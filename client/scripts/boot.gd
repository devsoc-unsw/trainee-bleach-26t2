extends Control

const TITLE_SCENE := "res://scenes/title.tscn"
const MIN_TIME := 2.4
const MAX_TIME := 6.0

const MESSAGES: Array[String] = [
	"Warming up the cart",
	"Packing the clubs",
	"Lining up the greens",
	"Checking the flags",
	"Almost there",
]

@onready var status_label: Label = $Overlay/Status
@onready var bar: ProgressBar = $Overlay/Bar

var _pending: Array[String] = []
var _loaded := 0
var _total := 1
var _elapsed := 0.0
var _done := false
var _display := 0.0
var _partial := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Only the next scene. Requesting packed scenes plus their nested GLBs/shaders
	# on worker threads can deadlock ResourceLoader, so the bar never finishes.
	if ResourceLoader.exists(TITLE_SCENE):
		var err := ResourceLoader.load_threaded_request(TITLE_SCENE)
		if err == OK:
			_pending.append(TITLE_SCENE)
		else:
			_loaded = 1
	else:
		_loaded = 1
	_total = maxi(_pending.size() + _loaded, 1)
	set_process(true)


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	_poll_loads()
	var load_t := clampf((float(_loaded) + _partial) / float(_total), 0.0, 1.0)
	var time_t := clampf(_elapsed / MIN_TIME, 0.0, 1.0)
	var target := minf(load_t, time_t) if _loaded >= _total or _elapsed >= MAX_TIME else minf(load_t, 0.92)
	_display = lerpf(_display, target, 1.0 - exp(-delta * 8.0))
	bar.value = _display
	var msg_i := clampi(int(_display * float(MESSAGES.size() - 1) + 0.001), 0, MESSAGES.size() - 1)
	status_label.text = MESSAGES[msg_i] + ".".repeat(int(_elapsed * 2.4) % 4)
	if (_loaded >= _total and _elapsed >= MIN_TIME) or _elapsed >= MAX_TIME:
		_finish()


func _poll_loads() -> void:
	_partial = 0.0
	var still: Array[String] = []
	for path in _pending:
		var prog: Array = []
		var status := ResourceLoader.load_threaded_get_status(path, prog)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
			_loaded += 1
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_loaded += 1
		else:
			still.append(path)
			if not prog.is_empty():
				_partial += float(prog[0])
	_pending = still


func _finish() -> void:
	_done = true
	bar.value = 1.0
	status_label.text = "Ready!"
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.28).set_delay(0.08)
	tw.tween_callback(func() -> void:
		get_tree().change_scene_to_file(TITLE_SCENE)
	)
