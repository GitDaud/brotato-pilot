extends Node

# Optional read-only viewport export; never captures the user's desktop.
var pilot
var connection = StreamPeerTCP.new()
var connected = false
var next_frame = 0
var next_probe = 0

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	connection.big_endian = false
	VisualServer.connect("frame_post_draw", self, "_capture_frame")

func _capture_frame():
	if not pilot.recording_enabled or pilot.recording_id == "" or pilot.recording_ended:
		return
	var now = OS.get_ticks_msec()
	if not connected:
		if now < next_probe:
			return
		next_probe = now + 200
		if connection.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			connected = true
			connection.set_no_delay(true)
		else:
			var f = File.new()
			if f.open("F:/codex-project/tudou/recordings/" + pilot.recording_id + ".port.json", File.READ) != OK:
				return
			var config = parse_json(f.get_as_text())
			f.close()
			if config is Dictionary:
				connection.connect_to_host("127.0.0.1", int(config.port))
			return
	if now < next_frame:
		return
	next_frame = now + 33
	var frame = get_viewport().get_texture().get_data()
	if frame.get_width() == 0:
		return
	frame.flip_y()
	frame.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
	frame.convert(Image.FORMAT_RGB8)
	var pixels = frame.get_data()
	var packet = StreamPeerBuffer.new()
	packet.big_endian = false
	packet.put_u32(now)
	packet.put_u32(pixels.size())
	packet.put_data(pixels)
	if connection.put_data(packet.data_array) != OK:
		connected = false
