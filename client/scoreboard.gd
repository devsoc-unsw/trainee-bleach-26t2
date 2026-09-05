extends Control

@onready var title_label: Label = $TitleLabel
@onready var placings_container: VBoxContainer = $PlacingsPanel/PlacingsContainer

func _ready() -> void:
	NetworkClient.match_ended.connect(_on_match_ended)

func _on_match_ended(placings: Array) -> void:
	for child in placings_container.get_children():
		child.queue_free()

	title_label.text = "Match Complete"
	modulate.a = 0.0

	var rows: Array[Control] = []
	for p in placings:
		var row := Label.new()
		var is_local := String(p.get("playerId", "")) == NetworkClient.my_player_id
		var you := "  (you)" if is_local else ""
		row.text = "#%d   %s%s     %d strokes" % [p["place"], p["name"], you, p["total"]]
		row.add_theme_color_override("font_color", Color(p["colour"]))
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.modulate.a = 0.0
		placings_container.add_child(row)
		rows.append(row)

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	for i in range(rows.size() - 1, -1, -1):
		tween.tween_property(rows[i], "modulate:a", 1.0, 0.22)
