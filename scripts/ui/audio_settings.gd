extends Node

## Autoload: ensures SFX/Music buses exist, loads/saves volume to user://settings.cfg.
## Run before SfxManager so buses exist when SFX players are created.

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "audio"

const BUS_MASTER := "Master"
const BUS_SFX := "SFX"
const BUS_MUSIC := "Music"

const DEFAULT_MASTER := 1.0
const DEFAULT_SFX := 1.0
const DEFAULT_MUSIC := 1.0

func _ready() -> void:
	_ensure_buses()
	_load_and_apply()

func _ensure_buses() -> void:
	if AudioServer.get_bus_index(BUS_SFX) < 0:
		AudioServer.add_bus(1)
		AudioServer.set_bus_name(1, BUS_SFX)
	if AudioServer.get_bus_index(BUS_MUSIC) < 0:
		AudioServer.add_bus(2)
		AudioServer.set_bus_name(2, BUS_MUSIC)

func _volume_linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return linear_to_db(linear)

func _load_and_apply() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		_apply_volume(BUS_MASTER, DEFAULT_MASTER)
		_apply_volume(BUS_SFX, DEFAULT_SFX)
		_apply_volume(BUS_MUSIC, DEFAULT_MUSIC)
		return
	var master: float = cfg.get_value(SECTION, "master_volume", DEFAULT_MASTER)
	var sfx: float = cfg.get_value(SECTION, "sfx_volume", DEFAULT_SFX)
	var music: float = cfg.get_value(SECTION, "music_volume", DEFAULT_MUSIC)
	_apply_volume(BUS_MASTER, master)
	_apply_volume(BUS_SFX, sfx)
	_apply_volume(BUS_MUSIC, music)

func _apply_volume(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, _volume_linear_to_db(linear))

func get_volume(bus_name: StringName) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 1.0
	var db: float = AudioServer.get_bus_volume_db(idx)
	if db <= -80.0:
		return 0.0
	return db_to_linear(db)

func set_volume(bus_name: StringName, linear: float) -> void:
	_apply_volume(bus_name, linear)
	_save()

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "master_volume", get_volume(BUS_MASTER))
	cfg.set_value(SECTION, "sfx_volume", get_volume(BUS_SFX))
	cfg.set_value(SECTION, "music_volume", get_volume(BUS_MUSIC))
	cfg.save(CONFIG_PATH)
