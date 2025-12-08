# SpacetimeDB Setup Verification Checklist

Follow these steps to verify your SpacetimeDB setup is working correctly.

## Step 1: Verify SpacetimeDB Server is Running

```bash
# Check if SpacetimeDB is running
spacetime server status

# If not running, start it:
spacetime server start

# Check logs
spacetime server logs
```

Expected output: Server should be running on `http://127.0.0.1:3000`

---

## Step 2: Publish the Module

```bash
cd /home/max/godot_autobattler_course/server

# Publish the module
spacetime publish autobattler

# Verify it's published
spacetime list
```

Expected output: You should see `autobattler` in the list of modules.

**Common issues:**
- If publish fails, try: `spacetime publish autobattler --clear-database`
- Make sure `Cargo.toml` and `src/lib.rs` are in the `server/` directory

---

## Step 3: Check Module in SpacetimeDB

```bash
# Get module info
spacetime describe autobattler

# Check tables exist
spacetime sql autobattler "SELECT * FROM player"
spacetime sql autobattler "SELECT * FROM matchmaking_queue"
spacetime sql autobattler "SELECT * FROM match_entry"
```

Expected output: Should show table structures, may be empty but shouldn't error.

---

## Step 4: Test Reducers from CLI

```bash
# Test join_matchmaking reducer
spacetime call autobattler join_matchmaking

# Check if player was added
spacetime sql autobattler "SELECT * FROM player"
spacetime sql autobattler "SELECT * FROM matchmaking_queue"
```

Expected output: Should see a player and queue entry created.

---

## Step 5: Generate GDScript Bindings in Godot

1. Open Godot project
2. Look for **SpacetimeDB dock** at the bottom (next to Output, Debugger tabs)
   - If you don't see it, check: `Project → Project Settings → Plugins` - ensure SpacetimeDB is enabled
3. In SpacetimeDB dock:
   - Server URL: `http://127.0.0.1:3000`
   - Click `+` to add module
   - Module name: `autobattler` (exact match!)
   - Click "Generate schema"

Expected result: Files generated in `spacetime_data/schema/` folder

**Files that should be generated:**
- `spacetime_data/schema/module_autobattler_reducers.gd`
- `spacetime_data/schema/tables/autobattler_player.gd`
- `spacetime_data/schema/tables/autobattler_match_entry.gd`
- etc.

---

## Step 6: Add Debug Node to Test Connection

1. Open `scenes/arena/arena.tscn`
2. Add a new `Node` as child of Arena
3. Attach script: `debug_spacetime.gd`
4. Run the game
5. Check Output/Console

**Expected console output:**
```
=== MultiplayerManager initializing ===
=== Connecting to SpacetimeDB: http://127.0.0.1:3000 / autobattler ===
Connecting to SpacetimeDB...
Connected to SpacetimeDB!
My Identity: 0x[some hex string]
Database initialized. Subscribing to tables...
Subscribed to tables (Request ID: [number])

=== SpacetimeDB Debug Info ===
Is connected: true
My identity: 0x[hex string]
Current state: 0
Current match ID: -1
Local DB exists: YES
  Table 'player': 0 rows
  Table 'matchmaking_queue': 0 rows
  Table 'match_entry': 0 rows
  Table 'board_unit': 0 rows
  Table 'unit_item': 0 rows
=== End Debug Info ===
```

---

## Step 7: Add Matchmaking UI to Arena

The game currently doesn't have the matchmaking UI integrated. You need to:

1. Open `scenes/arena/arena.tscn`
2. Add a `Control` node as child of Arena
3. Name it "MatchmakingUI"
4. Attach script: `res://scenes/matchmaking_ui/matchmaking_ui.gd`
5. (Optional) Position it in the top-right corner
6. Save the scene

Now when you run the game, you should see:
- "Find Match" button
- Status label showing connection status

---

## Step 8: Disable Regular "Start Battle" Button

The regular Start Battle button bypasses multiplayer. You should either:

**Option A: Hide it in multiplayer mode**
```gdscript
# In the start_battle_button script:
func _ready():
    # Hide button if in multiplayer mode
    visible = false  # Or add proper check
```

**Option B: Make it trigger matchmaking instead**
```gdscript
func _on_pressed():
    MultiplayerManager.join_queue()
```

---

## Troubleshooting

### "Not connected to SpacetimeDB"
- Check server is running: `spacetime server status`
- Check server logs: `spacetime server logs`
- Check console for connection errors

### "Failed to subscribe to tables"
- Module might not be published: `spacetime list`
- Table names might be wrong (check generated schema)
- Try republishing: `spacetime publish autobattler --clear-database`

### "No rows in tables"
- This is normal on first run
- Try calling a reducer from Godot: `MultiplayerManager.join_queue()`
- Check SpacetimeDB logs to see if reducer was called

### "Battle keeps cancelling"
- This is expected! You're not in a match yet
- You need TWO clients to test multiplayer
- Both must click "Find Match"
- Both must click "Ready"
- Then battle will start with opponent units

---

## Testing Multiplayer (2 Clients)

1. Run game instance 1
2. Click "Find Match" - should show "Searching..."
3. Run game instance 2 (separate window)
4. Click "Find Match" in instance 2
5. Both should show "Match Found!"
6. Both: Arrange units on board
7. Both: Click "Ready"
8. Battle should start with opponent's units on the right side

---

## SpacetimeDB Logs

Check server logs for reducer calls:
```bash
spacetime server logs --follow
```

You should see lines like:
```
[INFO] Reducer call: join_matchmaking by 0x...
[INFO] Match created: 0x... vs 0x...
```

If you don't see reducer calls, the client isn't connecting properly.
