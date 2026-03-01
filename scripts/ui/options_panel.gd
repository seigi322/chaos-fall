extends Popup

## Volume settings panel. Reads/writes AudioSettings and persists to config.

signal closed

@onready var master_slider: HSlider = $Content/VBox/MasterRow/MasterSlider
@onready var sfx_slider: HSlider = $Content/VBox/SfxRow/SfxSlider
@onready var music_slider: HSlider = $Content/VBox/MusicRow/MusicSlider
@onready var close_button: Button = $Content/VBox/CloseButton

func _ready() -> void:
	if master_slider:
		master_slider.value = AudioSettings.get_volume(AudioSettings.BUS_MASTER)
		master_slider.value_changed.connect(_on_master_changed)
	if sfx_slider:
		sfx_slider.value = AudioSettings.get_volume(AudioSettings.BUS_SFX)
		sfx_slider.value_changed.connect(_on_sfx_changed)
	if music_slider:
		music_slider.value = AudioSettings.get_volume(AudioSettings.BUS_MUSIC)
		music_slider.value_changed.connect(_on_music_changed)
	if close_button:
		close_button.pressed.connect(_close)
	popup_hide.connect(_on_popup_hide)

func _on_master_changed(value: float) -> void:
	AudioSettings.set_volume(AudioSettings.BUS_MASTER, value)

func _on_sfx_changed(value: float) -> void:
	AudioSettings.set_volume(AudioSettings.BUS_SFX, value)

func _on_music_changed(value: float) -> void:
	AudioSettings.set_volume(AudioSettings.BUS_MUSIC, value)

func _on_popup_hide() -> void:
	if not is_queued_for_deletion():
		emit_signal("closed")
		queue_free()

func _close() -> void:
	hide()
