extends Node

## Keeps the canvas and UI in sync when the browser or editor window resizes.
## Screens can implement apply_layout() and join group "layout_fit".

signal fitted(size: Vector2)

const MIN_WINDOW := Vector2i(720, 480)

var _last := Vector2.ZERO
var _web_hooked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := get_tree().root
	if not root.size_changed.is_connected(_on_root_size):
		root.size_changed.connect(_on_root_size)
	if OS.has_feature("web"):
		_hook_web()
	else:
		DisplayServer.window_set_min_size(MIN_WINDOW)
	set_process(true)
	call_deferred("_emit_fit")


func _process(_delta: float) -> void:
	var sz := _view_size()
	if sz.distance_squared_to(_last) > 0.25:
		_emit_fit()


func _on_root_size() -> void:
	_emit_fit()


func _view_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	return vp.get_visible_rect().size


func _emit_fit() -> void:
	var sz := _view_size()
	if sz.x < 2.0 or sz.y < 2.0:
		return
	if sz.distance_squared_to(_last) < 0.25:
		return
	_last = sz
	fitted.emit(sz)
	get_tree().call_group("layout_fit", "apply_layout")


func _hook_web() -> void:
	if _web_hooked or not OS.has_feature("web"):
		return
	_web_hooked = true
	JavaScriptBridge.eval(
		"""
(function(){
  if (window._puttLayoutHook) return;
  window._puttLayoutHook = true;
  function sync() {
    var c = document.getElementById('canvas');
    var vv = window.visualViewport;
    var w = Math.max(1, Math.round((vv && vv.width) || window.innerWidth || 1));
    var h = Math.max(1, Math.round((vv && vv.height) || window.innerHeight || 1));
    if (c) {
      c.style.width = w + 'px';
      c.style.height = h + 'px';
    }
  }
  window.addEventListener('resize', sync);
  window.addEventListener('orientationchange', sync);
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', sync);
  }
  sync();
})();
""",
		true
	)
