class_name AuthScreen
extends Control

## Authentication screen that handles login/logout flow

@onready var login_panel: PanelContainer = $LoginPanel
@onready var status_label: Label = $LoginPanel/VBoxContainer/StatusLabel
@onready var production_button: Button = $LoginPanel/VBoxContainer/ProductionButton
@onready var local_button: Button = $LoginPanel/VBoxContainer/LocalButton
@onready var user_panel: PanelContainer = $UserPanel
@onready var username_label: Label = $UserPanel/VBoxContainer/UsernameLabel
@onready var logout_button: Button = $UserPanel/VBoxContainer/LogoutButton

signal authentication_complete(use_maincloud: bool)

func _ready() -> void:
	# Connect auth signals
	SpacetimeAuth.authentication_started.connect(_on_authentication_started)
	SpacetimeAuth.authentication_completed.connect(_on_authentication_completed)
	SpacetimeAuth.authentication_failed.connect(_on_authentication_failed)

	# Connect button signals
	production_button.pressed.connect(_on_production_button_pressed)
	local_button.pressed.connect(_on_local_button_pressed)
	logout_button.pressed.connect(_on_logout_button_pressed)

	# Check if already authenticated
	if SpacetimeAuth.is_authenticated() and not SpacetimeAuth.is_token_expired():
		_show_authenticated_state()
	else:
		_show_login_state()


func _show_login_state() -> void:
	login_panel.show()
	user_panel.hide()
	status_label.text = "Choose your connection mode"
	production_button.disabled = false
	local_button.disabled = false


func _show_authenticated_state() -> void:
	login_panel.hide()
	user_panel.show()

	var profile = SpacetimeAuth.get_user_profile()
	var username = profile.get("preferred_username", profile.get("name", "Player"))
	username_label.text = "Signed in as: %s" % username


func _on_production_button_pressed() -> void:
	print("🌐 Production mode selected - authenticating with SpacetimeDB...")
	status_label.text = "Opening browser for authentication..."
	production_button.disabled = true
	local_button.disabled = true

	# Set connection to maincloud
	MultiplayerManager.set_connection_mode(true)

	# Start OAuth flow with production mode (GitHub Pages callback)
	SpacetimeAuth.authenticate(SpacetimeAuth.AuthMode.PRODUCTION)


func _on_local_button_pressed() -> void:
	print("🏠 Local mode selected - using local SpacetimeDB...")
	status_label.text = "Connecting to local server..."
	production_button.disabled = true
	local_button.disabled = true

	# Set connection to local
	MultiplayerManager.set_connection_mode(false)

	# Wait for connection to be established
	MultiplayerManager.connection_established.connect(_on_local_connection_ready, CONNECT_ONE_SHOT)

	# Connect directly without auth
	MultiplayerManager.connect_to_server()


func _on_local_connection_ready() -> void:
	status_label.text = "Connected! Loading game..."
	await get_tree().create_timer(0.3).timeout
	authentication_complete.emit(false)


func _on_logout_button_pressed() -> void:
	SpacetimeAuth.logout()
	_show_login_state()


func _on_authentication_started() -> void:
	status_label.text = "Waiting for browser authentication..."


func _on_authentication_completed(success: bool) -> void:
	if success:
		_show_authenticated_state()

		# Connect to SpacetimeDB with auth token
		MultiplayerManager.connect_to_server()

		# Auto-proceed to game after short delay
		await get_tree().create_timer(1.0).timeout
		authentication_complete.emit(true)
	else:
		status_label.text = "Authentication failed. Please try again."
		production_button.disabled = false
		local_button.disabled = false


func _on_authentication_failed(error: String) -> void:
	status_label.text = "Error: %s" % error
	production_button.disabled = false
	local_button.disabled = false
	print("Authentication failed: %s" % error)
