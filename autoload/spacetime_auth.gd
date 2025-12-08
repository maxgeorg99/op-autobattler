extends Node

## SpacetimeDB OAuth2/OIDC Authentication Manager
## Implements PKCE (Proof Key for Code Exchange) flow for public clients

# OAuth2/OIDC Configuration
const AUTH_SERVER = "https://auth.spacetimedb.com/oidc/authorize"
const TOKEN_ENDPOINT = "https://auth.spacetimedb.com/oidc/token"
const CLIENT_ID = "client_031CSnBZhPFgz5oj5Alo0a"  # From your SpacetimeDB auth project
const SCOPES = "openid profile email"

# Redirect URIs for different modes
const LOCAL_REDIRECT_PORT = 31419
const LOCAL_REDIRECT_HOST = "127.0.0.1"
const LOCAL_REDIRECT_URI = "http://127.0.0.1:31419"
const PRODUCTION_REDIRECT_URI = "https://maxgeorg99.github.io/op-autobattler/oauth_callback.html"  # Replace with your actual URL

# Authentication modes
enum AuthMode {
	LOCAL,      # Local development with localhost callback
	PRODUCTION  # Production with GitHub Pages callback
}

var current_auth_mode: AuthMode = AuthMode.LOCAL

# Token storage
const SAVE_DIR = "user://auth/"
const TOKEN_FILE = "user://auth/tokens.dat"
const ENCRYPTION_PASS = "spacetime_auth_v1"  # Change this for production

# State
var access_token: String = ""
var refresh_token: String = ""
var id_token: String = ""
var token_expiry: int = 0
var user_profile: Dictionary = {}

# PKCE variables
var code_verifier: String = ""
var code_challenge: String = ""

# HTTP server for OAuth callback
var tcp_server := TCPServer.new()
var is_listening := false

# Signals
signal authentication_started
signal authentication_completed(success: bool)
signal token_refreshed
signal authentication_failed(error: String)

func _ready() -> void:
	set_process(false)
	_load_tokens()


func _process(_delta: float) -> void:
	if not is_listening:
		return

	tcp_server.poll()

	if tcp_server.is_connection_available():
		var connection = tcp_server.take_connection()
		var request = connection.get_string(connection.get_available_bytes())

		if request:
			set_process(false)
			is_listening = false

			# Parse authorization code from callback
			var auth_code = _extract_auth_code(request)

			if auth_code:
				# Send success HTML response
				_send_http_response(connection, 200, _get_success_html())
				tcp_server.stop()

				# Exchange code for tokens
				await _exchange_code_for_tokens(auth_code)
			else:
				# Send error HTML response
				_send_http_response(connection, 400, _get_error_html("No authorization code received"))
				tcp_server.stop()
				authentication_failed.emit("No authorization code in callback")


## Start the OAuth2 authentication flow
## @param mode: AuthMode.LOCAL for local dev, AuthMode.PRODUCTION for GitHub Pages
func authenticate(mode: AuthMode = AuthMode.PRODUCTION) -> void:
	current_auth_mode = mode
	print("🔐 Starting SpacetimeDB authentication (mode: %s)..." % ("LOCAL" if mode == AuthMode.LOCAL else "PRODUCTION"))

	# Check if we have valid tokens
	if is_authenticated() and not is_token_expired():
		print("✅ Already authenticated with valid token")
		authentication_completed.emit(true)
		return

	# Try to refresh if we have a refresh token
	if refresh_token:
		print("🔄 Attempting to refresh token...")
		var refreshed = await refresh_access_token()
		if refreshed:
			print("✅ Token refreshed successfully")
			authentication_completed.emit(true)
			return

	# Start new authentication flow
	print("🌐 Starting new authentication flow...")
	authentication_started.emit()
	_start_auth_flow()


## Check if user is authenticated
func is_authenticated() -> bool:
	return access_token != ""


## Check if token is expired
func is_token_expired() -> bool:
	if token_expiry == 0:
		return true
	return Time.get_unix_time_from_system() >= token_expiry


## Get the current access token
func get_access_token() -> String:
	return access_token


## Get user profile information
func get_user_profile() -> Dictionary:
	return user_profile


## Refresh the access token using refresh token
func refresh_access_token() -> bool:
	if not refresh_token:
		return false

	print("Refreshing access token...")

	var http_request = HTTPRequest.new()
	add_child(http_request)

	var headers = ["Content-Type: application/x-www-form-urlencoded"]

	var body_parts = [
		"grant_type=refresh_token",
		"refresh_token=%s" % refresh_token,
		"client_id=%s" % CLIENT_ID
	]
	var body = "&".join(body_parts)

	var error = http_request.request(TOKEN_ENDPOINT, headers, HTTPClient.METHOD_POST, body)

	if error != OK:
		print("❌ HTTP request error: %s" % error)
		http_request.queue_free()
		return false

	var response = await http_request.request_completed
	http_request.queue_free()

	var response_code = response[1]
	var response_body = response[3].get_string_from_utf8()

	if response_code != 200:
		print("❌ Token refresh failed: %s" % response_body)
		return false

	var json = JSON.new()
	var parse_result = json.parse(response_body)

	if parse_result != OK:
		print("❌ Failed to parse token response")
		return false

	var data = json.data

	if data.has("access_token"):
		access_token = data["access_token"]

		if data.has("refresh_token"):
			refresh_token = data["refresh_token"]

		if data.has("expires_in"):
			token_expiry = Time.get_unix_time_from_system() + int(data["expires_in"])

		if data.has("id_token"):
			id_token = data["id_token"]
			user_profile = _decode_jwt_payload(id_token)

		_save_tokens()
		token_refreshed.emit()
		return true

	return false


## Logout and clear tokens
func logout() -> void:
	access_token = ""
	refresh_token = ""
	id_token = ""
	token_expiry = 0
	user_profile = {}

	# Delete token file
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists(TOKEN_FILE):
		dir.remove(TOKEN_FILE)

	print("🚪 Logged out successfully")


# ===== Private Methods =====

func _start_auth_flow() -> void:
	# Generate PKCE codes
	code_verifier = _generate_code_verifier()
	code_challenge = _generate_code_challenge(code_verifier)

	# Determine redirect URI based on mode
	var redirect_uri = PRODUCTION_REDIRECT_URI if current_auth_mode == AuthMode.PRODUCTION else LOCAL_REDIRECT_URI

	# Start local server ONLY for local mode
	if current_auth_mode == AuthMode.LOCAL:
		_start_redirect_server()
	else:
		# For production mode, we'll poll the game's API or use a different callback mechanism
		print("⚠️ Production mode: Manual code entry required after browser auth")

	# Build authorization URL
	var auth_url_parts = [
		"client_id=%s" % CLIENT_ID,
		"redirect_uri=%s" % redirect_uri.uri_encode(),
		"response_type=code",
		"scope=%s" % SCOPES.uri_encode(),
		"code_challenge=%s" % code_challenge,
		"code_challenge_method=S256"
	]

	var auth_url = AUTH_SERVER + "?" + "&".join(auth_url_parts)

	print("📱 Opening browser for authentication...")
	print("  Mode: %s" % ("Local" if current_auth_mode == AuthMode.LOCAL else "Production"))
	print("  Redirect: %s" % redirect_uri)
	OS.shell_open(auth_url)


func _start_redirect_server() -> void:
	var err = tcp_server.listen(LOCAL_REDIRECT_PORT, LOCAL_REDIRECT_HOST)

	if err != OK:
		print("❌ Failed to start redirect server on port %d: %s" % [LOCAL_REDIRECT_PORT, err])
		authentication_failed.emit("Failed to start local server")
		return

	is_listening = true
	set_process(true)
	print("✅ Redirect server listening on %s:%d" % [LOCAL_REDIRECT_HOST, LOCAL_REDIRECT_PORT])


func _exchange_code_for_tokens(auth_code: String) -> void:
	print("🔄 Exchanging authorization code for tokens...")

	var http_request = HTTPRequest.new()
	add_child(http_request)

	var headers = ["Content-Type: application/x-www-form-urlencoded"]

	var redirect_uri = PRODUCTION_REDIRECT_URI if current_auth_mode == AuthMode.PRODUCTION else LOCAL_REDIRECT_URI

	var body_parts = [
		"grant_type=authorization_code",
		"code=%s" % auth_code,
		"client_id=%s" % CLIENT_ID,
		"redirect_uri=%s" % redirect_uri,
		"code_verifier=%s" % code_verifier
	]
	var body = "&".join(body_parts)

	var error = http_request.request(TOKEN_ENDPOINT, headers, HTTPClient.METHOD_POST, body)

	if error != OK:
		print("❌ HTTP request error: %s" % error)
		http_request.queue_free()
		authentication_failed.emit("HTTP request failed")
		return

	var response = await http_request.request_completed
	http_request.queue_free()

	var response_code = response[1]
	var response_body = response[3].get_string_from_utf8()

	if response_code != 200:
		print("❌ Token exchange failed: %s" % response_body)
		authentication_failed.emit("Token exchange failed: %s" % response_body)
		return

	var json = JSON.new()
	var parse_result = json.parse(response_body)

	if parse_result != OK:
		print("❌ Failed to parse token response")
		authentication_failed.emit("Invalid token response")
		return

	var data = json.data

	if data.has("access_token"):
		access_token = data["access_token"]
		refresh_token = data.get("refresh_token", "")
		id_token = data.get("id_token", "")

		if data.has("expires_in"):
			token_expiry = Time.get_unix_time_from_system() + int(data["expires_in"])

		# Decode user profile from ID token
		if id_token:
			user_profile = _decode_jwt_payload(id_token)

		_save_tokens()

		print("✅ Authentication successful!")
		print("  User: %s" % user_profile.get("preferred_username", "Unknown"))
		authentication_completed.emit(true)
	else:
		print("❌ No access token in response")
		authentication_failed.emit("No access token received")


# ===== PKCE Helpers =====

func _generate_code_verifier() -> String:
	# Generate random 43-character string (base64url without padding)
	var bytes = PackedByteArray()
	for i in range(32):
		bytes.append(randi() % 256)
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")


func _generate_code_challenge(verifier: String) -> String:
	# SHA256 hash of verifier, then base64url encode
	var hash = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(verifier.to_utf8_buffer())
	var hashed = hash.finish()
	return Marshalls.raw_to_base64(hashed).replace("+", "-").replace("/", "_").replace("=", "")


# ===== Token Storage =====

func _save_tokens() -> void:
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(SAVE_DIR):
		dir.make_dir_recursive(SAVE_DIR)

	var file = FileAccess.open_encrypted_with_pass(TOKEN_FILE, FileAccess.WRITE, ENCRYPTION_PASS)

	if file:
		var token_data = {
			"access_token": access_token,
			"refresh_token": refresh_token,
			"id_token": id_token,
			"token_expiry": token_expiry,
			"user_profile": user_profile
		}
		file.store_var(token_data)
		file.close()
		print("💾 Tokens saved securely")


func _load_tokens() -> void:
	if not FileAccess.file_exists(TOKEN_FILE):
		return

	var file = FileAccess.open_encrypted_with_pass(TOKEN_FILE, FileAccess.READ, ENCRYPTION_PASS)

	if file:
		var token_data = file.get_var()
		file.close()

		if token_data:
			access_token = token_data.get("access_token", "")
			refresh_token = token_data.get("refresh_token", "")
			id_token = token_data.get("id_token", "")
			token_expiry = token_data.get("token_expiry", 0)
			user_profile = token_data.get("user_profile", {})
			print("💾 Tokens loaded from storage")


# ===== HTTP Helpers =====

func _extract_auth_code(request: String) -> String:
	# Parse HTTP request to extract authorization code
	# Example: GET /?code=ABC123&scope=openid+profile HTTP/1.1

	var lines = request.split("\r\n")
	if lines.size() == 0:
		return ""

	var first_line = lines[0]
	var parts = first_line.split(" ")

	if parts.size() < 2:
		return ""

	var path = parts[1]

	if not "code=" in path:
		return ""

	# Extract code parameter
	var code_start = path.find("code=") + 5
	var code_end = path.find("&", code_start)

	if code_end == -1:
		code_end = path.find(" ", code_start)
	if code_end == -1:
		code_end = path.length()

	return path.substr(code_start, code_end - code_start)


func _send_http_response(connection: StreamPeerTCP, status_code: int, html: String) -> void:
	var status_text = "OK" if status_code == 200 else "Bad Request"
	var response = "HTTP/1.1 %d %s\r\n" % [status_code, status_text]
	response += "Content-Type: text/html; charset=utf-8\r\n"
	response += "Content-Length: %d\r\n" % html.length()
	response += "Connection: close\r\n"
	response += "\r\n"
	response += html

	connection.put_data(response.to_utf8_buffer())


func _get_success_html() -> String:
	return """
<!DOCTYPE html>
<html>
<head>
	<title>Authentication Successful</title>
	<style>
		body {
			font-family: Arial, sans-serif;
			display: flex;
			justify-content: center;
			align-items: center;
			height: 100vh;
			margin: 0;
			background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
			color: white;
		}
		.container {
			text-align: center;
			padding: 40px;
			background: rgba(255, 255, 255, 0.1);
			border-radius: 20px;
			backdrop-filter: blur(10px);
		}
		h1 { margin: 0 0 20px 0; }
		p { margin: 10px 0; }
	</style>
</head>
<body>
	<div class="container">
		<h1>✅ Authentication Successful!</h1>
		<p>You can now close this window and return to the game.</p>
	</div>
</body>
</html>
"""


func _get_error_html(error_msg: String) -> String:
	return """
<!DOCTYPE html>
<html>
<head>
	<title>Authentication Error</title>
	<style>
		body {
			font-family: Arial, sans-serif;
			display: flex;
			justify-content: center;
			align-items: center;
			height: 100vh;
			margin: 0;
			background: linear-gradient(135deg, #ea5455 0%, #feb692 100%);
			color: white;
		}
		.container {
			text-align: center;
			padding: 40px;
			background: rgba(255, 255, 255, 0.1);
			border-radius: 20px;
			backdrop-filter: blur(10px);
		}
		h1 { margin: 0 0 20px 0; }
		p { margin: 10px 0; }
	</style>
</head>
<body>
	<div class="container">
		<h1>❌ Authentication Error</h1>
		<p>%s</p>
		<p>Please close this window and try again.</p>
	</div>
</body>
</html>
""" % error_msg


# ===== JWT Helpers =====

func _decode_jwt_payload(jwt: String) -> Dictionary:
	# Decode JWT payload (middle part of token)
	var parts = jwt.split(".")
	if parts.size() != 3:
		return {}

	var payload_b64 = parts[1]
	# Add padding if needed
	while payload_b64.length() % 4 != 0:
		payload_b64 += "="

	# Replace URL-safe base64 chars
	payload_b64 = payload_b64.replace("-", "+").replace("_", "/")

	var payload_bytes = Marshalls.base64_to_raw(payload_b64)
	var payload_str = payload_bytes.get_string_from_utf8()

	var json = JSON.new()
	var parse_result = json.parse(payload_str)

	if parse_result == OK:
		return json.data

	return {}
