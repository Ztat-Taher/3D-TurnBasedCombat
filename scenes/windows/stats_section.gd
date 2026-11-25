extends VBoxContainer
class_name StatsSection
## Header (portrait, name, level, HP bar) + stat radar for one party member.

## Lowest value each radar axis is scaled against, so a lone or weak party
## doesn't always fill the whole chart. The party's best value wins when higher.
const REFERENCE_FLOORS : Dictionary = {
	"max_health": 150,
	"attack": 20,
	"defense": 10,
	"agility": 15,
	"max_ap": 5,
}

@onready var portrait : TextureRect = $Header/Portrait
@onready var name_label : Label = $Header/InfoVBox/NameLabel
@onready var level_label : Label = $Header/InfoVBox/LevelLabel
@onready var hp_bar : ProgressBar = $Header/InfoVBox/HPBar
@onready var hp_label : Label = $Header/InfoVBox/HPBar/HPLabel
@onready var stats_graph : StatRadarGraph = $StatsGraph


## [param party] is used to scale the radar axes relative to the other members.
func setup(member : AllyPartyMember, party : Array[AllyPartyMember] = []) -> void:
	name_label.text = member.get_display_name()
	level_label.text = "Lv %d" % member.level

	hp_bar.max_value = 1.0
	hp_bar.value = member.get_hp_ratio()
	hp_label.text = "HP %s" % member.get_hp_text()

	portrait.texture = member.get_portrait()

	var references := REFERENCE_FLOORS.duplicate()
	for other in party:
		var other_stats := display_stats(other)
		for key in references:
			references[key] = maxi(int(references[key]), int(other_stats.get(key, 0)))
	stats_graph.set_stats(display_stats(member), references)


## Level-scaled stats, with HP taken from the same source as the HP bar.
static func display_stats(member : AllyPartyMember) -> Dictionary:
	var values := member.get_level_stats()
	if not values.is_empty():
		values["max_health"] = member.get_max_health()
	return values
