class_name CardBattleConfig
extends Resource
## Configuration for card-based combat system
## Resource-driven balance parameters for card combat integration

@export_group("Action Points System")
## Action Points granted per turn (used as default fallback if battler has no stats)
@export var ap_per_turn: int = 3
## Maximum Action Points a player can have (used as default fallback if battler has no stats)
@export var max_ap: int = 3
## Action Points cost to draw an extra card from the draw pile
@export var draw_card_ap_cost: int = 1

@export_group("Deck Settings")
## Number of cards in initial hand
@export var initial_hand_size: int = 4
## Maximum number of cards in hand
@export var max_hand_size: int = 10
## Maximum number of cards on the board (if using board mechanics)
@export var max_board_size: int = -1  # -1 = unlimited

@export_group("QTE Settings")
## Whether QTEs are enabled for card execution
@export var qte_enabled: bool = true
## Default QTE difficulty (0.0 = easy, 1.0 = hard)
@export_range(0.0, 1.0, 0.1) var default_qte_difficulty: float = 0.5
## Damage multiplier for successful QTE
@export_range(1.0, 2.0, 0.1) var qte_success_multiplier: float = 1.5
## Damage multiplier for failed QTE
@export_range(0.5, 1.0, 0.1) var qte_failure_multiplier: float = 0.8

@export_group("Card Balance")
## Base damage multiplier for attack cards
@export_range(0.5, 2.0, 0.1) var attack_damage_multiplier: float = 1.0
## Base healing multiplier for heal cards
@export_range(0.5, 2.0, 0.1) var heal_multiplier: float = 1.0

@export_group("Multi-Strike Chaining")
## Seconds trimmed from a multi-strike clip so the NEXT strike's animation travel is
## issued while the current clip is still playing. Keeping this above 0.0 stops the
## combat_actions sub-machine from falling back to its End state (and the actor from
## dropping back into idle) between combo hits. 0.0 = always wait for the full clip.
## Per-card overrides live in CardConfig.strike_chain_leads.
@export_range(0.0, 1.0, 0.05) var multi_strike_chain_lead: float = 0.2
