class_name UnitGrid
extends Node2D

signal unit_grid_changed

@export var size: Vector2i

var units: Dictionary


func _ready() -> void:
	for i in size.x:
		for j in size.y:
			units[Vector2i(i, j)] = null


func add_unit(tile: Vector2i, unit: Node) -> void:
	units[tile] = unit
	unit.tree_exited.connect(_on_unit_tree_exited.bind(unit, tile))
	unit_grid_changed.emit()


func remove_unit(tile: Vector2i) -> void:
	var unit := units[tile] as Node
	
	if not unit:
		return
	
	unit.tree_exited.disconnect(_on_unit_tree_exited)
	units[tile] = null
	unit_grid_changed.emit()


func is_tile_occupied(tile: Vector2i) -> bool:
	return units[tile] != null


func is_grid_full() -> bool:
	return units.keys().all(is_tile_occupied)


func get_first_empty_tile() -> Vector2i:
	for tile in units:
		if not is_tile_occupied(tile):
			return tile

	# no empty tile
	return Vector2i(-1, -1)


func get_all_units() -> Array[Unit]:
	var unit_array: Array[Unit] = []
	
	for unit: Unit in units.values():
		if unit:
			unit_array.append(unit)
	
	return unit_array


func get_all_occupied_tiles() -> Array[Vector2i]:
	var tile_array: Array[Vector2i] = []
	
	for tile: Vector2i in units.keys():
		if units[tile]:
			tile_array.append(tile)
	
	return tile_array


func _on_unit_tree_exited(unit: Node, tile: Vector2i) -> void:
	if unit.is_queued_for_deletion():
		units[tile] = null
		unit_grid_changed.emit()


# ===== Serialization for Multiplayer =====

func serialize_units() -> Array:
	var serialized = []

	for tile: Vector2i in get_all_occupied_tiles():
		var unit = units[tile]
		if not unit:
			continue

		# Get unit stats
		var unit_stats = unit.stats if unit.has("stats") else null
		if not unit_stats:
			continue

		var unit_data = {
			"unit_name": unit_stats.resource_path.get_file().get_basename(),  # e.g., "zoro" from "zoro.tres"
			"tier": unit_stats.tier,
			"x": tile.x,
			"y": tile.y,
			"on_bench": false,  # Will be set by the caller if needed
			"items": _serialize_items(unit)
		}

		serialized.append(unit_data)

	return serialized


func _serialize_items(unit: Node) -> Array:
	var items = []

	if not unit.has("item_handler"):
		return items

	var item_handler = unit.item_handler
	if not item_handler:
		return items

	for i in range(item_handler.equipped_items.size()):
		var item = item_handler.equipped_items[i]
		if item:
			items.append({
				"item_id": item.id,
				"equip_index": i
			})

	return items
