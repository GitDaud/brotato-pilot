extends Reference

# Optional experiment mode. Native pools, probabilities and combat rules remain
# intact. Phase seeds isolate menus from the preceding combat's RNG consumption;
# changed luck/equipment and changed combat call order can still change outcomes.
var pilot
var fixed_seed = -1
var resume_path = ""
var restored = false
var counts = {}
var replay_wave = 0
var last_command = ""
var wave_only = false
var wave_cleared = false

func _init(owner):
	pilot = owner

func configure(config):
	if config.has("seed"):
		fixed_seed = int(config.seed)
	resume_path = str(config.get("resume_checkpoint", ""))
	wave_only = bool(config.get("practice_wave_only",false))

func apply_scope(stream, wave, index = 0):
	if fixed_seed < 0:
		return -1
	var derived = int((fixed_seed % 2147483647 * 48271 + int(stream.hash()) % 2147483647 + wave * 1000003 + index * 104729) % 2147483647)
	seed(derived)
	Utils.set_rng_seed(derived)
	pilot.record("seed_scope", {"stream":stream,"wave":wave,"index":index,"seed":derived,"experiment_seed":fixed_seed})
	return derived

func next_scope(stream, wave, player = 0):
	var key = "%s/%s/%s" % [stream,wave,player]
	var index = int(counts.get(key,0))
	counts[key] = index + 1
	return apply_scope(stream + "/" + str(player),wave,index)

func wave_start():
	if fixed_seed < 0:
		return
	if pilot.recording_id == "":
		pilot.begin_recording()
	apply_scope("combat",RunData.current_wave)
	var folder = pilot.evidence + "/checkpoints/" + str(fixed_seed) + "/" + pilot.recording_id
	Directory.new().make_dir_recursive(folder)
	var state = ProgressData.get_run_state()
	var serialized = ProgressDataLoaderV3.new().serialize_run_state(state)
	var payload = {"schema":1,"seed":fixed_seed,"source_run_id":pilot.recording_id,"character":pilot.selected_character,"wave":RunData.current_wave,"difficulty":RunData.current_difficulty,"counts":counts.duplicate(),"state":serialized}
	var path = folder + "/wave-%02d.json" % RunData.current_wave
	var f = File.new()
	if f.open(path,File.WRITE) == OK:
		f.store_string(JSON.print(payload))
		f.close()
		pilot.record("wave_checkpoint",{"path":path,"wave":RunData.current_wave,"retries":RunData.retries})

func restore_checkpoint():
	if restored or resume_path == "":
		return false
	restored = true
	var prefix = pilot.evidence + "/checkpoints/" + str(fixed_seed) + "/"
	var f = File.new()
	if not resume_path.begins_with(prefix) or "/../" in resume_path or f.open(resume_path,File.READ) != OK:
		pilot.enabled = false
		pilot.decision = "Checkpoint unavailable"
		return true
	var payload = parse_json(f.get_as_text())
	f.close()
	if not payload is Dictionary or payload.get("seed",-1) != fixed_seed or payload.get("character","") != pilot.selected_character or payload.get("difficulty",-1) != pilot.challenge_difficulty:
		pilot.enabled = false
		pilot.decision = "Checkpoint identity mismatch"
		return true
	var state = ProgressDataLoaderV3.new().deserialize_run_state(payload.state)
	if not state.get("has_run_state",false):
		pilot.enabled = false
		pilot.decision = "Invalid checkpoint state"
		return true
	RunData.resume_from_state(state)
	RunData.retries = int(state.retries) + 1
	RunData.run_won = false
	counts = payload.get("counts",{}).duplicate()
	replay_wave = int(state.current_wave)
	pilot.begin_recording()
	pilot.record("checkpoint_restore",{"path":resume_path,"wave":replay_wave,"retries":RunData.retries,"practice":true})
	var error = pilot.get_tree().change_scene(MenuData.game_scene)
	if error != OK:
		pilot.enabled = false
		pilot.decision = "Checkpoint scene failed"
	return true

func process_command(scene):
	if fixed_seed < 0:
		return false
	var f = File.new()
	if f.open(pilot.evidence + "/control.json",File.READ) != OK:
		return false
	var command = parse_json(f.get_as_text())
	f.close()
	if not command is Dictionary or str(command.get("id","")) == last_command:
		return false
	if command.get("run_id","") != pilot.recording_id:
		return false
	if command.get("action","") == "retry_wave" and scene.has_node("EntitySpawner"):
		var retry = scene.get("_retry_wave")
		if is_instance_valid(retry) and retry.is_visible_in_tree():
			last_command = str(command.get("id",""))
			pilot.record("practice_retry",{"wave":RunData.current_wave,"retries_before":RunData.retries})
			retry._on_ConfirmButton_pressed()
			return true
	return false
