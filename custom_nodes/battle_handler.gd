class_name BattleHandler
extends Node

signal player_won
signal enemy_won

@export var game_state: GameState
@export var game_area: PlayArea
@export var game_area_unit_grid: UnitGrid
@export var battle_unit_grid: UnitGrid
@export var trait_tracker: TraitTracker

var battle_seed: int = 0
var battle_winner_team: int = -1

@onready var scene_spawner: SceneSpawner = $SceneSpawner


func _ready() -> void:
	game_state.changed.connect(_on_game_state_changed)


func _setup_battle_unit(unit_coord: Vector2i, new_unit: BattleUnit) -> void:
	new_unit.stats.reset_health()
	new_unit.stats.reset_mana()
	new_unit.global_position = game_area.get_global_from_tile(unit_coord) + Vector2(0, -Arena.QUARTER_CELL_SIZE.y)
	new_unit.tree_exited.connect(_on_battle_unit_died)
	battle_unit_grid.add_unit(unit_coord, new_unit)


func _add_items(unit: Unit, new_unit: BattleUnit) -> void:
	unit.item_handler.copy_items_to(new_unit.item_handler)	
	new_unit.item_handler.items_changed.connect(_on_battle_unit_items_changed.bind(unit, new_unit))
	new_unit.item_handler.item_removed.connect(_on_battle_unit_item_removed.bind(new_unit))
	
	for item: Item in new_unit.item_handler.equipped_items:
		item.apply_modifiers(new_unit)


func _add_trait_bonuses(new_unit: BattleUnit) -> void:
	for unit_trait: Trait in new_unit.stats.traits:
		if trait_tracker.active_traits.has(unit_trait):
			var trait_bonus := unit_trait.get_active_bonus(trait_tracker.unique_traits[unit_trait])
			if trait_bonus:
				trait_bonus.apply_bonus(new_unit)


func _clean_up_fight() -> void:
	get_tree().call_group("player_units", "queue_free")
	get_tree().call_group("enemy_units", "queue_free")
	get_tree().call_group("unit_abilities", "queue_free")
	get_tree().call_group("units", "show")


func _prepare_fight() -> void:
	get_tree().call_group("units", "hide")

	for unit_coord: Vector2i in game_area_unit_grid.get_all_occupied_tiles():
		var unit: Unit = game_area_unit_grid.units[unit_coord]
		var new_unit := scene_spawner.spawn_scene(battle_unit_grid) as BattleUnit
		new_unit.add_to_group("player_units")
		new_unit.stats = unit.stats
		new_unit.stats.team = UnitStats.Team.PLAYER
		_setup_battle_unit(unit_coord, new_unit)
		_add_items(unit, new_unit)
		_add_trait_bonuses(new_unit)

	# Note: Opponent units are now spawned by arena.gd from SpacetimeDB data

	# Safety check: Don't start battle if no enemies
	if get_tree().get_node_count_in_group("enemy_units") == 0:
		print("Warning: No enemy units found. Battle cancelled.")
		game_state.current_phase = GameState.Phase.PREPARATION
		_clean_up_fight()
		return


	UnitNavigation.update_occupied_tiles()
	var battle_units := get_tree().get_nodes_in_group("player_units") + get_tree().get_nodes_in_group("enemy_units")

	# Deterministic shuffle using battle seed (Fisher-Yates algorithm)
	var battle_rng := RandomNumberGenerator.new()
	battle_rng.seed = battle_seed if battle_seed != 0 else hash(Time.get_ticks_msec())

	for i in range(battle_units.size() - 1, 0, -1):
		var j = battle_rng.randi_range(0, i)
		var temp = battle_units[i]
		battle_units[i] = battle_units[j]
		battle_units[j] = temp

	for battle_unit: BattleUnit in battle_units:
		battle_unit.unit_ai.enabled = true

		for item: Item in battle_unit.item_handler.equipped_items:
			item.apply_bonus_effect(battle_unit)


func _on_battle_unit_died() -> void:
	# We already concluded the battle!
	# or we are quitting the game
	if not get_tree() or game_state.current_phase == GameState.Phase.PREPARATION:
		return

	var enemy_count = get_tree().get_node_count_in_group("enemy_units")
	var player_count = get_tree().get_node_count_in_group("player_units")

	if enemy_count == 0 and player_count == 0:
		# Draw - both last units died simultaneously, player wins by default
		battle_winner_team = UnitStats.Team.PLAYER
		game_state.current_phase = GameState.Phase.PREPARATION
		player_won.emit()
	elif enemy_count == 0:
		battle_winner_team = UnitStats.Team.PLAYER
		game_state.current_phase = GameState.Phase.PREPARATION
		player_won.emit()
	elif player_count == 0:
		battle_winner_team = UnitStats.Team.ENEMY
		game_state.current_phase = GameState.Phase.PREPARATION
		enemy_won.emit()


func _on_battle_unit_items_changed(unit: Unit, battle_unit: BattleUnit) -> void:
	battle_unit.item_handler.copy_items_to(unit.item_handler)
	
	for item: Item in battle_unit.item_handler.equipped_items:
		item.remove_modifiers(battle_unit)
		item.apply_modifiers(battle_unit)


func _on_battle_unit_item_removed(item: Item, battle_unit: BattleUnit) -> void:
	item.remove_modifiers(battle_unit)


func _on_game_state_changed() -> void:
	match game_state.current_phase:
		GameState.Phase.PREPARATION:
			_clean_up_fight()
		GameState.Phase.BATTLE:
			_prepare_fight()


func set_battle_seed(seed: int) -> void:
	battle_seed = seed
	print("Battle seed set to: %d" % battle_seed)


func get_battle_result() -> Dictionary:
	return {
		"winner_team": battle_winner_team,
		"hash": _calculate_battle_hash()
	}


func _calculate_battle_hash() -> int:
	var hash_value = 0
	for unit in get_tree().get_nodes_in_group("player_units"):
		if unit is BattleUnit:
			hash_value ^= int(unit.stats.current_health)
	for unit in get_tree().get_nodes_in_group("enemy_units"):
		if unit is BattleUnit:
			hash_value ^= int(unit.stats.current_health)
	return hash_value
