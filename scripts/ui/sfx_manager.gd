extends Node

## Autoload: plays SFX from assets/track at the right moments. Loud files use 30% volume.

const VOLUME_DB_30 := -10.5  # ~30% linear
const VOLUME_DB_LOW := -14.0  # ~20% for secondary underlayer

# Paths (match assets/track filenames)
const SPIN_BUTTON := "res://assets/track/spin button press.wav"
const REEL_SPIN_PRIMARY := "res://assets/track/reel spin sound primary.wav"
const REEL_SPIN_SECONDARY := (
	"res://assets/track/reel spin add secondary as underlayer at low volume when spin.wav"
)
const REEL_STOP := "res://assets/track/reel stop.wav"
const ROW_SCORES := "res://assets/track/row 1 2 3 score before total score comes.wav"
const COUNTING_SCORE := "res://assets/track/counting score sound.wav"
const FINAL_RESOLVE := "res://assets/track/final resolve score after score counts.wav"
const RETRIGGER := "res://assets/track/retrigger.wav"
const SMALL_ROW_SCORE := "res://assets/track/small-row-score.wav"
const MEDIUM_ROW_SCORE := "res://assets/track/medium-row-score.wav"
const BIG_ROW_SCORE := "res://assets/track/big-row-score.wav"
const LOCK := "res://assets/track/lock.wav"

# Score levels: Low <3000, Medium 3000-7000, Big 7000+
const SCORE_LEVEL_LOW := 3000
const SCORE_LEVEL_MEDIUM := 7000

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}

func _ready() -> void:
	_preload_streams()
	# Use a few players so we can overlap (e.g. spin primary + secondary, or row + count)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)

func _preload_streams() -> void:
	var paths := [SPIN_BUTTON, REEL_SPIN_PRIMARY, REEL_SPIN_SECONDARY, REEL_STOP, ROW_SCORES, COUNTING_SCORE, FINAL_RESOLVE, RETRIGGER, SMALL_ROW_SCORE, LOCK]
	for path in paths:
		var s: AudioStream = load(path) as AudioStream
		if s != null:
			_streams[path] = s
	for path in [MEDIUM_ROW_SCORE, BIG_ROW_SCORE]:
		if ResourceLoader.exists(path):
			var s: AudioStream = load(path) as AudioStream
			if s != null:
				_streams[path] = s

func _play(path: String, volume_db: float = VOLUME_DB_30) -> void:
	var stream: AudioStream = _streams.get(path)
	if stream == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return
	# All busy: use first player (will cut previous)
	var p0: AudioStreamPlayer = _players[0]
	p0.stop()
	p0.stream = stream
	p0.volume_db = volume_db
	p0.play()

func play_spin_button() -> void:
	_play(SPIN_BUTTON)

func play_reel_spin_primary() -> void:
	_play(REEL_SPIN_PRIMARY)

func stop_reel_spin_primary() -> void:
	var primary: AudioStream = _streams.get(REEL_SPIN_PRIMARY)
	if primary == null:
		return
	for p in _players:
		if p.stream == primary and p.playing:
			p.stop()
			return

func play_reel_spin_secondary() -> void:
	_play(REEL_SPIN_SECONDARY, VOLUME_DB_LOW)

func play_reel_stop() -> void:
	_play(REEL_STOP)

func play_row_scores() -> void:
	_play(ROW_SCORES)

func play_counting_score() -> void:
	_play(COUNTING_SCORE)

## Play counting score for retrigger; stop after half the clip length.
func play_counting_score_for_retrigger() -> void:
	_play(COUNTING_SCORE)
	var stream: AudioStream = _streams.get(COUNTING_SCORE)
	if stream != null and stream.get_length() > 0.0:
		var half := stream.get_length() * 0.5
		var t := get_tree().create_timer(half)
		t.timeout.connect(stop_counting_score, CONNECT_ONE_SHOT)

func stop_counting_score() -> void:
	var stream: AudioStream = _streams.get(COUNTING_SCORE)
	if stream == null:
		return
	for p in _players:
		if p.stream == stream and p.playing:
			p.stop()
			return

func play_final_resolve() -> void:
	_play(FINAL_RESOLVE)

func play_retrigger() -> void:
	_play(RETRIGGER)

func play_lock() -> void:
	_play(LOCK)

## Play row score sound by level: Low under 3000 = small, Medium 3000-7000 = medium, Big 7000+ = big.
func play_row_score_by_level(total_score: int) -> void:
	var path: String
	if total_score < SCORE_LEVEL_LOW:
		path = SMALL_ROW_SCORE
	elif total_score < SCORE_LEVEL_MEDIUM:
		path = MEDIUM_ROW_SCORE
	else:
		path = BIG_ROW_SCORE
	if _streams.has(path):
		_play(path)

## Chaos threshold sound removed; kept as no-op so callers do not need to change.
func play_chaos_threshold_if_crossed(_chaos_before: int, _chaos_after: int) -> void:
	pass
