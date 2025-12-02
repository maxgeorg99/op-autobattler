extends CanvasLayer

const TOOLTIP_SCENE := preload("res://scenes/tooltip/tooltip.tscn")

var tooltip: Tooltip

func _ready() -> void:
	tooltip = TOOLTIP_SCENE.instantiate()
	add_child(tooltip)
	tooltip.z_index = 100

func show_tooltip(text: String, position: Vector2, pos_mode: Tooltip.Position = Tooltip.Position.ABOVE, font_size: int = 0) -> void:
	if text.is_empty():
		return
	tooltip.show_tooltip(text, position, pos_mode, font_size)

func hide_tooltip() -> void:
	tooltip.hide_tooltip()
