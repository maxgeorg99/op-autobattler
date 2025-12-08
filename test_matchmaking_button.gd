extends Button

# Temporary test button for matchmaking
# Add this to a Button node in your scene to test

func _ready():
	text = "TEST: Join Queue"
	pressed.connect(_on_pressed)


func _on_pressed():
	print("\n=== TEST BUTTON CLICKED ===")
	print("Current state: %d (%s)" % [MultiplayerManager.state, _get_state_name(MultiplayerManager.state)])
	print("Is connected: ", MultiplayerManager.is_connected)
	print("Match ID: ", MultiplayerManager.current_match_id)

	if MultiplayerManager.state == MultiplayerManager.MatchmakingState.IDLE:
		print("→ Action: Joining queue...")
		MultiplayerManager.join_queue()
	elif MultiplayerManager.state == MultiplayerManager.MatchmakingState.IN_QUEUE:
		print("→ Action: Already in queue, leaving...")
		MultiplayerManager.leave_queue()
	elif MultiplayerManager.state == MultiplayerManager.MatchmakingState.IN_MATCH:
		print("→ Action: In match! Marking ready...")
		print("  Match ID: %d" % MultiplayerManager.current_match_id)
		MultiplayerManager.mark_ready(true)
	else:
		print("→ Unknown state: %d" % MultiplayerManager.state)

	# Wait a bit and print state again
	await get_tree().create_timer(0.5).timeout
	print("State after action: %d (%s)" % [MultiplayerManager.state, _get_state_name(MultiplayerManager.state)])
	print("======================\n")


func _get_state_name(s: int) -> String:
	match s:
		0: return "IDLE"
		1: return "IN_QUEUE"
		2: return "IN_MATCH"
		3: return "BATTLE_READY"
		_: return "UNKNOWN"
