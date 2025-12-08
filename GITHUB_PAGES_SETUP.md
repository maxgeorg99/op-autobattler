# GitHub Pages OAuth Callback Setup

This guide explains how to deploy the OAuth callback page to GitHub Pages and configure SpacetimeDB.

## Step 1: Deploy Callback Page to GitHub Pages

### Option A: Add to Existing GitHub Pages Site

If you already have a GitHub Pages site (like `maxgeorg99.github.io`):

1. Copy the `oauth_callback.html` file to your GitHub Pages repository
2. Rename it to `callback.html` (or `callback/index.html`)
3. Commit and push:
```bash
cd /path/to/your/github/pages/repo
cp /home/max/godot_autobattler_course/oauth_callback.html callback.html
git add callback.html
git commit -m "Add OAuth callback page for autobattler game"
git push
```

4. Verify it's accessible at: `https://maxgeorg99.github.io/callback`

### Option B: Create New GitHub Pages Repository

If you don't have a GitHub Pages site yet:

1. Create a new repository named `yourusername.github.io`
2. Clone it locally
3. Add the callback page
4. Push and enable GitHub Pages in settings

## Step 2: Configure SpacetimeDB Auth Project

1. Go to your SpacetimeDB auth project:
   https://spacetimedb.com/spacetimeauth/project_031CSnBYozXUwZy49r0H91

2. Find the **Redirect URIs** section

3. Add your GitHub Pages callback URL:
   ```
   https://maxgeorg99.github.io/callback
   ```

4. **Keep the existing URLs** (don't remove them, just add this one)

5. Save the configuration

## Step 3: Update Maincloud Module Name

1. Deploy your autobattler module to SpacetimeDB maincloud:
```bash
cd /home/max/godot_autobattler_course/server
spacetime publish autobattler-main --server maincloud
```

2. Update the module name in `autoload/multiplayer_manager.gd`:
```gdscript
const MAINCLOUD_MODULE_NAME = "autobattler-main"  # Use your actual module name
```

## Step 4: Test the Flow

### Test Local Mode:
1. Run the game
2. Click "🏠 Local Testing (Anonymous)"
3. Should connect to `http://127.0.0.1:3000`
4. No authentication required

### Test Production Mode:
1. Run the game
2. Click "🌐 Maincloud (Authenticated)"
3. Browser opens to SpacetimeDB auth
4. Log in with your SpacetimeDB account
5. Browser redirects to `https://maxgeorg99.github.io/callback?code=...`
6. Callback page displays success message
7. Return to game - should auto-connect to maincloud

## How It Works

### Production Mode (Maincloud)
```
User clicks "Maincloud" button
  ↓
Set connection: maincloud.spacetimedb.com
  ↓
Generate PKCE codes
  ↓
Open browser: auth.spacetimedb.com/oidc/authorize?...
  ↓
User logs in
  ↓
Redirect: maxgeorg99.github.io/callback?code=XXX
  ↓
User manually copies code from browser
  ↓
Paste code in game (or implement auto-polling)
  ↓
Exchange code for token
  ↓
Connect to maincloud with token
```

### Local Mode
```
User clicks "Local Testing" button
  ↓
Set connection: 127.0.0.1:3000
  ↓
Connect anonymously
  ↓
Done!
```

## Current Limitation: Manual Code Entry

Currently, the production flow requires the user to manually copy the authorization code from the GitHub Pages callback and paste it into the game.

### Future Enhancement: Auto-Polling

To make it fully automatic, you can implement one of these approaches:

#### Option 1: Use Custom URL Scheme
Register a custom URL scheme (`godot-autobattler://`) that the callback page can use to send the code back to the game.

#### Option 2: WebSocket Bridge
Set up a simple WebSocket server that:
1. Callback page sends code via WebSocket
2. Game client polls/connects to WebSocket
3. Receives code automatically

#### Option 3: Clipboard Auto-Copy
Modify the callback page to automatically copy the code to clipboard:
```javascript
// In oauth_callback.html
navigator.clipboard.writeText(code);
```

Then poll clipboard in Godot (if platform supports it).

## File Structure

```
godot_autobattler_course/
├── autoload/
│   ├── spacetime_auth.gd          # OAuth manager with dual-mode support
│   └── multiplayer_manager.gd      # DB connection with local/maincloud switching
├── scenes/
│   └── auth/
│       ├── auth_screen.gd         # UI with Production/Local buttons
│       └── auth_screen.tscn
├── oauth_callback.html            # GitHub Pages callback page
└── GITHUB_PAGES_SETUP.md          # This file
```

## Configuration Summary

### SpacetimeDB Auth Project
- **Client ID**: `client_031CSnBZhPFgz5oj5Alo0a`
- **Allowed Redirect URIs**:
  - `https://maxgeorg99.github.io/callback` ✅ (Production)
  - `http://127.0.0.1:31419` ⚠️ (Local dev - may not be whitelisted)

### MultiplayerManager
- **Local**: `http://127.0.0.1:3000` / `autobattler`
- **Maincloud**: `https://maincloud.spacetimedb.com` / `autobattler-main`

### Auth Modes
- **LOCAL**: Uses `127.0.0.1:31419` callback (localhost)
- **PRODUCTION**: Uses GitHub Pages callback

## Troubleshooting

### Issue: "NotFound" error when clicking Production button
- **Cause**: Redirect URI not whitelisted
- **Fix**: Add `https://maxgeorg99.github.io/callback` to SpacetimeDB auth project

### Issue: Callback page shows but code doesn't return to game
- **Cause**: Manual code entry not implemented yet
- **Fix**: Check browser console for code, or implement auto-polling

### Issue: Local mode works but production doesn't
- **Cause**: Maincloud module not deployed or wrong name
- **Fix**: Deploy module to maincloud and verify name in MultiplayerManager

## Next Steps

1. ✅ Deploy `oauth_callback.html` to GitHub Pages
2. ✅ Add redirect URI to SpacetimeDB auth project
3. ✅ Deploy server module to maincloud
4. ✅ Update `MAINCLOUD_MODULE_NAME` in code
5. ⚠️ (Optional) Implement automatic code return mechanism
6. ✅ Test both local and production modes
7. 🚀 Ship your game!
