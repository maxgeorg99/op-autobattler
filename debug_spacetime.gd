extends Node

# Quick debug script to test SpacetimeDB connection
# Attach this to a Node in your scene or run it from the debugger

func _ready():
	await get_tree().create_timer(2.0).timeout  # Wait for autoloads

	print_debug_info()


func print_debug_info():
	print("\n=== SpacetimeDB Debug Info ===")
	print("Is connected: ", MultiplayerManager.is_connected)
	print("My identity: ", MultiplayerManager.my_identity.hex_encode() if MultiplayerManager.my_identity.size() > 0 else "Not set")
	print("Current state: %d" % MultiplayerManager.state)
	print("Current match ID: ", MultiplayerManager.current_match_id)

	# Try to get local database
	var db = SpacetimeDB.get_local_database()
	if db:
		print("Local DB exists: YES")
		var tables = ["player", "matchmaking_queue", "match_entry", "board_unit", "unit_item"]
		for table in tables:
			var rows = db.get_all_rows(table)
			if rows:
				print("  Table '%s': %d rows" % [table, rows.size()])
				if table == "match_entry" and rows.size() > 0:
					for match_row in rows:
						print("    Match %s: P1=0x%s, P2=0x%s, State=%d" % [
							match_row.match_id,
							match_row.player1_identity.hex_encode().substr(0, 8),
							match_row.player2_identity.hex_encode().substr(0, 8),
							match_row.state
						])
			else:
				print("  Table '%s': No rows or doesn't exist" % table)
	else:
		print("Local DB exists: NO")

	print("=== End Debug Info ===\n")


# Call this from console to re-check state
func check():
	print_debug_info()
