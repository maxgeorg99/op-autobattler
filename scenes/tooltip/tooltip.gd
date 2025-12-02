class_name Tooltip
extends PanelContainer

enum Position { ABOVE, RIGHT, BELOW, LEFT }

@onready var label: RichTextLabel = %Label

func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_tooltip(text: String, cur_position: Vector2, pos_mode: Position = Position.ABOVE, font_size: int = 0) -> void:
	label.text = text

	if font_size > 0:
		label.add_theme_font_size_override("normal_font_size", font_size)
	else:
		label.remove_theme_font_size_override("normal_font_size")

	reset_size()

	var offset := Vector2.ZERO
	match pos_mode:
		Position.ABOVE:
			offset = Vector2(0, -80)
		Position.RIGHT:
			offset = Vector2(80, 0)
		Position.BELOW:
			offset = Vector2(0, 10)
		Position.LEFT:
			offset = Vector2(-80, 0)

	global_position = cur_position + offset
	show()

func hide_tooltip() -> void:
	hide()
