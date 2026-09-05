extends Area3D

signal oob_triggered

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	var putt := body as PuttBall
	if putt == null:
		return

	print("Ball went out of bounds")
	oob_triggered.emit()
