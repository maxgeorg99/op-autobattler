use spacetimedb::{reducer, Identity, ReducerContext, SpacetimeType, Table, Timestamp};

// ===== ENUMS =====

#[derive(SpacetimeType, Clone, Copy, Debug, PartialEq)]
pub enum PlayerState {
    InQueue,
    InMatch,
}

#[derive(SpacetimeType, Clone, Copy, Debug, PartialEq)]
pub enum MatchState {
    Preparation,
    BattleReady,
    Completed,
}

// ===== TABLES =====

#[spacetimedb::table(name = player, public)]
pub struct Player {
    #[primary_key]
    pub identity: Identity,
    pub state: PlayerState,
    pub current_match_id: Option<u64>,
}

#[spacetimedb::table(name = matchmaking_queue, public)]
pub struct MatchmakingQueue {
    #[primary_key]
    pub identity: Identity,
    pub queued_at: Timestamp,
}

#[spacetimedb::table(name = match_entry, public)]
pub struct Match {
    #[primary_key]
    pub match_id: u64,
    pub player1_identity: Identity,
    pub player2_identity: Identity,
    pub state: MatchState,
    pub battle_seed: u64,
    pub created_at: Timestamp,
    pub winner_identity: Option<Identity>,
}

#[spacetimedb::table(name = board_unit, public)]
pub struct BoardUnit {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    pub match_id: u64,
    pub player_identity: Identity,
    pub unit_name: String,
    pub tier: u8,
    pub position_x: i32,
    pub position_y: i32,
    pub on_bench: bool,
}

#[spacetimedb::table(name = unit_item, public)]
pub struct UnitItem {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    pub board_unit_id: u64,
    pub item_id: String,
    pub equip_index: u8,
}

// ===== REDUCERS =====

#[reducer]
pub fn join_matchmaking(ctx: &ReducerContext) -> Result<(), String> {
    let caller = ctx.sender;

    // Check if player already exists
    let existing_player = ctx.db.player().identity().find(&caller);

    if existing_player.is_none() {
        // Create new player
        ctx.db.player().insert(Player {
            identity: caller,
            state: PlayerState::InQueue,
            current_match_id: None,
        });
    } else {
        // Update existing player to InQueue state
        let player = existing_player.unwrap();
        if matches!(player.state, PlayerState::InMatch) {
            return Err("Player already in match".to_string());
        }
        ctx.db.player().identity().update(Player {
            identity: caller,
            state: PlayerState::InQueue,
            current_match_id: None,
        });
    }

    // Add to matchmaking queue if not already there
    if ctx.db.matchmaking_queue().identity().find(&caller).is_none() {
        ctx.db.matchmaking_queue().insert(MatchmakingQueue {
            identity: caller,
            queued_at: ctx.timestamp,
        });
    }

    // Try to create a match
    try_create_match(ctx)?;

    Ok(())
}

#[reducer]
pub fn leave_matchmaking(ctx: &ReducerContext) -> Result<(), String> {
    let caller = ctx.sender;

    // Remove from queue if present
    if ctx.db.matchmaking_queue().identity().find(&caller).is_some() {
        ctx.db.matchmaking_queue().identity().delete(&caller);
    }

    Ok(())
}

fn try_create_match(ctx: &ReducerContext) -> Result<(), String> {
    // Get all queued players
    let mut queue: Vec<_> = ctx.db.matchmaking_queue().iter().collect();

    if queue.len() < 2 {
        return Ok(()); // Not enough players
    }

    // Sort by queue time (FIFO)
    queue.sort_by_key(|q| q.queued_at);

    let p1 = queue[0].identity;
    let p2 = queue[1].identity;

    // Generate match ID and battle seed from timestamp
    let match_id = ctx.timestamp.to_micros_since_unix_epoch() as u64;
    let battle_seed = match_id.wrapping_mul(12345);

    // Create match
    ctx.db.match_entry().insert(Match {
        match_id,
        player1_identity: p1,
        player2_identity: p2,
        state: MatchState::Preparation,
        battle_seed,
        created_at: ctx.timestamp,
        winner_identity: None,
    });

    // Update both players
    for player_id in [p1, p2] {
        ctx.db.player().identity().update(Player {
            identity: player_id,
            state: PlayerState::InMatch,
            current_match_id: Some(match_id),
        });

        // Remove from queue
        ctx.db.matchmaking_queue().identity().delete(&player_id);
    }

    Ok(())
}

#[reducer]
pub fn update_board_state(
    ctx: &ReducerContext,
    match_id: u64,
    unit_name: String,
    tier: u8,
    position_x: i32,
    position_y: i32,
    on_bench: bool,
) -> Result<(), String> {
    let caller = ctx.sender;

    // Verify player is in this match
    let match_data = ctx
        .db
        .match_entry()
        .match_id()
        .find(&match_id)
        .ok_or("Match not found")?;

    if match_data.player1_identity != caller && match_data.player2_identity != caller {
        return Err("Not a participant in this match".to_string());
    }

    if !matches!(match_data.state, MatchState::Preparation) {
        return Err("Match not in preparation phase".to_string());
    }

    // Insert new unit
    ctx.db.board_unit().insert(BoardUnit {
        id: 0, // auto_inc
        match_id,
        player_identity: caller,
        unit_name,
        tier,
        position_x,
        position_y,
        on_bench,
    });

    Ok(())
}

#[reducer]
pub fn clear_board_state(ctx: &ReducerContext, match_id: u64) -> Result<(), String> {
    let caller = ctx.sender;

    // Verify player is in this match
    let match_data = ctx
        .db
        .match_entry()
        .match_id()
        .find(&match_id)
        .ok_or("Match not found")?;

    if match_data.player1_identity != caller && match_data.player2_identity != caller {
        return Err("Not a participant in this match".to_string());
    }

    // Delete all units for this player in this match
    let units_to_delete: Vec<_> = ctx
        .db
        .board_unit()
        .iter()
        .filter(|u| u.match_id == match_id && u.player_identity == caller)
        .collect();

    for unit in units_to_delete {
        // Delete associated items first
        let items_to_delete: Vec<_> = ctx
            .db
            .unit_item()
            .iter()
            .filter(|i| i.board_unit_id == unit.id)
            .collect();

        for item in items_to_delete {
            ctx.db.unit_item().id().delete(&item.id);
        }

        ctx.db.board_unit().id().delete(&unit.id);
    }

    Ok(())
}

#[reducer]
pub fn add_unit_item(
    ctx: &ReducerContext,
    board_unit_id: u64,
    item_id: String,
    equip_index: u8,
) -> Result<(), String> {
    let caller = ctx.sender;

    // Verify the unit belongs to the caller
    let unit = ctx
        .db
        .board_unit()
        .id()
        .find(&board_unit_id)
        .ok_or("Unit not found")?;

    if unit.player_identity != caller {
        return Err("Not your unit".to_string());
    }

    // Insert item
    ctx.db.unit_item().insert(UnitItem {
        id: 0, // auto_inc
        board_unit_id,
        item_id,
        equip_index,
    });

    Ok(())
}

#[reducer]
pub fn mark_ready(ctx: &ReducerContext, match_id: u64, is_ready: bool) -> Result<(), String> {
    let caller = ctx.sender;

    // Verify player is in this match
    let match_data = ctx
        .db
        .match_entry()
        .match_id()
        .find(&match_id)
        .ok_or("Match not found")?;

    if match_data.player1_identity != caller && match_data.player2_identity != caller {
        return Err("Not a participant in this match".to_string());
    }

    if !matches!(match_data.state, MatchState::Preparation) {
        return Err("Match not in preparation phase".to_string());
    }

    // For simplicity, transition to BattleReady when either player calls this
    // In a real implementation, you'd want a ReadyState table to track both players
    if is_ready {
        ctx.db.match_entry().match_id().update(Match {
            match_id: match_data.match_id,
            player1_identity: match_data.player1_identity,
            player2_identity: match_data.player2_identity,
            state: MatchState::BattleReady,
            battle_seed: match_data.battle_seed,
            created_at: match_data.created_at,
            winner_identity: match_data.winner_identity,
        });
    }

    Ok(())
}

#[reducer]
pub fn submit_battle_result(
    ctx: &ReducerContext,
    match_id: u64,
    caller_won: bool,
) -> Result<(), String> {
    let caller = ctx.sender;

    // Verify player is in this match
    let match_data = ctx
        .db
        .match_entry()
        .match_id()
        .find(&match_id)
        .ok_or("Match not found")?;

    if match_data.player1_identity != caller && match_data.player2_identity != caller {
        return Err("Not a participant in this match".to_string());
    }

    if !matches!(match_data.state, MatchState::BattleReady) {
        return Err("Battle not ready".to_string());
    }

    // Determine winner based on who called and whether they won
    let winner_identity = if caller_won {
        caller
    } else {
        // Caller lost, so the other player won
        if match_data.player1_identity == caller {
            match_data.player2_identity
        } else {
            match_data.player1_identity
        }
    };

    // Update match with winner
    ctx.db.match_entry().match_id().update(Match {
        match_id: match_data.match_id,
        player1_identity: match_data.player1_identity,
        player2_identity: match_data.player2_identity,
        state: MatchState::Completed,
        battle_seed: match_data.battle_seed,
        created_at: match_data.created_at,
        winner_identity: Some(winner_identity),
    });

    // Update both players back to queue state
    for player_id in [match_data.player1_identity, match_data.player2_identity] {
        ctx.db.player().identity().update(Player {
            identity: player_id,
            state: PlayerState::InQueue,
            current_match_id: None,
        });
    }

    // Clean up board units and their items for this match
    let units_to_delete: Vec<_> = ctx
        .db
        .board_unit()
        .iter()
        .filter(|u| u.match_id == match_id)
        .collect();

    for unit in units_to_delete {
        // Delete associated items first
        let items_to_delete: Vec<_> = ctx
            .db
            .unit_item()
            .iter()
            .filter(|i| i.board_unit_id == unit.id)
            .collect();

        for item in items_to_delete {
            ctx.db.unit_item().id().delete(&item.id);
        }

        ctx.db.board_unit().id().delete(&unit.id);
    }

    // Delete the match entry itself
    ctx.db.match_entry().match_id().delete(&match_id);

    Ok(())
}

#[reducer]
pub fn forfeit_match(ctx: &ReducerContext, match_id: u64) -> Result<(), String> {
    let caller = ctx.sender;

    // Verify player is in this match
    let match_data = ctx
        .db
        .match_entry()
        .match_id()
        .find(&match_id)
        .ok_or("Match not found")?;

    if match_data.player1_identity != caller && match_data.player2_identity != caller {
        return Err("Not a participant in this match".to_string());
    }

    // Set winner as the other player
    let winner = if match_data.player1_identity == caller {
        match_data.player2_identity
    } else {
        match_data.player1_identity
    };

    ctx.db.match_entry().match_id().update(Match {
        match_id: match_data.match_id,
        player1_identity: match_data.player1_identity,
        player2_identity: match_data.player2_identity,
        state: MatchState::Completed,
        battle_seed: match_data.battle_seed,
        created_at: match_data.created_at,
        winner_identity: Some(winner),
    });

    // Update both players back to queue state
    for player_id in [match_data.player1_identity, match_data.player2_identity] {
        ctx.db.player().identity().update(Player {
            identity: player_id,
            state: PlayerState::InQueue,
            current_match_id: None,
        });
    }

    // Clean up board units and their items for this match
    let units_to_delete: Vec<_> = ctx
        .db
        .board_unit()
        .iter()
        .filter(|u| u.match_id == match_id)
        .collect();

    for unit in units_to_delete {
        // Delete associated items first
        let items_to_delete: Vec<_> = ctx
            .db
            .unit_item()
            .iter()
            .filter(|i| i.board_unit_id == unit.id)
            .collect();

        for item in items_to_delete {
            ctx.db.unit_item().id().delete(&item.id);
        }

        ctx.db.board_unit().id().delete(&unit.id);
    }

    // Delete the match entry itself
    ctx.db.match_entry().match_id().delete(&match_id);

    Ok(())
}
