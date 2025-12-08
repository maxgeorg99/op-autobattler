# SpacetimeDB Authentication Setup

This game uses SpacetimeDB's OAuth2/OIDC authentication system for multiplayer functionality.

## Architecture

The authentication system consists of:

1. **SpacetimeAuth** (`autoload/spacetime_auth.gd`) - Singleton that handles OAuth2/OIDC flow
2. **AuthScreen** (`scenes/auth/auth_screen.tscn`) - UI for login/logout
3. **Main** (`scenes/main/main.tscn`) - Entry point that shows auth before game
4. **MultiplayerManager** - Updated to use auth tokens when available

## How It Works

### OAuth2 Flow with PKCE

1. User clicks "Sign in with SpacetimeDB"
2. System generates PKCE code verifier and challenge
3. Local HTTP server starts on `127.0.0.1:31419` to receive callback
4. System browser opens to SpacetimeDB auth page
5. User logs in with their SpacetimeDB account
6. Browser redirects to `http://127.0.0.1:31419?code=...`
7. Local server receives authorization code
8. System exchanges code for access token using PKCE
9. Tokens are saved encrypted in `user://auth/tokens.dat`
10. Game connects to SpacetimeDB with access token

### Token Management

- **Access Token**: Short-lived (typically 1 hour), used for API calls
- **Refresh Token**: Long-lived, used to get new access tokens
- **ID Token**: Contains user profile information (username, email, etc.)
- **Auto-refresh**: Tokens are automatically refreshed when expired

## Configuration

### SpacetimeDB Auth Project

The game is configured to use:
- **Authority**: `https://auth.spacetimedb.com/oidc`
- **Client ID**: `client_031CSnBZhPFgz5oj5Alo0a`
- **Scopes**: `openid profile email`
- **Redirect URI**: `http://127.0.0.1:31419`

### Local vs Production

The system supports two modes:

1. **Local Development** (Default)
   - Click "Skip (Local/Anonymous)" on auth screen
   - Uses anonymous SpacetimeDB connection
   - No authentication required

2. **Authenticated Mode**
   - Click "Sign in with SpacetimeDB"
   - Uses OAuth2 flow
   - Required for production/cloud deployments

## Files

```
autoload/
  └── spacetime_auth.gd          # OAuth2/OIDC singleton
  └── multiplayer_manager.gd      # Updated to use auth tokens

scenes/
  ├── main/
  │   ├── main.tscn               # Entry point with auth flow
  │   └── main.gd
  └── auth/
      ├── auth_screen.tscn        # Login/logout UI
      └── auth_screen.gd
```

## Testing

### Local Testing (No Auth)

1. Run the game
2. Click "Skip (Local/Anonymous)"
3. Game starts with anonymous connection to local SpacetimeDB

### Testing OAuth Flow

1. Run the game
2. Click "Sign in with SpacetimeDB"
3. Browser opens to auth page
4. Log in with your SpacetimeDB account
5. Browser shows success message
6. Game automatically connects with your authenticated identity

### Debugging

Enable detailed logging in `spacetime_auth.gd` by uncommenting debug prints.

Common issues:
- **Port 31419 already in use**: Another instance running or port blocked
- **Browser doesn't redirect**: Check firewall/antivirus settings
- **Token expired**: System should auto-refresh, but can logout and login again

## Security Notes

- **PKCE**: Uses PKCE (Proof Key for Code Exchange) for secure public client auth
- **Local Storage**: Tokens stored encrypted in `user://` directory
- **No Client Secret**: Public clients (desktop/mobile) don't use client secrets
- **HTTPS**: Production auth server uses HTTPS
- **Local Redirect**: Callback uses localhost (127.0.0.1) for security

## Production Deployment

For production deployment:

1. Register your game with SpacetimeDB auth project
2. Add your production redirect URIs
3. Update `REDIRECT_URI` in `spacetime_auth.gd` if needed
4. Configure server to require authentication
5. Remove "Skip" button for production builds

## API Reference

### SpacetimeAuth

```gdscript
# Check if authenticated
if SpacetimeAuth.is_authenticated():
    print("User is logged in")

# Get access token
var token = SpacetimeAuth.get_access_token()

# Get user profile
var profile = SpacetimeAuth.get_user_profile()
var username = profile.get("preferred_username", "Unknown")

# Start authentication
SpacetimeAuth.authenticate()  # Returns via signal

# Refresh token
var refreshed = await SpacetimeAuth.refresh_access_token()

# Logout
SpacetimeAuth.logout()
```

### Signals

```gdscript
SpacetimeAuth.authentication_started.connect(func():
    print("Auth started"))

SpacetimeAuth.authentication_completed.connect(func(success):
    print("Auth completed: ", success))

SpacetimeAuth.authentication_failed.connect(func(error):
    print("Auth failed: ", error))

SpacetimeAuth.token_refreshed.connect(func():
    print("Token refreshed"))
```

## Resources

- [SpacetimeDB Authentication Docs](https://spacetimedb.com/docs/auth)
- [OAuth 2.0 with PKCE](https://oauth.net/2/pkce/)
- [OpenID Connect](https://openid.net/connect/)
