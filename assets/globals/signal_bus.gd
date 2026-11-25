extends Node

#===============================================================================
# Battler Targeting Controls
#-------------------------------------------------------------------------------
@warning_ignore("unused_signal")
signal allow_select_target(can_target:bool)
@warning_ignore("unused_signal")
signal select_target(battler:Battler)
@warning_ignore("unused_signal")
signal hover_target(battler:Battler)
@warning_ignore("unused_signal")
signal clear_default_selection
@warning_ignore("unused_signal")
signal counter_attack_started
@warning_ignore("unused_signal")
signal counter_attack_finished

#===============================================================================
# Combat Events
#-------------------------------------------------------------------------------
## Emitted by CardBattleManager whenever a card resolves a combat effect
## (damage, states, weapon procs). info: {"kind": "effects"|"strike"|"projectile",
## "card", "actor", "target", "strike_index", "damage_multiplier",
## "qte_multiplier"}. Weapon systems and other listeners decide what to do —
## the card pipeline stays mechanic-agnostic.
@warning_ignore("unused_signal")
signal card_hit_resolved(info: Dictionary)
