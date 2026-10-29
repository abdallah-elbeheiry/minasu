package input

import "core:mem"
import "aqwabor:logx"

g_log: ^logx.Logger
g_allocator: mem.Allocator
g_arena: mem.Dynamic_Arena

init :: proc() {
	mem.dynamic_arena_init(&g_arena)
	g_allocator = mem.dynamic_arena_allocator(&g_arena)
	g_log = logx.with(g_allocator)
}

// EventKind enumerates the kinds of raw events a Backend can emit.
EventKind :: enum u8 {
    KeyDown,   // emitted on a key press edge
    KeyUp,     // emitted on a key release edge
    MouseDown, // emitted on a mouse button press edge
    MouseUp,   // emitted on a mouse button release edge
    MouseMove, // emitted when the pointer changes position
}

// Event is a single raw input event produced by a Backend.
Event :: struct {
	Kind:   EventKind,
	Key:    Key,
	Button: MouseButton,
	X, Y:   f64, // valid for mouse events
}

// ActionEventType enumerates the derived events recorded by Manager.Drain.
ActionEventType :: enum u8 {
    Pressed,
    Released,
    Hold,
    Tap,
    Toggle,
    Drag,
}

// ActionEvent is a recorded, replayable derived event.
ActionEvent :: struct {
	Type:   ActionEventType,
	Action: ^Action,
	Now:    f64, // Manager clock (seconds) at dispatch
	Dt:     f64, // frame delta (seconds) that produced this event
	Active: bool,   // toggle state, for EventTypeToggle
	DX, DY: f64,    // movement delta, for EventTypeDrag
}

// Backend supplies raw input events to the Manager.
//
// Implementations must be safe to call from the same thread that calls
// Manager.Update. Poll is called once per frame and should return the events
// that occurred since the previous call (an empty slice is fine).
Backend :: proc() -> [dynamic]Event



// Context is passed to every callback. It is a value type and is reused
// across dispatches within a single frame, so callbacks must consume it
// synchronously (they always do).
Context :: struct {
	mgr:    ^Manager,
	action: ^Action,
	now:    f64,
	dt:     f64,
}

// MousePosition returns the current pointer position in window coordinates.
MousePosition :: proc(c: Context) -> (f64, f64) {
	return c.mgr.mouseX, c.mgr.mouseY
}

// ActionCtx returns the Action that triggered the current callback.
ActionCtx :: proc(c: Context) -> ^Action {
	return c.action
}

// NowCtx returns the Manager clock (seconds) at the time of dispatch.
NowCtx :: proc(c: Context) -> f64 {
	return c.now
}

// DtCtx returns the frame delta (seconds) that produced the current dispatch.
//
// OnHold fires once per frame, so any accumulation must scale by Dt to be
// frame-rate independent: charge += rate*ctx.Dt().
DtCtx :: proc(c: Context) -> f64 {
	return c.dt
}

// Default tuning constants for derived tap behaviour.
defaultTapMax :: f64

// Manager owns all Actions and drives event processing.
Manager :: struct {
	backend: Backend,

	actions: [dynamic]^Action,
	byName:  map[string]^Action,

	clock: f64,

	keysDown:  map[Key]bool,
	mouseDown: [MouseButton.Count]bool,
	mouseX:    f64,
	mouseY:    f64,

	ctx: Context,

	recording: bool,
	events:    [dynamic]ActionEvent,
}

// NewManager creates a Manager fed by the given Backend.
NewManager :: proc(backend: Backend) -> ^Manager {
	m := new(Manager, context.allocator)
	m.backend = backend
	m.byName = make(map[string]^Action, context.allocator)
	m.keysDown = make(map[Key]bool, context.allocator)
	m.ctx.mgr = m
	logx.logger_debug(g_log, "input manager created")
	return m
}

// Action returns the named Action, creating it on first use.
ActionMgr :: proc(m: ^Manager, name: string) -> ^Action {
	if a, ok := m.byName[name]; ok {
		return a
	}
	a := new(Action, context.allocator)
	a.name = name
	a.mgr = m
	a.enabled = true
	append(&m.actions, a)
	m.byName[name] = a
	return a
}

// BindKey adds a keyboard binding to an Action. Bindings accumulate; an
// Action fires when any of its bindings is active.
BindKey :: proc(m: ^Manager, a: ^Action, k: Key) {
	append(&a.bindings, Binding{kind = .Key, key = k})
	logx.logger_debug(g_log, "bound key", "action", a.name, "key", k, "bindings", len(a.bindings))
}

// BindMouseButton adds a mouse button binding to an Action.
BindMouseButton :: proc(m: ^Manager, a: ^Action, b: MouseButton) {
	append(&a.bindings, Binding{kind = .Mouse, button = b})
	logx.logger_debug(g_log, "bound mouse button", "action", a.name, "button", b, "bindings", len(a.bindings))
}

// Combo returns (creating if needed) an Action that fires only when all the
// given keys are held simultaneously.
Combo :: proc(m: ^Manager, name: string, keys: ..Key) -> ^Action {
	a := ActionMgr(m, name)
	append(&a.bindings, Binding{kind = .Combo, combo = keys})
	logx.logger_debug(g_log, "bound combo", "action", name, "keys", keys)
	return a
}

// Rebind clears an Action's hardware bindings and binds a single key.
Rebind :: proc(m: ^Manager, a: ^Action, k: Key) {
	logx.logger_debug(g_log, "rebind", "action", a.name, "key", k)
	Unbind(a)
	BindKey(m, a, k)
}

// IsDown reports whether the Action is currently considered pressed.
IsDownMgr :: proc(m: ^Manager, a: ^Action) -> bool {
	return a.down
}

// MousePosition returns the current pointer position.
MousePositionMgr :: proc(m: ^Manager) -> (f64, f64) {
	return m.mouseX, m.mouseY
}

// Clock returns the internal clock (seconds) advanced by Update.
Clock :: proc(m: ^Manager) -> f64 {
	return m.clock
}

// SetRecording enables or disables recording of derived events.
SetRecording :: proc(m: ^Manager, on: bool) {
	m.recording = on
}

// Drain returns and clears the derived events recorded since the last call.
Drain :: proc(m: ^Manager) -> []ActionEvent {
	e := m.events[:]
	m.events = nil
	return e
}

// record appends a derived event to the buffer when recording is enabled.
record :: proc(m: ^Manager, t: ActionEventType, active: bool, dx: f64, dy: f64) {
	if !m.recording {
		return
	}
	append(&m.events, ActionEvent{Type = t, Action = m.ctx.action, Now = m.clock, Dt = m.ctx.dt, Active = active, DX = dx, DY = dy})
}

// Update advances the simulation by dt seconds, pumps the Backend for new
// raw events, and dispatches derived events to enabled Actions.
//
// Call this once per frame from your main loop (single-threaded).
	Update :: proc(m: ^Manager, dt: f64) {
		dt_in := dt
		if dt_in < 0 {
			dt_in = 0
		}
		m.clock += dt_in
		m.ctx.now = m.clock
		m.ctx.dt = dt_in

	eventCount := 0
	if m.backend != nil {
		backend_proc := m.backend
		events := backend_proc()
		for ev in events {
			applyEvent(m, ev)
			eventCount += 1
		}
	}

	for a in m.actions {
		process(a, m)
	}
	logx.logger_trace(g_log, "input frame", "clock", m.clock, "dt", dt_in, "raw_events", eventCount, "actions", len(m.actions))
}

applyEvent :: proc(m: ^Manager, ev: Event) {
	switch ev.Kind {
	case .KeyDown:
		m.keysDown[ev.Key] = true
		logx.logger_trace(g_log, "key down", "key", ev.Key)
	case .KeyUp:
		m.keysDown[ev.Key] = false
		logx.logger_trace(g_log, "key up", "key", ev.Key)
	case .MouseDown:
		if cast(int) ev.Button < cast(int) MouseButton.Count {
			m.mouseDown[cast(int) ev.Button] = true
		}
		m.mouseX, m.mouseY = ev.X, ev.Y
		logx.logger_trace(g_log, "mouse down", "button", ev.Button, "x", ev.X, "y", ev.Y)
	case .MouseUp:
		if cast(int) ev.Button < cast(int) MouseButton.Count {
			m.mouseDown[cast(int) ev.Button] = false
		}
		m.mouseX, m.mouseY = ev.X, ev.Y
		logx.logger_trace(g_log, "mouse up", "button", ev.Button, "x", ev.X, "y", ev.Y)
	case .MouseMove:
		m.mouseX, m.mouseY = ev.X, ev.Y
		logx.logger_trace(g_log, "mouse move", "x", ev.X, "y", ev.Y)
	}
}

append_elems_event :: proc(slice: ^[]ActionEvent, elem: ActionEvent) {
	tmp := slice^
	new_slice := make([]ActionEvent, len(tmp) + 1)
	copy(new_slice, tmp)
	new_slice[len(tmp)] = elem
	slice^ = new_slice
}

append_slice_proc_ctx :: proc(slice: ^[]proc(Context), elem: proc(Context)) {
	tmp := slice^
	new_slice := make([]proc(Context), len(tmp) + 1)
	copy(new_slice, tmp)
	new_slice[len(tmp)] = elem
	slice^ = new_slice
}

append_slice_action :: proc(slice: ^[]^Action, elem: ^Action) {
	tmp := slice^
	new_slice := make([]^Action, len(tmp) + 1)
	copy(new_slice, tmp)
	new_slice[len(tmp)] = elem
	slice^ = new_slice
}

append_slice_binding :: proc(slice: ^[]Binding, elem: Binding) {
	tmp := slice^
	new_slice := make([]Binding, len(tmp) + 1)
	copy(new_slice, tmp)
	new_slice[len(tmp)] = elem
	slice^ = new_slice
}

append_slice_holdHandler :: proc(slice: ^[]holdHandler, elem: holdHandler) {
	tmp := slice^
	new_slice := make([]holdHandler, len(tmp) + 1)
	copy(new_slice, tmp)
	new_slice[len(tmp)] = elem
	slice^ = new_slice
}

append_slice_proc_bool_ctx :: proc(slice: ^[]proc(bool, Context), elem: proc(bool, Context)) {
	tmp := slice^
	new_slice := make([]proc(bool, Context), len(tmp) + 1)
	copy(new_slice, tmp)
	new_slice[len(tmp)] = elem
	slice^ = new_slice
}

append_slice_proc_f64_f64_ctx :: proc(slice: ^[]proc(f64, f64, Context), elem: proc(f64, f64, Context)) {
	tmp := slice^
	new_slice := make([]proc(f64, f64, Context), len(tmp) + 1)
	copy(new_slice, tmp)
	new_slice[len(tmp)] = elem
	slice^ = new_slice
}

append_slice_event :: proc(slice: ^[]ActionEvent, elem: ActionEvent) {
	tmp := slice^
	new_slice := make([]ActionEvent, len(tmp) + 1)
	copy(new_slice, tmp)
	new_slice[len(tmp)] = elem
	slice^ = new_slice
}
