class_name CardBattleConfig
extends Resource
## Configuration for card-based combat system
## Resource-driven balance parameters for card combat integration

@export_group("Action Points System")
## (A battler's AP and its regen come from its own stats.)
## Action Points cost to draw an extra card from the draw pile
@export var draw_card_ap_cost: int = 1

@export_group("Deck Settings")
## Number of cards in initial hand
@export var initial_hand_size: int = 4
## Maximum number of cards in hand
@export var max_hand_size: int = 10
## (QTE settings and multipliers live in the QTE config.)

@export_group("Multi-Strike Timing")
## Global default strike timing offset (seconds).
##   > 0  → delay: pause this many seconds AFTER clip ends before next strike.
##   = 0  → seamless: next strike fires exactly at clip end.
##   < 0  → lead: fire |value| seconds BEFORE clip ends (overlap).
## Per-card overrides live in CardConfig.strike_timing.
@export_range(-1.0, 1.0, 0.05) var default_strike_timing: float = -0.2
