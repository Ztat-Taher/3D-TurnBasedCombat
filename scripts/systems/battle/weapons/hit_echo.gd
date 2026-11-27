class_name HitEcho
extends Node
## Self-contained runtime for weapons carrying a [HitEchoModule]. Spawned as
## a child of [WeaponSystem] by the module's create_runtime — the weapon
## system, card pipeline, and battle manager contain no echo-specific code.
##
## How it works:
## - Records the weapon's echo-node global transform every frame (rolling
##   buffer) so a ghost blade can replay the exact swing trajectory.
## - On each hostile [signal Battler.hit_moment], opens an echo session.
## - Listens to the generic [signal SignalBus.card_hit_resolved] combat event
##   and queues each card resolution (damage/strike/projectile) onto the
##   matching session.
## - After [member HitEchoModule.echo_delay], spawns a translucent clone of the weapon
##   model that plays back the recorded transforms; when playback reaches the
##   recorded hit offset it fires the replay — each queued card resolution
##   via [method CardBattleManager.replay_card_resolution] (its damage procs
##   the weapon like any attack), or the weapon procs alone for a non-card hit.
##
## Damage splitting is NOT handled here: [method WeaponSystem
## .get_damage_dealt_multiplier] already returns the module's
## echo_damage_fraction, so every damage instance (original and replayed)
## passes through the real pipeline at the same fraction.

## Weapon being echoed.
var weapon: Weapon = null
## The battler owning the weapon.
var owner_battler: Battler = null
## The owning weapon system (visual node + proc replay).
var weapon_system: WeaponSystem = null
## The HitEchoModule configuration this runtime was spawned from.
var module: HitEchoModule = null

## Rolling buffer of the echo node's global transforms, recorded every frame
## while the weapon's slash trail is emitting (or always, for trail-less
## visuals like ORB rigs). Entries: {"t", "xf", "trail"}.
var _frames: Array = []
## Timestamp (sec) of the last attack_start / attack_end signals (fallback
## swing bounds when the weapon has no trail).
var _swing_start: float = -1.0
var _attack_end: float = -1.0
## Timestamp (sec) of the last trail-emission start / stop — the "slash
## active" window that bounds ghost recording and playback.
var _slash_start: float = -1.0
var _slash_end: float = -1.0
var _was_emitting: bool = false
## Pending hit armed by hit_moment, claimed by the first card_hit_resolved
## of the same burst (or flushed after PENDING_TTL for non-card hits).
var _pending_hit: Dictionary = {}
var _pending_gen: int = 0
## The session currently collecting replay infos for one hit burst.
var _current_session: Dictionary = {}
## Pending ghost sessions: {"target", "hit_time", "swing_start", "end_time",
## "src_node", "replay_queue", "fired"}. One per landed hit.
var _sessions: Array = []
## Active ghost blade playbacks: {"node", "frames", "t0", "hit_offset",
## "duration", "elapsed", "session", "mat", "idx", "fired",
## "trail_nodes", "trail_prev"}.
var _playbacks: Array = []
## Trail-node lookup cache for the current echo node.
var _trail_cache_node: Node = null
var _trail_cache: Array = []
const MAX_BUFFER := 600    ## ~10s at 60fps
const MAX_SESSIONS := 4
const FRAME_KEEP := 4.0    ## seconds of history retained
const PENDING_TTL := 1.0   ## seconds a hit_moment waits for its card event
const BURST_WINDOW := 0.25 ## seconds same-burst resolutions may trail the first


func setup(p_weapon: Weapon, p_owner: Battler, p_weapon_system: WeaponSystem, p_module: HitEchoModule) -> void:
	weapon = p_weapon
	owner_battler = p_owner
	weapon_system = p_weapon_system
	module = p_module


func _ready() -> void:
	if weapon == null or owner_battler == null or weapon_system == null:
		push_warning("HitEcho on '%s' missing weapon, owner, or weapon system." % name)
		return
	if owner_battler.has_signal("hit_moment"):
		owner_battler.hit_moment.connect(_on_hit_moment)
	if owner_battler.has_signal("attack_start"):
		owner_battler.attack_start.connect(_on_attack_start)
	if owner_battler.has_signal("attack_end"):
		owner_battler.attack_end.connect(_on_attack_end)
	SignalBus.card_hit_resolved.connect(_on_card_hit_resolved)


func _exit_tree() -> void:
	if SignalBus.card_hit_resolved.is_connected(_on_card_hit_resolved):
		SignalBus.card_hit_resolved.disconnect(_on_card_hit_resolved)


# ---------------------------------------------------------------------------
# Session capture
# ---------------------------------------------------------------------------

func _on_hit_moment(attacker: Battler) -> void:
	if attacker != owner_battler:
		return
	var target: Battler = owner_battler.current_target
	if target == null or target == owner_battler or not is_instance_valid(target):
		return
	# Weapons are hostile tools: never echo ally/self hits (buffs, shields).
	if target.team == owner_battler.team:
		return
	# A previous pending hit that no card event claimed gets its own session
	# now — rapid successive hits each keep their echo.
	_flush_pending()
	_pending_hit = {"target": target, "time": Time.get_ticks_msec() / 1000.0}
	_pending_gen += 1
	_arm_pending_timer(_pending_gen)


## A card resolution arrived. The first one of a burst claims the pending
## hit_moment (preserving the original hit timing for swing bounds); later
## resolutions of the same burst join the open session's replay queue.
func _on_card_hit_resolved(info: Dictionary) -> void:
	if info.get("is_replay", false):
		return  # replays must not schedule further echoes
	var actor = info.get("actor")
	var target = info.get("target")
	if actor != owner_battler or target == null:
		return
	if target is Battler and (target as Battler).team == owner_battler.team:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var hit_time := now
	var session_target = target
	# Claim the pending hit_moment if it's still fresh — its timestamp is the
	# real hit frame even when the resolution lands later (projectiles).
	if not _pending_hit.is_empty() and now - float(_pending_hit.get("time", 0.0)) < PENDING_TTL:
		hit_time = float(_pending_hit["time"])
		session_target = _pending_hit.get("target", target)
		_pending_hit = {}
	# Same-burst resolutions (e.g. AOE per-target events, strike+effects)
	# join the open session instead of spawning extra ghosts.
	if not _current_session.is_empty() and not _current_session.get("fired", false) \
			and now - float(_current_session.get("hit_time", 0.0)) < BURST_WINDOW:
		(_current_session["replay_queue"] as Array).append(info)
		return
	_schedule_session(session_target, hit_time)
	if not _current_session.is_empty():
		(_current_session["replay_queue"] as Array).append(info)


## PENDING_TTL elapsed with no card event claiming the hit — a non-card
## attack (attack_anim etc.). Echo the weapon procs with an empty queue.
func _flush_pending() -> void:
	if _pending_hit.is_empty():
		return
	var p := _pending_hit
	_pending_hit = {}
	_schedule_session(p.get("target"), float(p.get("time", 0.0)))


func _arm_pending_timer(gen: int) -> void:
	await get_tree().create_timer(PENDING_TTL).timeout
	if not is_inside_tree() or gen != _pending_gen or _pending_hit.is_empty():
		return
	_flush_pending()


func _on_attack_start() -> void:
	_swing_start = Time.get_ticks_msec() / 1000.0
	_attack_end = -1.0


func _on_attack_end() -> void:
	_attack_end = Time.get_ticks_msec() / 1000.0


## Opens a ghost session for a landed hit. [param hit_time] is the original
## hit_moment timestamp when known (keeps swing bounds accurate for delayed
## resolutions like projectile impacts).
func _schedule_session(target: Battler, hit_time: float = -1.0) -> void:
	if _sessions.size() >= MAX_SESSIONS:
		_evict_session()
	var now := Time.get_ticks_msec() / 1000.0
	var ht := hit_time if hit_time > 0.0 else now
	# Prefer the recorded slash (trail) window; fall back to attack signals.
	var swing_start := _slash_start if _slash_start >= 0.0 \
		else (_swing_start if _swing_start >= 0.0 else ht - 0.6)
	var end_time := _slash_end if _slash_end > now \
		else (_attack_end if _attack_end > now else now + 0.5)
	_sessions.append({
		"target": target,
		"hit_time": ht,
		"swing_start": swing_start,
		"end_time": end_time,
		"src_node": _echo_node(),
		"replay_queue": [],
		"fired": false,
	})
	_current_session = _sessions[_sessions.size() - 1]
	_arm_session_timer(_current_session, module.echo_delay if module else 0.35)


## Makes room for a new session: drops the oldest fired one, or, when every
## session is still waiting, replays the oldest right away (without its ghost)
## so its hit is never lost.
func _evict_session() -> void:
	for i in _sessions.size():
		if _sessions[i].get("fired", false):
			_sessions.remove_at(i)
			return
	var oldest: Dictionary = _sessions.pop_front()
	oldest["fired"] = true
	if _current_session == oldest:
		_current_session = {}
	_fire_session_replay(oldest)


func _arm_session_timer(session: Dictionary, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree():
		return
	_fire_session(session)


# ---------------------------------------------------------------------------
# Ghost playback + replay
# ---------------------------------------------------------------------------

## The node whose transform is recorded for ghost playback: the socketed
## weapon model for BLADE weapons, the attuned orb holder for ORB weapons.
func _echo_node() -> Node3D:
	var visual := weapon_system.weapon_visual if weapon_system else null
	if visual == null or not is_instance_valid(visual):
		return null
	# ORB weapons echo the Attuned orb's motion — ask the OrbSystem module.
	var orb_sys := weapon_system.get_node_or_null("OrbSystem") as OrbSystem
	if orb_sys:
		var orb_node := orb_sys.echo_node()
		if orb_node:
			return orb_node
	return visual as Node3D


## Delay elapsed: snapshot the recorded swing, spawn the ghost blade playback.
func _fire_session(session: Dictionary) -> void:
	if session.get("fired", false) or not _sessions.has(session):
		return
	session["fired"] = true
	if _current_session == session:
		_current_session = {}
	var src: Node3D = session.get("src_node")
	if src == null or not is_instance_valid(src):
		src = _echo_node()
	if src == null or weapon == null or weapon.model_scene == null:
		_fire_session_replay(session)
		return
	# Slice recorded frames covering the swing (wind-up through follow-through
	# captured up to fire time).
	var fire_time := Time.get_ticks_msec() / 1000.0
	var frames: Array = []
	for f in _frames:
		var ft := float(f.get("t", 0.0))
		if ft >= float(session["swing_start"]) and ft <= fire_time:
			frames.append(f)
	if frames.is_empty():
		_fire_session_replay(session)
		return
	var ghost := src.duplicate() as Node3D
	if ghost == null:
		_fire_session_replay(session)
		return
	owner_battler.add_child(ghost)
	ghost.top_level = true
	ghost.global_transform = frames[0].get("xf")
	var duration := maxf(0.01, frames[frames.size() - 1]["t"] - float(session["swing_start"]))
	var entry := {
		"node": ghost,
		"frames": frames,
		"t0": float(session["swing_start"]),
		# Clamped to the recorded swing: a hit timed after the recording ends
		# still replays, at the end of the ghost's swing at the latest.
		"hit_offset": clampf(float(session["hit_time"]) - float(session["swing_start"]), 0.0, duration),
		"duration": duration,
		"elapsed": 0.0,
		"idx": 0,
		"fired": false,
		"session": session,
		"trail_nodes": _trail_nodes(ghost),
		"trail_prev": [],
	}
	_ghostify(ghost, entry)
	_playbacks.append(entry)


## Replays the hit through the real pipelines: each queued card resolution
## (whose replayed damage procs the weapon like any attack), or, for a hit
## with no card behind it (a counter), the weapon procs alone.
func _fire_session_replay(session: Dictionary) -> void:
	var target: Battler = session.get("target")
	if target == null or not is_instance_valid(target):
		return
	var queue: Array = session.get("replay_queue", [])
	if queue.is_empty():
		weapon_system.notify_attack_hit(target, {}, true)
		return
	# Merge projectile resolutions of the same card into a single replay
	# carrying every target — the original was one projectile (possibly AOE
	# emitting one event per target), so the ghost fires one too.
	var merged: Array = []
	var proj_by_card: Dictionary = {}
	for info in queue:
		if str(info.get("kind", "")) == "projectile" and info.get("card") != null:
			var card = info.get("card")
			if proj_by_card.has(card):
				var prev: Dictionary = proj_by_card[card]
				var targets: Array = prev.get("aoe_targets", [])
				if not targets.has(info.get("target")):
					targets.append(info.get("target"))
				prev["aoe_targets"] = targets
				continue
			info["aoe_targets"] = [info.get("target")]
			proj_by_card[card] = info
		merged.append(info)
	var cbm := get_tree().get_first_node_in_group("card_battle_manager")
	if cbm and cbm.has_method("replay_card_resolution"):
		for info in merged:
			cbm.replay_card_resolution(info)


## All WeaponTrail nodes under [param node] (the ghost clone carries the same
## trail setup as the source weapon).
func _trail_nodes(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	for c in node.find_children("*", "", true, false):
		if c is WeaponTrail:
			out.append(c)
	return out


## Trail nodes under [param node], cached per echo node (the echo node can
## change when an ORB weapon's attuned orb rotates).
func _echo_trails(node: Node) -> Array:
	if node != _trail_cache_node or not is_instance_valid(_trail_cache_node):
		_trail_cache_node = node
		_trail_cache = _trail_nodes(node)
	return _trail_cache


## Per-trail emission state, in the same order [_method _trail_nodes] returns.
func _trail_states(trails: Array) -> Array:
	var states: Array = []
	for t in trails:
		states.append(is_instance_valid(t) and (t as WeaponTrail)._is_emitting)
	return states


## Replays the recorded trail on/off transitions onto the ghost's trails, so
## the spectral blade emits its slash arc in the same moments the original did.
func _update_ghost_trails(pb: Dictionary) -> void:
	var trails: Array = pb.get("trail_nodes", [])
	if trails.is_empty():
		return
	var frames: Array = pb.get("frames", [])
	var idx := int(pb.get("idx", 0))
	var states: Array = frames[idx].get("trail", []) if idx >= 0 and idx < frames.size() else []
	var prev: Array = pb.get("trail_prev", [])
	while prev.size() < trails.size():
		prev.append(false)
	pb["trail_prev"] = prev
	for i in mini(trails.size(), states.size()):
		var want: bool = states[i]
		if want == prev[i]:
			continue
		prev[i] = want
		var t = trails[i]
		if not is_instance_valid(t):
			continue
		if want:
			t._on_trail_start()
		else:
			t._on_trail_end()


## Repaints every mesh under [param node] with a translucent ghost material
## stored on the playback entry for fading.
func _ghostify(node: Node, entry: Dictionary) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.85, 1.0, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.7, 1.0)
	mat.emission_energy_multiplier = 1.5
	for m in node.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = mat
	entry["mat"] = mat


## Positions [param node] at the recorded transform for the playback's current
## elapsed time, interpolating between the bracketing frames.
func _playback_transform(pb: Dictionary, node: Node3D) -> void:
	var frames: Array = pb.get("frames", [])
	if frames.is_empty():
		return
	var lt := float(pb["t0"]) + float(pb["elapsed"])
	var idx := int(pb.get("idx", 0))
	# Frames are time-ordered; advance the cached index forward.
	while idx + 1 < frames.size() and float(frames[idx + 1].get("t", 0.0)) <= lt:
		idx += 1
	pb["idx"] = idx
	var cur_t := float(frames[idx].get("t", 0.0))
	var cur_xf: Transform3D = frames[idx].get("xf")
	if idx + 1 >= frames.size() or lt <= cur_t:
		node.global_transform = cur_xf
		return
	var nxt_t := float(frames[idx + 1].get("t", 0.0))
	var nxt_xf: Transform3D = frames[idx + 1].get("xf")
	# Recording is gated to trail-active windows, so frames can have gaps
	# between slashes — snap across large gaps instead of drifting.
	if nxt_t - cur_t > 0.25:
		node.global_transform = cur_xf if lt - cur_t < (nxt_t - cur_t) * 0.5 else nxt_xf
		return
	var w := clampf((lt - cur_t) / maxf(0.0001, nxt_t - cur_t), 0.0, 1.0)
	node.global_transform = cur_xf.interpolate_with(nxt_xf, w)


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	# Record the echo node's transform — but only while the slash trail is
	# emitting, so ghosts spawn/animate/record exactly over the active slash
	# window. Trail-less visuals (ORB rigs) record continuously.
	if owner_battler and is_instance_valid(owner_battler):
		var node := _echo_node()
		if node and is_instance_valid(node):
			var trails := _echo_trails(node)
			var states := _trail_states(trails)
			var emitting := trails.is_empty() or states.has(true)
			if emitting != _was_emitting:
				if emitting:
					_slash_start = now
				else:
					_slash_end = now
				_was_emitting = emitting
			if emitting:
				_frames.append({"t": now, "xf": node.global_transform, "trail": states})
				if _frames.size() > MAX_BUFFER:
					_frames.pop_front()
	# Drop stale frames — but keep any frames an unfired session still needs:
	# a long echo_delay must not age the swing recording out before replay.
	var cutoff := now - FRAME_KEEP
	for sess in _sessions:
		if not sess.get("fired", false):
			cutoff = minf(cutoff, float(sess.get("swing_start", cutoff)) - 0.25)
	while not _frames.is_empty() and float(_frames[0].get("t", 0.0)) < cutoff:
		_frames.pop_front()
	# Advance ghost blade playbacks.
	for i in range(_playbacks.size() - 1, -1, -1):
		var pb: Dictionary = _playbacks[i]
		var node: Node3D = pb.get("node")
		if node == null or not is_instance_valid(node):
			_playbacks.remove_at(i)
			continue
		pb["elapsed"] = float(pb["elapsed"]) + delta
		_playback_transform(pb, node)
		_update_ghost_trails(pb)
		if not pb.get("fired", false) and float(pb["elapsed"]) >= float(pb["hit_offset"]):
			pb["fired"] = true
			_fire_session_replay(pb.get("session", {}))
		if float(pb["elapsed"]) >= float(pb["duration"]):
			# Fade out then free.
			var fade_t := clampf((float(pb["elapsed"]) - float(pb["duration"])) / 0.2, 0.0, 1.0)
			var mat: StandardMaterial3D = pb.get("mat")
			if mat:
				mat.albedo_color.a = 0.6 * (1.0 - fade_t)
			if fade_t >= 1.0:
				node.queue_free()
				_playbacks.remove_at(i)
