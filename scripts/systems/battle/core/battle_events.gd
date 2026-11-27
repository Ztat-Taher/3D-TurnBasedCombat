class_name BattleEvents
## Names of the battle lifecycle events a [Battler] is told about through
## [method Battler.notify_battle_event].
##
## Battle code only ever sends these generic events. Each passive system a
## battler carries (vestiges, and anything added later) maps them to its own
## triggers, so the battle and card code never needs to know those systems.
##
## Context keys every event gets: "battle_manager". Event-specific keys are
## listed next to each event.

## The battle has begun (battlers placed, saved HP restored).
const COMBAT_START := &"combat_start"
## The battle has ended (any outcome).
const COMBAT_END := &"combat_end"
## This battler's turn starts.
const TURN_START := &"turn_start"
## This battler's turn ends.
const TURN_END := &"turn_end"
## This battler played a card. "card", "target", "targets" (everyone it
## resolves on: an AOE card's targets, else [target])
const CARD_PLAYED := &"card_played"
## This battler lost HP to a hit (after dodges, shields and multipliers; not
## sent for hits that did nothing). "attacker", "damage" (HP lost),
## "damage_type", "element", "is_attack" (false for bonus damage: weapon
## procs, vestiges, DOTs)
const DAMAGE_TAKEN := &"damage_taken"
## This battler's hit made a target lose HP. "target", "damage" (HP lost),
## "damage_type", "element", "is_attack"
const DAMAGE_DEALT := &"damage_dealt"
## A hit is about to defeat this battler. "attacker", "damage". A listener
## that saves the battler sets "revive_health" (> 0) to the HP it is left
## with instead of being defeated; the highest value wins.
const LETHAL_DAMAGE := &"lethal_damage"
## This battler regained HP. "heal_amount" (HP regained)
const HEALED := &"healed"
## This battler's HP changed. "old_health", "new_health", "max_health"
const HEALTH_CHANGED := &"health_changed"
## A state was put on this battler. "state", "state_name", "source" (the
## battler that applied it, or null)
const STATE_APPLIED := &"state_applied"
## This battler put a state on another battler. "target", "state", "state_name"
const STATE_INFLICTED := &"state_inflicted"
## A state was taken off this battler. "state", "state_name"
const STATE_REMOVED := &"state_removed"
## A battler of the opposing team was defeated. "defeated", "attacker" (may
## be null or another battler)
const ENEMY_DEFEATED := &"enemy_defeated"
