extends Node

# Must be set/used to get player turn.
var activeBattler

# These variables do not NEED to have stuff filled out. 
# These variables would/can be a place to define what sound an animation player will play.
# It's goal is to not keep data hard to change, And keeping reuseability.
var hit_sound: AudioStream
var critical_sound: AudioStream
var miss_sound : AudioStream
var escape_sound: AudioStream
var enemy_defeat_sound: AudioStream = null
var boss_defeat_sound: AudioStream = null
var ally_party: int = 0

# Set damage calculation type (based on other game damage calcs)
var Global_Damage_Calc_Type : Damage_Calc_Type = Damage_Calc_Type.PKMN

enum Elements {
	Physical = 0,
	EARTH = 1,
	AIR = 2,
	FIRE = 3,
	WATER = 4,
	MAGIC = 5,
	NONE = 6, # In theory this would ensure everyone can be effected.
	ENDLIST}

enum SkillTypes {
	SKILLS = 0,
	HEALING = 1, #Placerholder.
	HEALTHREDUCTIONATTACKS = 2,
	ENDLIST}

enum ItemTypes {
	HEALING = 0,
	THROWABLE = 1,
	BUFFS = 2,
	ENDLIST}

enum WeaponTypes {
	HANDS = 0,
	SWORD = 1,
	AXE = 2,
	BOW = 3,
	CLAWS = 4,
	UNDEFINED = 5,
	ENDLIST}

enum ArmorTypes {
	REGULARARMOR = 0,
	LIGHTARMOR = 1,
	MAGICARMOR = 2,
	HEAVYARMOR = 3,
	METALARMOR = 4,
	ENDLIST}

enum Difficulties {
	EASY = 0,
	NORMAL = 1,
	HARD = 2,
	ENDLIST}

enum Damage_Calc_Type {
	PKMN = 0,
	DRGNQST = 1
}

# Element colors for battle affliction text display (BBCode format)
var element_colors = {
	0: Color.GRAY,                    # Physical
	1: Color.DARK_GOLDENROD,         # EARTH
	2: Color.WHITE_SMOKE,            # AIR
	3: Color.RED,                    # FIRE
	4: Color.SKY_BLUE,               # WATER
	5: Color.MAGENTA,                # MAGIC
	6: Color.WHITE                   # NONE
}

# Battle Configuration - Set before starting a battle
var current_battle_config: BattleConfig = null

# Current difficulty for this session
var Global_Difficulty: int = Difficulties.NORMAL

# Start Functions down here.


# Find the first battler, This may be set to allow anyone to go first later. For situations
# Where they get hit first before battle.
func set_active_battler(character):
	activeBattler = character

## Set the current battle configuration
func set_battle_config(config: BattleConfig) -> void:
	current_battle_config = config


## Get the current battle configuration
func get_battle_config() -> BattleConfig:
	return current_battle_config

## Clear battle configuration after battle ends
func clear_battle_config() -> void:

	current_battle_config = null
