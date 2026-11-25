class_name Weapon
extends Item
## An equippable weapon. Lives in an [AllyPartyMember]'s inventory as a
## non-stackable item; the equipped one is referenced by
## [AllyPartyMember.equipped_weapon] and drives a [WeaponSystem] on the
## spawned [Battler].
##
## This resource holds only intrinsic weapon data: model, stats, generic
## effects, progression, and combat multipliers. Special mechanics are NOT
## fields here — they are composed via [member modules], an array of
## [WeaponModule] resources (OrbModule, HitEchoModule, ...) that each spawn
## their own runtime node under the weapon system.

## Equip category. Derived from the weapon's modules — a weapon with an
## [OrbModule] is ORB, one with a [GunModule] is GUN, everything else is
## BLADE. Used for ally weapon type-locking ([AllyPartyMember.weapon_type]).
enum WType {
	BLADE,  ## Melee weapon: handheld model + data-driven WeaponEffect list.
	ORB,    ## Orbiting relic: cyclic OrbDefinition roster via OrbModule.
	GUN,    ## Firearm: handheld gun model; gun mechanics hang off GunModule.
}

## The weapon's model/visual scene. For socketed weapons this is the handheld
## prop (instanced into the battler's weapon socket); for root-space rigs it
## is instanced under the weapon system or reused from the battler's scene.
@export var model_scene: PackedScene = null

@export_group("Progression")
@export var weapon_xp: int = 0
@export var weapon_level: int = 1
@export var xp_per_level: int = 50
@export var max_level: int = 5

@export_group("Effects")
## Generic weapon effects evaluated on their triggers — the baseline mechanic
## every weapon can carry regardless of modules.
@export var effects: Array[WeaponEffect] = []

@export_group("Stat Modifiers")
## Same shape as Vestige stat modifiers — applied to the battler's stats
## while this weapon is equipped (each battle).
@export var max_health_bonus: int = 0
@export var attack_bonus: int = 0
@export var defense_bonus: int = 0
@export var agility_bonus: int = 0
@export var max_ap_bonus: int = 0
@export var ap_regen_bonus: int = 0

@export var max_health_percent: float = 0.0
@export var attack_percent: float = 0.0
@export var defense_percent: float = 0.0
@export var agility_percent: float = 0.0

@export_group("Combat")
## Scales all damage this battler deals (consumed by damage_calculation).
@export var damage_dealt_multiplier: float = 1.0
## Scales all damage this battler receives (consumed by take_damage).
@export var damage_taken_multiplier: float = 1.0

@export_group("Modules")
## Composed weapon mechanics. Each module is a [WeaponModule] resource that
## spawns its own runtime node (OrbSystem, HitEcho, ...) and may contribute
## combat modifiers. Add a mechanic = add a module here — no code changes.
@export var modules: Array[WeaponModule] = []


func _init() -> void:
	# Weapons are equipment, not consumables.
	is_stackable = false
	is_battle_item = false
	can_be_sold = false


## The weapon's equip category, derived from its modules: ORB when an
## [OrbModule] is present, GUN when a [GunModule] is present, BLADE otherwise.
func equip_kind() -> WType:
	for mod in modules:
		if mod is OrbModule:
			return WType.ORB
		if mod is GunModule:
			return WType.GUN
	return WType.BLADE


## First HitEcho module on this weapon, or null.
func get_hit_echo_module() -> HitEchoModule:
	for mod in modules:
		if mod is HitEchoModule:
			return mod
	return null


## Adds XP and applies level-ups. Returns true when a level was gained.
func add_weapon_xp(amount: int) -> bool:
	if amount <= 0 or weapon_level >= max_level:
		return false
	weapon_xp += amount
	var leveled := false
	while weapon_level < max_level and weapon_xp >= xp_per_level * weapon_level:
		weapon_level += 1
		leveled = true
	return leveled
