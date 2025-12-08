extends Node

# Signals for game state changes
signal match_found(match_id: int, opponent_identity: String, battle_seed: int, is_player1: bool)
signal opponent_board_updated
signal both_players_ready
signal match_completed(winner_identity: String)
signal connection_established
signal connection_failed(error: String)

# Match states
enum MatchmakingState {
	IDLE,
	IN_QUEUE,
	IN_MATCH,
	BATTLE_READY,
}

# Current state
var state: MatchmakingState = MatchmakingState.IDLE
var current_match_id: int = -1
var opponent_identity: PackedByteArray
var my_identity: PackedByteArray
var battle_seed: int = 0
var is_player1: bool = false
var is_connected: bool = false

# SpacetimeDB connection settings
const SERVER_URL = "http://127.0.0.1:3000"
const MODULE_NAME = "autobattler"


func _ready():
	print("=== MultiplayerManager initializing ===")

	# Connect SpacetimeDB signals
	SpacetimeDB.connected.connect(_on_spacetimedb_connected)
	SpacetimeDB.disconnected.connect(_on_spacetimedb_disconnected)
	SpacetimeDB.connection_error.connect(_on_spacetimedb_connection_error)
	SpacetimeDB.identity_received.connect(_on_spacetimedb_identity_received)
	SpacetimeDB.database_initialized.connect(_on_spacetimedb_database_initialized)
	SpacetimeDB.transaction_update_received.connect(_on_transaction_update)
	# Note: row_inserted/updated/deleted are now handled via LocalDatabase.subscribe_to_inserts/updates

	# Auto-connect on startup
	connect_to_server()

	print("=== Connecting to SpacetimeDB: %s / %s ===" % [SERVER_URL, MODULE_NAME])


func connect_to_server():
	print("Connecting to SpacetimeDB...")
	var options = SpacetimeDBConnectionOptions.new()
	options.one_time_token = true  # Anonymous sessions for now
	options.compression = SpacetimeDBConnection.CompressionPreference.NONE
	options.threading = true

	SpacetimeDB.connect_db(SERVER_URL, MODULE_NAME, options)


func _on_spacetimedb_connected():
	print("Connected to SpacetimeDB!")
	is_connected = true

	# Subscribe to tables immediately after connection
	print("Subscribing to tables...")
	var queries = [
		"SELECT * FROM player",
		"SELECT * FROM matchmaking_queue",
		"SELECT * FROM match_entry",
		"SELECT * FROM board_unit",
		"SELECT * FROM unit_item"
	]

	var req_id = SpacetimeDB.subscribe(queries)
	if req_id < 0:
		printerr("Failed to subscribe to tables!")
	else:
		print("✅ Subscribed to tables (Request ID: %d)" % req_id)


func _on_spacetimedb_identity_received(identity_token):
	my_identity = identity_token.identity
	print("My Identity: 0x%s" % my_identity.hex_encode())


func _on_spacetimedb_database_initialized():
	print("📊 Database initialized and synced!")

	# Subscribe to table insert/update events (required for row signals to work!)
	var db = SpacetimeDB.get_local_database()
	if db:
		print("🔔 Subscribing to table events...")
		db.subscribe_to_inserts(&"player", func(row): _on_row_inserted("player", row))
		db.subscribe_to_inserts(&"matchmaking_queue", func(row): _on_row_inserted("matchmaking_queue", row))
		db.subscribe_to_inserts(&"match_entry", func(row): _on_row_inserted("match_entry", row))
		db.subscribe_to_inserts(&"board_unit", func(row): _on_row_inserted("board_unit", row))
		db.subscribe_to_inserts(&"unit_item", func(row): _on_row_inserted("unit_item", row))

		db.subscribe_to_updates(&"match_entry", func(prev, row): _on_row_updated("match_entry", prev, row))
		print("✅ Subscribed to table events!")
	else:
		printerr("❌ Failed to get local database for event subscriptions!")

	connection_established.emit()

	# Check for existing matches after subscription
	await get_tree().create_timer(0.5).timeout
	_check_existing_matches()


func _check_existing_matches():
	print("🔍 Checking for existing matches...")
	var db = SpacetimeDB.get_local_database()
	if not db:
		print("  No local DB yet")
		return

	var matches = db.get_all_rows("match_entry")
	if not matches or matches.size() == 0:
		print("  No existing matches found")
		return

	print("  Found %d match(es) in database" % matches.size())
	for match_row in matches:
		# Only process matches that involve us
		if match_row.player1_identity == my_identity or match_row.player2_identity == my_identity:
			print("  Found our existing match (ID: %d)" % match_row.match_id)
			_handle_match_created(match_row)
		else:
			print("  Ignoring match %d (not ours)" % match_row.match_id)


func _on_spacetimedb_disconnected():
	print("Disconnected from SpacetimeDB")
	is_connected = false


func _on_spacetimedb_connection_error(code, reason):
	printerr("Connection error (Code %d): %s" % [code, reason])
	connection_failed.emit("%s (Code: %d)" % [reason, code])


func _on_transaction_update(update):
	if update.status:
		match update.status.status_type:
			0:  # Committed
				if update.reducer_call:
					print("✅ Reducer '%s' succeeded (ID: %d)" % [update.reducer_call.reducer_name, update.reducer_call.request_id])
			1:  # Failed
				if update.reducer_call:
					printerr("❌ Reducer '%s' FAILED: %s" % [update.reducer_call.reducer_name, update.status.failure_message])
			2:  # OutOfEnergy
				printerr("⚡ Reducer out of energy!")


# ===== Matchmaking Functions =====

func join_queue():
	if not is_connected:
		printerr("❌ Not connected to SpacetimeDB!")
		return

	print("📞 Calling join_matchmaking reducer...")
	print("  Current state before call: %d" % state)
	var req_id = SpacetimeDB.call_reducer("join_matchmaking", [], [])

	if req_id < 0:
		printerr("❌ Failed to join queue! Request ID: %d" % req_id)
	else:
		print("  Setting state to IN_QUEUE...")
		state = MatchmakingState.IN_QUEUE
		print("  New state: %d (should be 1)" % state)
		print("✅ join_matchmaking called successfully (Request ID: %d)" % req_id)
		print("⏳ Waiting for server response...")


func leave_queue():
	if not is_connected:
		return

	print("Leaving matchmaking queue...")
	var req_id = SpacetimeDB.call_reducer("leave_matchmaking", [], [])

	if req_id >= 0:
		state = MatchmakingState.IDLE
		print("Left matchmaking queue")


# ===== Board State Functions =====

func clear_my_board():
	if current_match_id < 0:
		return

	SpacetimeDB.call_reducer("clear_board_state", [current_match_id], [&'u64'])


func update_unit(unit_name: String, tier: int, pos_x: int, pos_y: int, on_bench: bool):
	if current_match_id < 0 or state != MatchmakingState.IN_MATCH:
		return

	SpacetimeDB.call_reducer(
		"update_board_state",
		[current_match_id, unit_name, tier, pos_x, pos_y, on_bench],
		[&'u64', &'string', &'u8', &'i32', &'i32', &'bool']
	)


func add_item_to_unit(board_unit_id: int, item_id: String, equip_index: int):
	if current_match_id < 0:
		return

	SpacetimeDB.call_reducer(
		"add_unit_item",
		[board_unit_id, item_id, equip_index],
		[&'u64', &'string', &'u8']
	)


func mark_ready(ready: bool = true):
	if current_match_id < 0:
		return

	print("Marking ready: %s" % ready)
	SpacetimeDB.call_reducer(
		"mark_ready",
		[current_match_id, ready],
		[&'u64', &'bool']
	)


# ===== Battle Result Functions =====

func submit_battle_result(winner_identity: PackedByteArray):
	if current_match_id < 0:
		return

	print("Submitting battle result. Winner: 0x%s" % winner_identity.hex_encode())
	SpacetimeDB.call_reducer(
		"submit_battle_result",
		[current_match_id, winner_identity],
		[&'u64', &'identity']
	)


func forfeit_match():
	if current_match_id < 0:
		return

	print("Forfeiting match")
	SpacetimeDB.call_reducer("forfeit_match", [current_match_id], [&'u64'])


# ===== Data Query Functions =====

func get_opponent_units() -> Array:
	var db = SpacetimeDB.get_local_database()
	if not db:
		return []

	var all_units = db.get_all_rows("board_unit")
	if not all_units:
		return []

	# Filter units belonging to opponent in current match
	var opponent_units = []
	for unit in all_units:
		if unit.match_id == current_match_id and unit.player_identity == opponent_identity:
			opponent_units.append(unit)

	return opponent_units


func get_my_board_units() -> Array:
	var db = SpacetimeDB.get_local_database()
	if not db:
		return []

	var all_units = db.get_all_rows("board_unit")
	if not all_units:
		return []

	var my_units = []
	for unit in all_units:
		if unit.match_id == current_match_id and unit.player_identity == my_identity:
			my_units.append(unit)

	return my_units


# ===== Row Event Handlers =====

func _on_row_inserted(table_name: String, row: Resource):
	print("📊 Row inserted in table: %s" % table_name)
	match table_name:
		"match_entry":
			print("  🎮 New match_entry detected!")
			_handle_match_created(row)
		"board_unit":
			print("  📦 New board_unit detected!")
			_handle_board_unit_updated(row)
		"player":
			print("  👤 Player entry updated")
		"matchmaking_queue":
			print("  🎯 Queue entry updated")
		_:
			print("  (No handler for table: %s)" % table_name)


func _on_row_updated(table_name: String, previous: Resource, row: Resource):
	match table_name:
		"match_entry":
			_handle_match_updated(row)
		"board_unit":
			_handle_board_unit_updated(row)


func _on_row_deleted(table_name: String, row: Resource):
	pass  # Handle if needed


func _handle_match_created(match_row):
	print("🎮 _handle_match_created called!")
	print("  Match ID: %s" % str(match_row.match_id))
	print("  Player 1: 0x%s" % match_row.player1_identity.hex_encode())
	print("  Player 2: 0x%s" % match_row.player2_identity.hex_encode())
	print("  My Identity: 0x%s" % my_identity.hex_encode())

	# Check if this match involves us
	if match_row.player1_identity != my_identity and match_row.player2_identity != my_identity:
		print("  ❌ Not our match, ignoring")
		return  # Not our match

	print("  ✅ This is OUR match!")
	print("  Match ID: %d" % match_row.match_id)

	current_match_id = match_row.match_id
	is_player1 = (match_row.player1_identity == my_identity)
	opponent_identity = match_row.player2_identity if is_player1 else match_row.player1_identity
	battle_seed = match_row.battle_seed

	print("  Setting state to IN_MATCH...")
	state = MatchmakingState.IN_MATCH
	print("  New state: %d" % state)

	print("  Emitting match_found signal...")
	match_found.emit(
		current_match_id,
		opponent_identity.hex_encode(),
		battle_seed,
		is_player1
	)
	print("  ✅ Match found signal emitted!")


func _handle_match_updated(match_row):
	if match_row.match_id != current_match_id:
		return

	# Check for state changes
	if match_row.state == 1:  # BattleReady (enum index)
		print("Both players ready! Battle starting...")
		state = MatchmakingState.BATTLE_READY
		both_players_ready.emit()

	elif match_row.state == 2:  # Completed (enum index)
		print("Match completed!")
		if match_row.winner_identity:
			match_completed.emit(match_row.winner_identity.hex_encode())

		# Reset state
		state = MatchmakingState.IDLE
		current_match_id = -1
		opponent_identity = PackedByteArray()


func _handle_board_unit_updated(unit_row):
	if unit_row.match_id != current_match_id:
		return

	# Check if it's opponent's unit
	if unit_row.player_identity == opponent_identity:
		opponent_board_updated.emit()


# ===== Cleanup =====

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		if is_connected:
			SpacetimeDB.disconnect_db()
