extends Control

## Main entry point that handles authentication before starting the game

const AUTH_SCREEN = preload("res://scenes/auth/auth_screen.tscn")
const ARENA_SCENE = preload("res://scenes/arena/arena.tscn")

@onready var container: Control = $Container

var auth_screen: AuthScreen = null

func _ready() -> void:
	# Show auth screen first
	_show_auth_screen()


func _show_auth_screen() -> void:
	# Clear container
	for child in container.get_children():
		child.queue_free()

	# Create and show auth screen
	auth_screen = AUTH_SCREEN.instantiate()
	container.add_child(auth_screen)

	# Connect signals
	auth_screen.authentication_complete.connect(_on_authentication_complete)


func _on_authentication_complete(use_maincloud: bool) -> void:
	print("Authentication complete! Mode: %s" % ("MAINCLOUD" if use_maincloud else "LOCAL"))
	print("Starting game...")
	_start_game()


func _start_game() -> void:
	# Remove auth screen
	if auth_screen:
		auth_screen.queue_free()
		auth_screen = null

	# Load and show arena
	var arena = ARENA_SCENE.instantiate()
	container.add_child(arena)
