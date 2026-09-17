class_name NodeConfigManager
extends Resource

## Manages configurations for all node types
## Provides easy access to node type settings

var configs: Dictionary = {}

func _init() -> void:
	_initialize_default_configs()

func _initialize_default_configs() -> void:
	# Combat node
	var combat_config = NodeConfig.new()
	combat_config.node_type = "Combat"
	combat_config.difficulty_level = 1
	combat_config.reward_multiplier = 1.0
	combat_config.description = "Standard combat encounter"
	combat_config.node_color = Color(1, 0.2, 0.2, 1)
	combat_config.glow_color = Color(1, 0.5, 0.5, 1)
	combat_config.glow_intensity = 0.3
	configs["Combat"] = combat_config
	
	# Elite node
	var elite_config = NodeConfig.new()
	elite_config.node_type = "Elite"
	elite_config.difficulty_level = 2
	elite_config.reward_multiplier = 1.5
	elite_config.description = "Elite combat encounter"
	elite_config.node_color = Color(1, 0.5, 0, 1)
	elite_config.glow_color = Color(1, 0.7, 0.3, 1)
	elite_config.glow_intensity = 0.5
	configs["Elite"] = elite_config
	
	# Boss node
	var boss_config = NodeConfig.new()
	boss_config.node_type = "Boss"
	boss_config.difficulty_level = 3
	boss_config.reward_multiplier = 2.0
	boss_config.description = "Boss encounter"
	boss_config.node_color = Color(0.5, 0, 0, 1)
	boss_config.glow_color = Color(1, 0.3, 0.3, 1)
	boss_config.glow_intensity = 0.7
	configs["Boss"] = boss_config
	
	# Rest node
	var rest_config = NodeConfig.new()
	rest_config.node_type = "Rest"
	rest_config.difficulty_level = 0
	rest_config.reward_multiplier = 0.5
	rest_config.description = "Rest and recover"
	rest_config.node_color = Color(0.2, 0.8, 0.2, 1)
	rest_config.glow_color = Color(0.5, 1, 0.5, 1)
	rest_config.glow_intensity = 0.4
	configs["Rest"] = rest_config
	
	# Shop node
	var shop_config = NodeConfig.new()
	shop_config.node_type = "Shop"
	shop_config.difficulty_level = 0
	shop_config.reward_multiplier = 0.0
	shop_config.description = "Visit the shop"
	shop_config.node_color = Color(1, 0.8, 0, 1)
	shop_config.glow_color = Color(1, 0.9, 0.3, 1)
	shop_config.glow_intensity = 0.5
	configs["Shop"] = shop_config
	
	# Treasure node
	var treasure_config = NodeConfig.new()
	treasure_config.node_type = "Treasure"
	treasure_config.difficulty_level = 0
	treasure_config.reward_multiplier = 1.0
	treasure_config.description = "Find treasure"
	treasure_config.node_color = Color(0, 0.8, 1, 1)
	treasure_config.glow_color = Color(0.5, 0.9, 1, 1)
	treasure_config.glow_intensity = 0.6
	configs["Treasure"] = treasure_config

func get_config(node_type: String) -> NodeConfig:
	if configs.has(node_type):
		return configs[node_type]
	# Return default combat config if type not found
	return configs["Combat"]

func get_all_types() -> Array:
	return configs.keys()

func register_config(config: NodeConfig) -> void:
	configs[config.node_type] = config