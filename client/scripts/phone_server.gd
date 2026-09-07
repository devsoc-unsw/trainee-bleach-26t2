class_name PhoneServer
extends Node

signal hit_received(power: float, stick_x: float, stick_y: float)
signal urls_changed
signal pose_received(beta: float, gamma: float, holding: bool, stick_x: float, stick_y: float, lift: float, power: float, accel: float, yaw: float, recenter: bool, look_x: float, look_y: float, zoom: float)
signal power_used(kind: String, slot: int)
signal restart_requested
signal type_received(text: String, done: bool, closing: bool)
signal client_seen

const HTML_PATH := "res://ui/phone_remote.html"
const PORT := 27351
const PORT_FALLBACKS: Array[int] = [27351, 28351, 29351, 33771, 45771, 55771, 8099]
const TLS_PORT_FALLBACKS: Array[int] = [27443, 28443, 29443, 33443, 45443, 55443]
const PORT_CFG := "user://phone_remote.cfg"
const MAX_BUFFER := 65536
const MAX_PEERS := 32
# Publicly published certificate for *.local-ip.sh, a wildcard DNS service that
# resolves 192-168-0-31.local-ip.sh to 192.168.0.31. Because the certificate is
# signed by Let's Encrypt the phone gets a real secure context with no warning
# and no chrome://flags entry, which is what the motion sensor requires.
const TLS_CERT_PATH := "res://certs/local_ip_cert.pem"
const TLS_KEY_PATH := "res://certs/local_ip_key.pem"
const TLS_DOMAIN := "local-ip.sh"

var _server := TCPServer.new()
var _tls_server := TCPServer.new()
var _peers: Array[StreamPeerTCP] = []
var _tls: Array = []
var _bufs: Array[PackedByteArray] = []
var _html := ""
var _port := PORT
var _tls_port := 0
var _tls_host := ""
var _tls_options: TLSOptions
var _dns_queue := -1
var _dns_want := ""
var _last_error := ""
var _cached_ips: PackedStringArray
var _ip_thread: Thread
var _ip_scan_done := false
var _left_kind := ""
var _left_left := 0.0
var _right_kind := ""
var _right_left := 0.0
var _rank := 0
var _rank_text := ""
var _rank_caption := ""
var _type_on := false
var _type_text := ""
var _type_hint := ""
var _type_max := 32


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_listening() -> bool:
	return _server.is_listening()


func listen_port() -> int:
	return _port


func last_error() -> String:
	return _last_error


func set_powers(left_kind: String, left_left: float, right_kind: String, right_left: float) -> void:
	_left_kind = left_kind
	_left_left = maxf(left_left, 0.0)
	_right_kind = right_kind
	_right_left = maxf(right_left, 0.0)


func set_rank(place: int, label: String = "", caption: String = "") -> void:
	_rank = maxi(place, 0)
	_rank_text = label if not label.is_empty() else _ordinal(_rank)
	_rank_caption = caption if _rank > 0 else ""


func set_type(on: bool, text: String = "", hint: String = "", max_len: int = 32) -> void:
	_type_on = on
	_type_text = text
	_type_hint = hint
	_type_max = maxi(max_len, 1)


func ensure_listening() -> Error:
	if _server.is_listening():
		return OK
	_load_html()
	if _html.is_empty():
		_last_error = "Cannot read %s" % HTML_PATH
		push_error("PhoneServer: %s" % _last_error)
		return ERR_FILE_NOT_FOUND
	var tried: Array[int] = []
	for port in _candidate_ports():
		tried.append(port)
		if _server.listen(port, "0.0.0.0") == OK:
			_port = port
			_last_error = ""
			_save_port(port)
			set_process(true)
			print("PhoneServer listening on port %d" % port)
			_try_listen_tls()
			return OK
	_last_error = "Windows blocked every port we tried: %s" % str(tried)
	push_error("PhoneServer: %s" % _last_error)
	return ERR_CANT_CONNECT


# Secure listener for the motion sensor. Entirely optional: if anything here
# fails the plain HTTP listener above keeps working on its own. The DNS lookup
# runs through the async queue so a slow resolver cannot stall startup.
func _try_listen_tls() -> void:
	if _tls_server.is_listening() or _dns_queue != -1:
		return
	var ips := lan_ips()
	var host := _best_lan_ip(ips)
	if host.is_empty():
		return
	if not _is_preferred_ip(host) and not _ip_scan_done:
		return
	_dns_want = host
	_tls_host = "%s.%s" % [host.replace(".", "-"), TLS_DOMAIN]
	_dns_queue = IP.resolve_hostname_queue_item(_tls_host, IP.TYPE_IPV4)


func _poll_dns() -> void:
	var status := IP.get_resolve_item_status(_dns_queue)
	if status == IP.RESOLVER_STATUS_WAITING:
		return
	var found := IP.get_resolve_item_address(_dns_queue)
	IP.erase_resolve_item(_dns_queue)
	_dns_queue = -1
	# Only advertise the secure name if this network's DNS maps it back to us.
	# Some routers refuse to answer with private addresses.
	if status != IP.RESOLVER_STATUS_DONE or found != _dns_want:
		print("PhoneServer: %s did not resolve to %s, staying on http" % [_tls_host, _dns_want])
		_tls_host = ""
		return
	if not _load_tls():
		_tls_host = ""
		return
	for port in _tls_candidate_ports():
		if _tls_server.listen(port, "0.0.0.0") == OK:
			_tls_port = port
			_save_tls_port(port)
			print("PhoneServer secure page at https://%s:%d/" % [_tls_host, port])
			urls_changed.emit()
			return
	_tls_host = ""


func _load_tls() -> bool:
	if _tls_options != null:
		return true
	var key := CryptoKey.new()
	if key.load(TLS_KEY_PATH) != OK:
		push_warning("PhoneServer: cannot read %s" % TLS_KEY_PATH)
		return false
	var cert := X509Certificate.new()
	if cert.load(TLS_CERT_PATH) != OK:
		push_warning("PhoneServer: cannot read %s" % TLS_CERT_PATH)
		return false
	_tls_options = TLSOptions.server(key, cert)
	return true


func secure_url() -> String:
	if _tls_port <= 0:
		return ""
	return "https://%s:%d/" % [_tls_host, _tls_port]


func _candidate_ports() -> Array[int]:
	var ports: Array[int] = []
	var saved := _saved_port()
	if saved > 0:
		ports.append(saved)
	for port in PORT_FALLBACKS:
		if not ports.has(port):
			ports.append(port)
	return ports


func _tls_candidate_ports() -> Array[int]:
	var ports: Array[int] = []
	var saved := _saved_value("tls_port")
	if saved > 0:
		ports.append(saved)
	for port in TLS_PORT_FALLBACKS:
		if not ports.has(port):
			ports.append(port)
	return ports


func _saved_port() -> int:
	return _saved_value("port")


func _saved_value(key: String) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(PORT_CFG) != OK:
		return 0
	return int(cfg.get_value("phone", key, 0))


func _save_port(port: int) -> void:
	_save_value("port", port)


func _save_tls_port(port: int) -> void:
	_save_value("tls_port", port)


func _save_value(key: String, port: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PORT_CFG)
	cfg.set_value("phone", key, port)
	cfg.save(PORT_CFG)


func public_urls() -> PackedStringArray:
	var urls := PackedStringArray()
	var secure := secure_url()
	if not secure.is_empty():
		urls.append(secure)
	var ips := lan_ips()
	if ips.size() > 0:
		urls.append("http://%s:%d/" % [ips[0], _port])
	return urls


func local_url() -> String:
	return "http://127.0.0.1:%d/" % _port


func lan_ips() -> PackedStringArray:
	if _cached_ips.size() > 0:
		_start_ip_scan()
		return _cached_ips
	var seen := {}
	var ips: Array[String] = []
	for ip in IP.get_local_addresses():
		if _usable_ipv4(ip) and not seen.has(ip):
			seen[ip] = true
			ips.append(ip)
	ips.sort_custom(func(a: String, b: String) -> bool: return _rank_ip(a) < _rank_ip(b))
	_cached_ips = PackedStringArray(ips)
	_start_ip_scan()
	return _cached_ips


func _start_ip_scan() -> void:
	if _ip_scan_done or _ip_thread != null:
		return
	_ip_thread = Thread.new()
	_ip_thread.start(_ipconfig_worker)


func _ipconfig_worker() -> void:
	var extra := _ips_from_ipconfig()
	call_deferred("_merge_lan_ips", extra)


func _merge_lan_ips(extra: Array) -> void:
	if _ip_thread != null:
		_ip_thread.wait_to_finish()
		_ip_thread = null
	_ip_scan_done = true
	var added := false
	var ips: Array[String] = []
	for ip in _cached_ips:
		ips.append(ip)
	for item in extra:
		var ip := str(item)
		if not _usable_ipv4(ip):
			continue
		var known := false
		for have in ips:
			if have == ip:
				known = true
				break
		if known:
			continue
		ips.append(ip)
		added = true
	if not added:
		_try_listen_tls()
		return
	ips.sort_custom(func(a: String, b: String) -> bool: return _rank_ip(a) < _rank_ip(b))
	_cached_ips = PackedStringArray(ips)
	_try_listen_tls()
	urls_changed.emit()


func _best_lan_ip(ips: PackedStringArray) -> String:
	for ip in ips:
		if _is_preferred_ip(ip):
			return ip
	if ips.size() > 0:
		return ips[0]
	return ""


func _is_preferred_ip(ip: String) -> bool:
	return ip.begins_with("192.168.") or ip.begins_with("10.")


func _load_html() -> void:
	if not _html.is_empty():
		return
	_html = FileAccess.get_file_as_string(HTML_PATH)


func _exit_tree() -> void:
	if _ip_thread != null:
		_ip_thread.wait_to_finish()
		_ip_thread = null


func _process(_delta: float) -> void:
	if not _server.is_listening():
		return
	if _dns_queue != -1:
		_poll_dns()
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer == null:
			break
		_add_peer(peer, null)
	while _tls_server.is_listening() and _tls_server.is_connection_available():
		var peer := _tls_server.take_connection()
		if peer == null:
			break
		var tls := StreamPeerTLS.new()
		if tls.accept_stream(peer, _tls_options) != OK:
			peer.disconnect_from_host()
			continue
		_add_peer(peer, tls)
	var i := 0
	while i < _peers.size():
		var peer := _peers[i]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_drop(i)
			continue
		var stream: StreamPeer = peer
		var tls: StreamPeerTLS = _tls[i]
		if tls != null:
			tls.poll()
			var tls_status := tls.get_status()
			if tls_status == StreamPeerTLS.STATUS_HANDSHAKING:
				i += 1
				continue
			if tls_status != StreamPeerTLS.STATUS_CONNECTED:
				_drop(i)
				continue
			stream = tls
		var available := stream.get_available_bytes()
		if available > 0:
			var chunk: Array = stream.get_partial_data(available)
			if int(chunk[0]) == OK:
				_bufs[i].append_array(chunk[1])
		if _bufs[i].size() > MAX_BUFFER:
			_respond(stream, 413, "text/plain; charset=utf-8", "too large")
			_drop(i)
			continue
		if _try_handle(i):
			continue
		i += 1


func _add_peer(peer: StreamPeerTCP, tls: StreamPeerTLS) -> void:
	peer.set_no_delay(true)
	_peers.append(peer)
	_tls.append(tls)
	_bufs.append(PackedByteArray())
	while _peers.size() > MAX_PEERS:
		_close(0)
		_drop(0)


func _stream(index: int) -> StreamPeer:
	var tls: StreamPeerTLS = _tls[index]
	if tls != null:
		return tls
	return _peers[index]


func _close(index: int) -> void:
	var tls: StreamPeerTLS = _tls[index]
	if tls != null:
		tls.disconnect_from_stream()
	_peers[index].disconnect_from_host()


func _try_handle(index: int) -> bool:
	var header_at := _header_end(_bufs[index])
	if header_at < 0:
		return false
	var rest_start := 4
	if header_at >= 0 and header_at + 1 < _bufs[index].size() and _bufs[index][header_at] == 10:
		rest_start = 2
	var header := _bufs[index].slice(0, header_at).get_string_from_utf8()
	var rest := _bufs[index].slice(header_at + rest_start)
	var content_length := _content_length(header)
	if rest.size() < content_length:
		return false
	var body := rest.slice(0, content_length)
	_bufs[index] = rest.slice(content_length)
	var peer := _stream(index)
	var request_line := header.get_slice("\r\n", 0)
	if request_line == header:
		request_line = header.get_slice("\n", 0)
	var parts := request_line.split(" ")
	var method := parts[0] if parts.size() > 0 else ""
	var raw_path := parts[1] if parts.size() > 1 else "/"
	var path := raw_path.split("?")[0]
	if method == "POST" and (path == "/hit" or path == "/swing"):
		var hit := _stick_from_body(body)
		var power := clampf(float(hit.get("power", 0.0)), 0.0, 1.0)
		if power >= 0.05:
			hit_received.emit(power, float(hit.get("sx", 0.0)), float(hit.get("sy", 0.0)))
		_respond(peer, 200, "application/json", "{\"ok\":true}", true)
		_close(index)
		_drop(index)
		return true
	if method == "POST" and path == "/pose":
		_emit_pose(body)
		_respond(peer, 200, "application/json", _powers_json(), false)
		return false
	if method == "POST" and path == "/power":
		var payload := _stick_from_body(body)
		var kind := str(payload.get("kind", ""))
		var slot := int(payload.get("slot", -1))
		if kind == "shield" or kind == "shrink" or kind == "gust":
			power_used.emit(kind, slot)
		_respond(peer, 200, "application/json", "{\"ok\":true}", true)
		_close(index)
		_drop(index)
		return true
	if method == "POST" and path == "/restart":
		restart_requested.emit()
		_respond(peer, 200, "application/json", "{\"ok\":true}", true)
		_close(index)
		_drop(index)
		return true
	if method == "POST" and path == "/type":
		var typed := _stick_from_body(body)
		type_received.emit(str(typed.get("text", "")), bool(typed.get("done", false)), bool(typed.get("close", false)))
		_respond(peer, 200, "application/json", "{\"ok\":true}", true)
		_close(index)
		_drop(index)
		return true
	if method == "OPTIONS":
		_respond(peer, 204, "text/plain; charset=utf-8", "", true)
	elif method == "GET" or method == "HEAD":
		if path == "/favicon.ico":
			_respond(peer, 204, "text/plain; charset=utf-8", "", true)
		elif path == "/hello":
			client_seen.emit()
			_respond(peer, 200, "application/json", "{\"ok\":true}", true)
		else:
			client_seen.emit()
			_load_html()
			_respond(peer, 200, "text/html; charset=utf-8", _html if method == "GET" else "", true)
	else:
		_respond(peer, 404, "text/plain; charset=utf-8", "not found", true)
	_close(index)
	_drop(index)
	return true


func _respond(peer: StreamPeer, code: int, content_type: String, body: String, close_conn: bool = true) -> void:
	var payload := body.to_utf8_buffer()
	var reason := "OK"
	if code == 204:
		reason = "No Content"
	elif code == 404:
		reason = "Not Found"
	elif code == 413:
		reason = "Payload Too Large"
	var conn := "close" if close_conn else "keep-alive"
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: %s\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\n\r\n" % [
		code, reason, content_type, payload.size(), conn
	]
	peer.put_data(head.to_utf8_buffer())
	if payload.size() > 0 and code != 204:
		peer.put_data(payload)


func _powers_json() -> String:
	return JSON.stringify({
		"ok": true,
		"leftKind": _left_kind,
		"leftLeft": _left_left,
		"rightKind": _right_kind,
		"rightLeft": _right_left,
		"rank": _rank,
		"rankText": _rank_text,
		"rankCaption": _rank_caption,
		"typeOn": _type_on,
		"typeText": _type_text,
		"typeHint": _type_hint,
		"typeMax": _type_max,
	})


func _ordinal(place: int) -> String:
	if place < 1:
		return ""
	var tens := place % 100
	var ones := place % 10
	if tens >= 11 and tens <= 13:
		return "%dth" % place
	if ones == 1:
		return "%dst" % place
	if ones == 2:
		return "%dnd" % place
	if ones == 3:
		return "%drd" % place
	return "%dth" % place


func _emit_pose(body: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	pose_received.emit(
		float(data.get("b", 75.0)),
		float(data.get("g", 0.0)),
		bool(data.get("h", 0)),
		clampf(float(data.get("sx", 0.0)), -1.0, 1.0),
		clampf(float(data.get("sy", 0.0)), -1.0, 1.0),
		float(data.get("u", 0.0)),
		clampf(float(data.get("p", 0.0)), 0.0, 1.0),
		float(data.get("a", 0.0)),
		float(data.get("al", 0.0)),
		bool(data.get("c", 0)),
		clampf(float(data.get("lx", 0.0)), -1.0, 1.0),
		clampf(float(data.get("ly", 0.0)), -1.0, 1.0),
		clampf(float(data.get("z", 0.0)), -1.0, 1.0)
	)


func _drop(index: int) -> void:
	_peers.remove_at(index)
	_tls.remove_at(index)
	_bufs.remove_at(index)


func _header_end(buf: PackedByteArray) -> int:
	var n := buf.size()
	if n < 4:
		return -1
	for i in range(n - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	for i in range(n - 1):
		if buf[i] == 10 and buf[i + 1] == 10:
			return i
	return -1


func _content_length(header: String) -> int:
	for line in header.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			return maxi(0, int(line.get_slice(":", 1).strip_edges()))
	return 0


func _stick_from_body(body: PackedByteArray) -> Dictionary:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		return parsed
	return {}


func _power_from_body(body: PackedByteArray) -> float:
	return clampf(float(_stick_from_body(body).get("power", 0.0)), 0.0, 1.0)


func _usable_ipv4(ip: String) -> bool:
	if ip.is_empty() or ip.contains(":"):
		return false
	if ip.begins_with("127.") or ip.begins_with("169.254."):
		return false
	var parts := ip.split(".")
	if parts.size() != 4:
		return false
	return true


func _rank_ip(ip: String) -> int:
	if ip.begins_with("192.168."):
		return 0
	if ip.begins_with("10."):
		return 1
	return 2


func _ips_from_ipconfig() -> Array[String]:
	var pipe: Array = []
	var exe := "ipconfig" if OS.get_name() == "Windows" else "ipconfig.exe"
	OS.execute(exe, PackedStringArray(), pipe, true, false)
	var text := ""
	for item in pipe:
		text += str(item) + "\n"
	var ips: Array[String] = []
	for line in text.split("\n"):
		if "IPv4 Address" not in line and "IP Address" not in line:
			continue
		if "Subnet" in line or "Gateway" in line or "DNS" in line:
			continue
		var matched := _first_ipv4(line)
		if not matched.is_empty():
			ips.append(matched)
	return ips


func _first_ipv4(line: String) -> String:
	var parts := line.split(" ")
	for part in parts:
		var token := part.strip_edges().trim_suffix(":").trim_suffix(".")
		if _usable_ipv4(token) or (token.find(".") > 0 and token.split(".").size() == 4):
			if token.begins_with("127.") or token.begins_with("169.254."):
				continue
			if token.split(".").size() == 4:
				return token
	var digits := ""
	var dots := 0
	for i in line.length():
		var ch := line.substr(i, 1)
		if ch >= "0" and ch <= "9":
			digits += ch
		elif ch == ".":
			digits += ch
			dots += 1
		else:
			if dots == 3 and _usable_ipv4(digits):
				return digits
			digits = ""
			dots = 0
	if dots == 3 and _usable_ipv4(digits):
		return digits
	return ""
