extends Control

# UI Elements
var find_match_button: Button
var cancel_button: Button
var ready_button: Button
var status_label: Label
var panel: PanelContainer


func _ready():
	# Create panel container
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-100, -50)
	panel.size = Vector2(200, 100)
	add_child(panel)

	# Create VBox for layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Status label
	status_label = Label.new()
	status_label.text = "Multiplayer Menu"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)

	# Find Match button
	find_match_button = Button.new()
	find_match_button.text = "Find Match"
	find_match_button.pressed.connect(_on_find_match_pressed)
	vbox.add_child(find_match_button)

	# Cancel button (hidden initially)
	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(_on_cancel_pressed)
	cancel_button.visible = false
	vbox.add_child(cancel_button)

	# Ready button (hidden initially)
	ready_button = Button.new()
	ready_button.text = "Ready!"
	ready_button.pressed.connect(_on_ready_pressed)
	ready_button.visible = false
	vbox.add_child(ready_button)

	# Connect to MultiplayerManager signals
	MultiplayerManager.match_found.connect(_on_match_found)
	MultiplayerManager.both_players_ready.connect(_on_both_players_ready)
	MultiplayerManager.match_completed.connect(_on_match_completed)
	MultiplayerManager.connection_established.connect(_on_connection_established)


func _on_connection_established():
	status_label.text = "Connected to Server"


func _on_find_match_pressed():
	MultiplayerManager.join_queue()
	find_match_button.visible = false
	cancel_button.visible = true
	status_label.text = "Searching for opponent..."


func _on_cancel_pressed():
	MultiplayerManager.leave_queue()
	cancel_button.visible = false
	find_match_button.visible = true
	status_label.text = "Multiplayer Menu"


func _on_ready_pressed():
	MultiplayerManager.mark_ready(true)
	ready_button.disabled = true
	status_label.text = "Waiting for opponent..."


func _on_match_found(match_id: int, opponent: String, seed: int, is_p1: bool):
	cancel_button.visible = false
	ready_button.visible = true
	ready_button.disabled = false
	status_label.text = "Match Found!\nOpponent: ...%s" % opponent.substr(opponent.length() - 8)


func _on_both_players_ready():
	panel.visible = false
	status_label.text = "Battle Starting!"


func _on_match_completed(winner: String):
	panel.visible = true
	ready_button.visible = false
	find_match_button.visible = true

	var my_identity_str = MultiplayerManager.my_identity.hex_encode()

	if winner == my_identity_str:
		status_label.text = "🎉 Victory!"
	else:
		status_label.text = "😢 Defeat!"

	# Auto-return to menu after delay
	await get_tree().create_timer(3.0).timeout
	status_label.text = "Multiplayer Menu"
