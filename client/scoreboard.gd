extends Control

@onready var placings_container: VBoxContainer = $PlacingsContainer

func _ready() -> void:
	NetworkClient.match_ended.connect(_on_match_ended)

func _on_match_ended(placings: Array) -> void:
	for child in placings_container.get_children():
		child.queue_free()

	for p in placings:
		var row := Label.new()
		row.text = "#%d  %s  (%d)" % [p["place"], p["name"], p["total"]]
		row.add_theme_color_override("font_color", Color(p["colour"]))
		placings_container.add_child(row)
