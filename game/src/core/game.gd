extends Node
## Global game state, settings and the shared event bus.
## Autoloaded as `Game`.

signal state_changed(state: String)
signal message(text: String, seconds: float)
signal objective_changed(cut: int, total: int)
signal player_damaged(amount, from)
signal player_died
signal enemy_hit(enemy, killed, weak)
signal explosion(at: Vector3, radius: float)
signal relay_cut(index: int)

enum State { TITLE, PLAYING, PAUSED, DEAD, COMPLETE }

const RELAY_TOTAL := 3

var state: State = State.TITLE
var relay_cut_count := 0
var retries := 0
var seed_value := 4207
var run_time := 0.0

var settings := {
	"look_sens": 1.0,
	"invert_y": false,
	"ads_sens_scale": 0.62,
	"fov": 74.0,
	"ads_fov": 54.0,
	"vibration": 1.0,
	"shadows": false,
}

var player = null
var level = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_state(next: State) -> void:
	if state == next:
		return
	state = next
	if next != State.PLAYING:
		Haptics.stop_all()
		Pad.clear_triggers()
	state_changed.emit(state_name(next))


static func state_name(s: State) -> String:
	match s:
		State.TITLE: return "title"
		State.PLAYING: return "playing"
		State.PAUSED: return "paused"
		State.DEAD: return "dead"
		State.COMPLETE: return "complete"
	return "unknown"


func reset_run(seed_in: int = -1) -> void:
	if seed_in >= 0:
		seed_value = seed_in
	relay_cut_count = 0
	run_time = 0.0
	objective_changed.emit(0, RELAY_TOTAL)


func cut_relay(index: int) -> void:
	relay_cut_count += 1
	relay_cut.emit(index)
	objective_changed.emit(relay_cut_count, RELAY_TOTAL)
	Haptics.play("relay")
	if relay_cut_count >= RELAY_TOTAL:
		message.emit("All relays dark 鈥?reach the boat", 3.5)
	else:
		message.emit("Relay %d/%d cut" % [relay_cut_count, RELAY_TOTAL], 2.0)


func _process(delta: float) -> void:
	if state == State.PLAYING:
		run_time += delta
