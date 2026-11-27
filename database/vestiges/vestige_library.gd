@tool
class_name VestigeLibrary
extends Resource
## Every vestige the game can hand out, and how rewards pick one.

## All obtainable vestiges (each one's rarity and drop flags live on it).
@export var vestiges: Array[Vestige] = []

## Relative chance of each rarity in [method roll]; a rarity with no weight
## never rolls (e.g. boss vestiges come from boss rewards with their own weights).
@export var rarity_weights: Dictionary[Vestige.Rarity, float] = {
	Vestige.Rarity.COMMON: 70.0,
	Vestige.Rarity.UNCOMMON: 25.0,
	Vestige.Rarity.RARE: 5.0,
}


## Picks a random vestige that drops from [param source] and passes
## [param is_available] (e.g. "the run can still gain it"). The rarity is
## rolled by weight among the rarities that still have a candidate, so a
## used-up rarity never turns a roll into "nothing". [param weights] overrides
## [member rarity_weights]. Returns null when nothing qualifies.
func roll(source: Vestige.DropSource, is_available: Callable = Callable(), weights: Dictionary = {}) -> Vestige:
	var use_weights: Dictionary = weights if not weights.is_empty() else rarity_weights
	var by_rarity := {}
	for vestige in vestiges:
		if vestige == null or not vestige.can_drop_from(source):
			continue
		if is_available.is_valid() and not is_available.call(vestige):
			continue
		if float(use_weights.get(vestige.rarity, 0.0)) <= 0.0:
			continue
		if not by_rarity.has(vestige.rarity):
			by_rarity[vestige.rarity] = []
		by_rarity[vestige.rarity].append(vestige)
	if by_rarity.is_empty():
		return null
	var total := 0.0
	for rarity in by_rarity:
		total += float(use_weights[rarity])
	var pick := randf() * total
	for rarity in by_rarity:
		pick -= float(use_weights[rarity])
		if pick <= 0.0:
			return by_rarity[rarity].pick_random()
	return by_rarity[by_rarity.keys().back()].pick_random()
