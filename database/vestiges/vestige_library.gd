@tool
class_name VestigeLibrary
extends Resource
## Library containing all available vestiges organized by rarity

@export var common_vestiges: Array[Vestige] = []
@export var uncommon_vestiges: Array[Vestige] = []
@export var rare_vestiges: Array[Vestige] = []
@export var boss_vestiges: Array[Vestige] = []
@export var event_vestiges: Array[Vestige] = []
@export var shop_vestiges: Array[Vestige] = []


## Get random vestige from specified rarity pool
func get_random_vestige(rarity: Vestige.Rarity) -> Vestige:
	var pool := _get_pool_by_rarity(rarity)
	if pool.is_empty():
		push_warning("VestigeLibrary: No vestiges available for rarity: %s" % Vestige.Rarity.keys()[rarity])
		return null
	
	return pool.pick_random()


## Get all vestiges from specified rarity pool
func get_vestiges_by_rarity(rarity: Vestige.Rarity) -> Array[Vestige]:
	return _get_pool_by_rarity(rarity)


## Get boss vestige choices (typically 3 for player selection)
## excluding: Array of vestiges already owned (to avoid duplicates)
func get_boss_vestige_choices(excluding: Array[Vestige] = []) -> Array[Vestige]:
	var available := boss_vestiges.filter(func(v): return not v in excluding)
	
	# Shuffle and return up to 3 choices
	available.shuffle()
	return available.slice(0, mini(3, available.size()))


## Get available vestiges from specific source type
func get_vestiges_by_source(can_drop_from_elites: bool = true, can_drop_from_bosses: bool = true, 
		can_drop_from_treasure: bool = true, can_drop_from_events: bool = true, 
		can_be_purchased: bool = true, can_drop_from_rest_sites: bool = false) -> Array[Vestige]:
	var all_vestiges: Array[Vestige] = []
	
	for vestige in common_vestiges + uncommon_vestiges + rare_vestiges:
		if _matches_source(vestige, can_drop_from_elites, can_drop_from_bosses, 
				can_drop_from_treasure, can_drop_from_events, can_be_purchased, can_drop_from_rest_sites):
			all_vestiges.append(vestige)
	
	return all_vestiges


## Add a vestige to the appropriate rarity pool
func add_vestige(vestige: Vestige) -> void:
	match vestige.rarity:
		Vestige.Rarity.COMMON:
			if not vestige in common_vestiges:
				common_vestiges.append(vestige)
		Vestige.Rarity.UNCOMMON:
			if not vestige in uncommon_vestiges:
				uncommon_vestiges.append(vestige)
		Vestige.Rarity.RARE:
			if not vestige in rare_vestiges:
				rare_vestiges.append(vestige)
		Vestige.Rarity.BOSS:
			if not vestige in boss_vestiges:
				boss_vestiges.append(vestige)
		Vestige.Rarity.EVENT:
			if not vestige in event_vestiges:
				event_vestiges.append(vestige)
		Vestige.Rarity.SHOP:
			if not vestige in shop_vestiges:
				shop_vestiges.append(vestige)


## Remove a vestige from the library
func remove_vestige(vestige: Vestige) -> void:
	common_vestiges.erase(vestige)
	uncommon_vestiges.erase(vestige)
	rare_vestiges.erase(vestige)
	boss_vestiges.erase(vestige)
	event_vestiges.erase(vestige)
	shop_vestiges.erase(vestige)


## Get total count of all vestiges in library
func get_total_count() -> int:
	return common_vestiges.size() + uncommon_vestiges.size() + rare_vestiges.size() + \
		boss_vestiges.size() + event_vestiges.size() + shop_vestiges.size()


## Helper: Get pool array by rarity
func _get_pool_by_rarity(rarity: Vestige.Rarity) -> Array[Vestige]:
	match rarity:
		Vestige.Rarity.COMMON:
			return common_vestiges
		Vestige.Rarity.UNCOMMON:
			return uncommon_vestiges
		Vestige.Rarity.RARE:
			return rare_vestiges
		Vestige.Rarity.BOSS:
			return boss_vestiges
		Vestige.Rarity.EVENT:
			return event_vestiges
		Vestige.Rarity.SHOP:
			return shop_vestiges
		_:
			return []


## Helper: Check if vestige matches source criteria
func _matches_source(vestige: Vestige, elites: bool, bosses: bool, treasure: bool, 
		events: bool, purchased: bool, rest: bool) -> bool:
	if elites and vestige.can_drop_from_elites:
		return true
	if bosses and vestige.can_drop_from_bosses:
		return true
	if treasure and vestige.can_drop_from_treasure:
		return true
	if events and vestige.can_drop_from_events:
		return true
	if purchased and vestige.can_be_purchased:
		return true
	if rest and vestige.can_drop_from_rest_sites:
		return true
	return false
