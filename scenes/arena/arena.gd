class_name Arena
extends Node2D

const CELL_SIZE := Vector2(32, 32)
const HALF_CELL_SIZE := Vector2(16, 16)
const QUARTER_CELL_SIZE := Vector2(8, 8)

@export var arena_music_stream: AudioStream

@onready var game_area: PlayArea = $GameArea
@onready var battle_grid: UnitGrid = $GameArea/BattleUnitGrid
@onready var bench_items: BenchItems = $BenchItems
@onready var sell_portal: SellPortal = $SellPortal
@onready var unit_mover: UnitMover = $UnitMover
@onready var unit_spawner: UnitSpawner = $UnitSpawner
@onready var unit_combiner: UnitCombiner = $UnitCombiner
@onready var trait_tracker: TraitTracker = $TraitTracker
@onready var shop: Shop = %Shop
@onready var traits: Traits = %Traits
@onready var battle_handler: BattleHandler = $BattleHandler
@onready var game_state: GameState = preload("res://data/game_state/game_state.tres")
@onready var game_area_grid: UnitGrid = $GameArea/ArenaUnitGrid

# Battle unit scene for spawning opponents
const BATTLE_UNIT_SCENE = preload("res://scenes/battle_unit/battle_unit.tscn")


func _ready() -> void:
	unit_spawner.unit_spawned.connect(unit_mover.setup_unit)
	unit_spawner.unit_spawned.connect(sell_portal.setup_unit)
	unit_spawner.unit_spawned.connect(unit_combiner.queue_unit_combination_update.unbind(1))
	shop.unit_bought.connect(unit_spawner.spawn_unit)
	trait_tracker.traits_changed.connect(traits.update_traits)
	sell_portal.unit_sold.connect(bench_items.return_items_from_unit)

	# Multiplayer hooks
	MultiplayerManager.match_found.connect(_on_match_found)
	MultiplayerManager.both_players_ready.connect(_on_both_players_ready)
	MultiplayerManager.match_completed.connect(_on_match_completed)
	game_area_grid.unit_grid_changed.connect(_on_board_changed)
	battle_handler.player_won.connect(_on_player_won)
	battle_handler.enemy_won.connect(_on_enemy_won)

	MusicPlayer.play(arena_music_stream)
	UnitNavigation.initialize(battle_grid, game_area)


# ===== Multiplayer Handlers =====

func _on_match_found(match_id: int, opponent: String, seed: int, is_p1: bool):
	print("🎮 Match found! Opponent: %s, Seed: %d, IsPlayer1: %s" % [opponent, seed, is_p1])
	print("  Match ID: %d" % match_id)
	print("  MultiplayerManager state: %d" % MultiplayerManager.state)
	# Transition to preparation phase
	# Player can now arrange units and buy from shop

	# IMPORTANT: Sync any units that were already placed on the board BEFORE matching
	print("  🔄 Syncing existing board state to server...")
	_on_board_changed()

	# Wait a moment for board sync to complete, then auto-mark ready
	await get_tree().create_timer(0.3).timeout
	print("  ✅ Board synced, auto-marking ready...")
	MultiplayerManager.mark_ready(true)


func _on_board_changed():
	print("🔄 _on_board_changed called!")
	print("  Current state: %d" % MultiplayerManager.state)
	print("  Match ID: %d" % MultiplayerManager.current_match_id)

	# Sync board state to server when units are moved/added/removed
	if MultiplayerManager.state != MultiplayerManager.MatchmakingState.IN_MATCH:
		print("  ❌ Not in match state, skipping sync")
		return

	print("  ✅ In match state, syncing board...")

	# Clear previous board state on server
	MultiplayerManager.clear_my_board()

	# Sync all units on game area (not bench)
	var occupied_tiles = game_area_grid.get_all_occupied_tiles()
	print("  📦 Found %d occupied tiles" % occupied_tiles.size())

	for tile in occupied_tiles:
		var unit = game_area_grid.units[tile]
		if not unit or not "stats" in unit:
			print("  ⚠️ Tile %s has invalid unit" % tile)
			continue

		var unit_stats = unit.stats
		if not unit_stats:
			print("  ⚠️ Unit at tile %s has no stats!" % tile)
			continue

		# Use the name property directly instead of parsing resource_path
		# (resource_path can be empty for duplicated resources)
		var unit_name = unit_stats.name.to_lower().replace(" ", "_")

		print("  📤 Syncing unit: %s at (%d, %d)" % [unit_name, tile.x, tile.y])

		# Send unit to server
		MultiplayerManager.update_unit(
			unit_name,
			unit_stats.tier,
			tile.x,
			tile.y,
			false  # on_bench = false for game area units
		)

	print("  ✅ Board sync complete!")


func _on_both_players_ready():
	print("Both players ready! Loading opponent's board...")

	# Load opponent units from server
	var opponent_units = MultiplayerManager.get_opponent_units()

	# Spawn opponent's units
	_spawn_opponent_units(opponent_units)

	# Set battle seed for deterministic battle
	battle_handler.set_battle_seed(MultiplayerManager.battle_seed)

	# Start battle
	game_state.current_phase = GameState.Phase.BATTLE


func _spawn_opponent_units(opponent_units: Array):
	print("Spawning %d opponent units..." % opponent_units.size())

	# First pass: Calculate opponent's trait composition
	var opponent_trait_counts = {}
	for unit_data in opponent_units:
		if unit_data.on_bench:
			continue

		var unit_stats = _get_unit_stats_by_name(unit_data.unit_name)
		if unit_stats:
			for unit_trait in unit_stats.traits:
				if not opponent_trait_counts.has(unit_trait):
					opponent_trait_counts[unit_trait] = 0
				opponent_trait_counts[unit_trait] += 1

	print("  Opponent trait composition: %s" % str(opponent_trait_counts))

	# Second pass: Spawn units and apply trait bonuses
	for unit_data in opponent_units:
		if unit_data.on_bench:
			continue  # Only spawn arena units, not bench

		# Load unit stats by name
		var unit_stats = _get_unit_stats_by_name(unit_data.unit_name)
		if not unit_stats:
			printerr("Failed to load unit stats for: %s" % unit_data.unit_name)
			continue

		# Create battle unit
		var battle_unit = BATTLE_UNIT_SCENE.instantiate()
		battle_unit.add_to_group("enemy_units")

		# Add to scene tree first (required for @onready variables to initialize)
		battle_handler.add_child(battle_unit)

		# Prepare stats with correct team and tier BEFORE assigning
		# (so _set_stats() sets up collision layers correctly)
		var modified_stats = unit_stats.duplicate()
		modified_stats.tier = unit_data.tier
		modified_stats.team = UnitStats.Team.ENEMY

		# Now assign the fully configured stats
		battle_unit.stats = modified_stats

		# Override sprite to use rogues for PvP (both players should look like players)
		battle_unit.skin.texture = UnitStats.TEAM_SPRITESHEET[UnitStats.Team.PLAYER]
		battle_unit.skin.flip_h = false  # Opponent faces left

		# Mirror position horizontally (flip to right side of arena)
		# Assuming arena width is 10 tiles
		var mirrored_pos = Vector2i(9 - unit_data.position_x, unit_data.position_y)

		# Setup and add to battle
		battle_handler._setup_battle_unit(mirrored_pos, battle_unit)

		# Apply trait bonuses based on opponent's trait composition
		_apply_trait_bonuses_to_unit(battle_unit, opponent_trait_counts)

		# TODO: Apply items if needed
		# For now, items are not synced in this simplified version


func _get_unit_stats_by_name(unit_name: String) -> UnitStats:
	# Try to load unit resource by name
	var path = "res://data/units/%s.tres" % unit_name

	if ResourceLoader.exists(path):
		return load(path)
	else:
		printerr("Unit resource not found: %s" % path)
		return null


func _apply_trait_bonuses_to_unit(battle_unit: BattleUnit, trait_counts: Dictionary) -> void:
	# Apply trait bonuses to a unit based on trait counts
	for unit_trait: Trait in battle_unit.stats.traits:
		if trait_counts.has(unit_trait):
			var count = trait_counts[unit_trait]
			var trait_bonus = unit_trait.get_active_bonus(count)
			if trait_bonus:
				print("    Applying trait bonus: %s (count: %d) to %s" % [unit_trait.name, count, battle_unit.stats.name])
				trait_bonus.apply_bonus(battle_unit)


func _on_player_won():
	print("Player won the battle!")
	print("  Is player1: %s" % MultiplayerManager.is_player1)
	print("  Match ID: %d" % MultiplayerManager.current_match_id)
	# Only player1 submits the result to avoid race conditions
	if MultiplayerManager.is_player1:
		print("  Submitting: I won")
		MultiplayerManager.submit_battle_result(true)
	else:
		print("  (Waiting for player1 to submit result)")


func _on_enemy_won():
	print("Enemy won the battle!")
	print("  Is player1: %s" % MultiplayerManager.is_player1)
	print("  Match ID: %d" % MultiplayerManager.current_match_id)
	# Only player1 submits the result to avoid race conditions
	if MultiplayerManager.is_player1:
		print("  Submitting: I lost (opponent won)")
		MultiplayerManager.submit_battle_result(false)
	else:
		print("  (Waiting for player1 to submit result)")


func _on_match_completed(winner: String):
	print("Match completed! Winner: %s" % winner)

	var my_identity_str = MultiplayerManager.my_identity.hex_encode()

	if winner == my_identity_str:
		print("🎉 You won!")
	else:
		print("😢 You lost!")

	# TODO: Show match result UI
	# TODO: Return to matchmaking menu
