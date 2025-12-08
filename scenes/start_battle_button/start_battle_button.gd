class_name StartBattleButton
extends Button

@export var game_state: GameState
@export var player_stats: PlayerStats
@export var arena_grid: UnitGrid

@onready var icon_texture: TextureRect = $Icon

var waiting_label: Label


func _ready() -> void:
	pressed.connect(_on_pressed)
	player_stats.changed.connect(_update)
	arena_grid.unit_grid_changed.connect(_update)
	game_state.changed.connect(_update)

	# Connect to multiplayer signals
	MultiplayerManager.match_found.connect(_on_match_found)

	# Create waiting label (hidden by default)
	waiting_label = Label.new()
	waiting_label.text = "Waiting for opponent..."
	waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	waiting_label.anchor_left = 0
	waiting_label.anchor_right = 1
	waiting_label.anchor_top = 0
	waiting_label.anchor_bottom = 1
	waiting_label.offset_top = 30  
	waiting_label.visible = false
	add_child(waiting_label)

	_update()


func _update() -> void:
	var units_used := arena_grid.get_all_units().size()

	# Update button state based on multiplayer state
	if MultiplayerManager.state == MultiplayerManager.MatchmakingState.IN_QUEUE:
		disabled = true
		waiting_label.visible = true
		icon_texture.visible = false
	else:
		disabled = game_state.is_battling() or units_used > player_stats.level or units_used == 0
		waiting_label.visible = false
		icon_texture.visible = true
		icon_texture.modulate.a = 0.5 if disabled else 1.0


func _on_pressed() -> void:
	if game_state.is_battling():
		return

	# Single press: Join queue (which will auto-ready when matched)
	print("🎮 Joining matchmaking queue...")
	MultiplayerManager.join_queue()
	_update()


func _on_match_found(match_id: int, opponent: String, seed: int, is_p1: bool):
	print("🎮 Match found! Waiting for board sync...")
	_update()
