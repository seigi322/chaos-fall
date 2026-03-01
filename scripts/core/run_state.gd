extends Node
class_name RunState

## Manages the current run state: level, XP, chips, etc.

signal level_changed(new_level: int)
signal xp_changed(new_xp: int, max_xp: int)
signal chips_changed(new_chips: int)
signal total_chips_changed(new_total: int)
signal spins_changed(remaining: int, max: int)
signal chaos_changed(new_chaos: int, max_chaos: int)
signal chaos_max_reached()
signal lock_charges_changed(new_charges: int, max_charges: int)

const SPINS_PER_LEVEL := 10
const MAX_CHAOS := 100  # Run ends when chaos reaches this value
const INITIAL_CHAOS := 10  # Chaos value at run start and after restart
const MAX_LOCK_CHARGES := 3  # Maximum lock charges player can have
const STARTING_LOCK_CHARGES := 10  # Lock charges at start of run

var level: int = 0
var xp: int = 0
var xp_max: int = 100
var chips: int = 0  # Current chips earned this hand
var total_chips: int = 0  # Total chips accumulated
var spins_remaining: int = SPINS_PER_LEVEL
var chaos: int = 0  # Chaos value (0-100)
var lock_charges: int = STARTING_LOCK_CHARGES  # Lock charges available

func _ready() -> void:
	reset_run()

func reset_run() -> void:
	level = 0  # Reset level to 0
	xp = 0
	xp_max = 100
	chips = 0
	total_chips = 0  # Reset score (total chips) to 0
	spins_remaining = SPINS_PER_LEVEL
	chaos = INITIAL_CHAOS
	lock_charges = STARTING_LOCK_CHARGES  # Start with 2 lock charges
	level_changed.emit(level)
	xp_changed.emit(xp, xp_max)
	chips_changed.emit(chips)
	total_chips_changed.emit(total_chips)  # Emit total chips changed signal
	spins_changed.emit(spins_remaining, SPINS_PER_LEVEL)
	chaos_changed.emit(chaos, MAX_CHAOS)
	lock_charges_changed.emit(lock_charges, MAX_LOCK_CHARGES)

## Re-emit all state signals so UI is forced to sync (e.g. after restart).
func notify_listeners() -> void:
	level_changed.emit(level)
	xp_changed.emit(xp, xp_max)
	chips_changed.emit(chips)
	total_chips_changed.emit(total_chips)
	spins_changed.emit(spins_remaining, SPINS_PER_LEVEL)
	chaos_changed.emit(chaos, MAX_CHAOS)
	lock_charges_changed.emit(lock_charges, MAX_LOCK_CHARGES)

func add_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_max:
		xp -= xp_max
		level_up()
	xp_changed.emit(xp, xp_max)

func level_up() -> void:
	level += 1
	# XP requirement increases (simple formula)
	xp_max = int(100 * pow(1.5, level - 1))
	# Reset spins for new level
	spins_remaining = SPINS_PER_LEVEL
	level_changed.emit(level)
	xp_changed.emit(xp, xp_max)
	spins_changed.emit(spins_remaining, SPINS_PER_LEVEL)

func add_chips(amount: int) -> void:
	chips += amount
	total_chips += amount
	chips_changed.emit(chips)
	total_chips_changed.emit(total_chips)

func reset_chips() -> void:
	chips = 0
	chips_changed.emit(chips)

func use_spin() -> bool:
	# Returns true if spin was used, false if no spins remaining
	if spins_remaining <= 0:
		return false
	spins_remaining -= 1
	spins_changed.emit(spins_remaining, SPINS_PER_LEVEL)
	return true

func add_chaos(amount: int) -> void:
	var old_chaos = chaos
	chaos += amount
	if chaos >= MAX_CHAOS:
		chaos = MAX_CHAOS
	# Emit signal when chaos reaches or exceeds MAX_CHAOS (only once)
	if old_chaos < MAX_CHAOS and chaos >= MAX_CHAOS:
		chaos_max_reached.emit()
	chaos_changed.emit(chaos, MAX_CHAOS)

func reduce_chaos(amount: int) -> void:
	# Rare chaos reduction (only from stabilization moments or special jokers)
	chaos -= amount
	if chaos < 0:
		chaos = 0
	chaos_changed.emit(chaos, MAX_CHAOS)

## Chaos gain multiplier by tier (before adding chaos this spin). Stacks with joker multipliers.
## 0–25 → x1, 25–50 → x1.2, 50–75 → x1.5, 75–100 → x2
func get_chaos_tier_multiplier() -> float:
	if chaos < 25:
		return 1.0
	if chaos < 50:
		return 1.2
	if chaos < 75:
		return 1.5
	return 2.0

func get_chaos_penalty_multiplier() -> float:
	# Returns a multiplier based on chaos level
	# At 0 chaos: 1.0 (no penalty)
	# At 50 chaos: 0.75 (25% penalty)
	# At 100 chaos: 0.5 (50% penalty)
	# Linear interpolation
	var penalty_ratio = float(chaos) / float(MAX_CHAOS)
	return 1.0 - (penalty_ratio * 0.5)  # Max 50% penalty

func use_lock_charge() -> bool:
	# Consume 1 lock charge when spin is pressed (if any cards were locked)
	# Returns true if charge was consumed, false if no charges available
	if lock_charges <= 0:
		return false
	lock_charges -= 1
	lock_charges_changed.emit(lock_charges, MAX_LOCK_CHARGES)
	return true

func restore_lock_charge() -> void:
	# Restore 1 lock charge when player scores a valid combo
	# No maximum limit - players can have unlimited charges
	lock_charges += 1
	lock_charges_changed.emit(lock_charges, MAX_LOCK_CHARGES)
