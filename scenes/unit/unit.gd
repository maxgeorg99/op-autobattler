@tool
class_name Unit
extends Area2D

signal quick_sell_pressed

@export var stats: UnitStats : set = _set_stats

@onready var skin: PackedSprite2D = $Visuals/Skin
@onready var health_bar: ProgressBar = $HealthBar
@onready var mana_bar: ProgressBar = $ManaBar
@onready var tier_icon: TierIcon = $TierIcon
@onready var drag_and_drop: DragAndDrop = $DragAndDrop
@onready var item_handler: ItemHandler = $ItemHandler
@onready var velocity_based_rotation: VelocityBasedRotation = $VelocityBasedRotation
@onready var outline_highlighter: OutlineHighlighter = $OutlineHighlighter
@onready var animations: UnitAnimations = $UnitAnimations

var is_hovered := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		drag_and_drop.drag_started.connect(_on_drag_started)
		drag_and_drop.drag_canceled.connect(_on_drag_canceled)


func _input(event: InputEvent) -> void:
	if not is_hovered:
		return

	if event.is_action_pressed("quick_sell"):
		quick_sell_pressed.emit()

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_show_stats_tooltip()
			else:
				TooltipManager.hide_tooltip()


func _set_stats(value: UnitStats) -> void:
	stats = value
	
	if value == null or not is_instance_valid(tier_icon):
		return
	
	if not Engine.is_editor_hint():
		stats = value.duplicate()
	
	skin.coordinates = stats.skin_coordinates
	tier_icon.stats = stats


func reset_after_dragging(starting_position: Vector2) -> void:
	velocity_based_rotation.enabled = false
	global_position = starting_position


func _on_drag_started() -> void:
	velocity_based_rotation.enabled = true


func _on_drag_canceled(starting_position: Vector2) -> void:
	reset_after_dragging(starting_position)


func _on_mouse_entered() -> void:
	if drag_and_drop.dragging:
		return
	
	is_hovered = true
	outline_highlighter.highlight()
	z_index = 1


func _on_mouse_exited() -> void:
	if drag_and_drop.dragging:
		return

	is_hovered = false
	outline_highlighter.clear_highlight()
	z_index = 0
	TooltipManager.hide_tooltip()


func _show_stats_tooltip() -> void:
	var tooltip_text := _format_stats()
	TooltipManager.show_tooltip(tooltip_text, global_position, Tooltip.Position.LEFT, 15)


func _format_stats() -> String:
	var text := "[b]%s[/b] (Tier %d)\n" % [stats.name, stats.tier]

	# Base stats
	var base_hp := stats.get_max_health()
	var base_ad := stats.get_attack_damage()
	var base_as := stats.attack_speed
	var base_ap := stats.ability_power
	var base_armor := stats.armor
	var base_mr := stats.magic_resist

	# Calculate modified stats from items
	var mod_hp := base_hp
	var mod_ad := base_ad
	var mod_as := base_as
	var mod_ap := base_ap
	var mod_armor := base_armor
	var mod_mr := base_mr

	for i in range(item_handler.equipped_items.size()):
		var item = item_handler.equipped_items[i]
		if item:
			var mod_keys = item.modifiers.keys()
			for j in range(mod_keys.size()):
				var mod_type = mod_keys[j]
				var mod_value = item.modifiers[mod_type]
				match mod_type:
					Modifier.Type.UNIT_MAXHEALTH:
						mod_hp = _apply_modifier(mod_hp, mod_value)
					Modifier.Type.UNIT_AD:
						mod_ad = _apply_modifier(mod_ad, mod_value)
					Modifier.Type.UNIT_ATKSPEED:
						mod_as = _apply_modifier(mod_as, mod_value)
					Modifier.Type.UNIT_AP:
						mod_ap = _apply_modifier(mod_ap, mod_value)
					Modifier.Type.UNIT_ARMOR:
						mod_armor = _apply_modifier(mod_armor, mod_value)
					Modifier.Type.UNIT_MAGICRESIST:
						mod_mr = _apply_modifier(mod_mr, mod_value)

	# Format output
	text += "[b]Stats:[/b]\n"
	text += _stat_line("HP", base_hp, mod_hp)
	text += _stat_line("AD", base_ad, mod_ad)
	text += _stat_line("AS", base_as, mod_as)
	text += _stat_line("AP", base_ap, mod_ap)
	text += _stat_line("MR", base_mr, mod_mr)
	text += _stat_line("ARMOR", base_armor, mod_armor)

	# Show traits
	if stats.traits.size() > 0:
		text += "[b]Traits:[/b]\n"
		for i in range(stats.traits.size()):
			text += "%s " % stats.traits[i].name

	# Show items
	if item_handler.equipped_items.size() > 0:
		text += "[b]Items:[/b]\n"
		for i in range(item_handler.equipped_items.size()):
			if item_handler.equipped_items[i]:
				text += "• %s\n" % item_handler.equipped_items[i].name

	return text


func _apply_modifier(base: float, mod_value) -> float:
	var result := base
	result += mod_value.flat_value
	result *= (1.0 + mod_value.percent_value)
	return result


func _stat_line(stat_name: String, base: float, modified: float) -> String:
	if abs(modified - base) < 0.01:
		return "%s: %.1f\n" % [stat_name, base]
	else:
		return "%s: %.1f [color=green](+%.1f)[/color]\n" % [stat_name, modified, modified - base]
