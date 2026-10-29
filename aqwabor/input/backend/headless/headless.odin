package headless

import "core:mem"
import "core:sync"
import "aqwabor:input"
import "aqwabor:logx"

// Backend is an input.Backend whose events are injected programmatically.
//
// It is intended for tests, headless servers and LLM-driven playtesting: the
// same Action logic that runs against real hardware can be driven by injecting
// synthetic events, and consumed deterministically with a fixed timestep.
Backend :: struct {
	mu:    sync.Mutex,
	queue: [dynamic]input.Event,
}

g_log: ^logx.Logger
g_allocator: mem.Allocator
g_arena: mem.Dynamic_Arena

// New creates an empty headless Backend.
New :: proc() -> ^Backend {
	b := new(Backend, context.allocator)
	b.queue = make([dynamic]input.Event, 0, 16, context.allocator)
	return b
}

push :: proc(b: ^Backend, e: input.Event) {
	sync.mutex_lock(&b.mu)
	_ = append(&b.queue, e)
	sync.mutex_unlock(&b.mu)
	logx.logger_trace(g_log, "headless injected event", "kind", e.Kind, "key", e.Key, "button", e.Button, "x", e.X, "y", e.Y)
}

// Poll returns and clears the events injected since the last call.
Poll :: proc(b: ^Backend) -> [dynamic]input.Event {
	sync.mutex_lock(&b.mu)
	q := b.queue
	b.queue = make([dynamic]input.Event, 0, 16, context.allocator)
	sync.mutex_unlock(&b.mu)
	logx.logger_trace(g_log, "headless poll", "events", len(q))
	return q
}

// KeyDown injects a key press edge.
KeyDown :: proc(b: ^Backend, k: input.Key) {
	push(b, input.Event{Kind = input.EventKind.KeyDown, Key = k})
}

// KeyUp injects a key release edge.
KeyUp :: proc(b: ^Backend, k: input.Key) {
	push(b, input.Event{Kind = input.EventKind.KeyUp, Key = k})
}

// MouseMove injects a pointer movement to (x, y).
MouseMove :: proc(b: ^Backend, x: f64, y: f64) {
	push(b, input.Event{Kind = input.EventKind.MouseMove, X = x, Y = y})
}

// MouseDown injects a mouse button press at (x, y).
MouseDown :: proc(b: ^Backend, btn: input.MouseButton, x: f64, y: f64) {
	push(b, input.Event{Kind = input.EventKind.MouseDown, Button = btn, X = x, Y = y})
}

// MouseUp injects a mouse button release at (x, y).
MouseUp :: proc(b: ^Backend, btn: input.MouseButton, x: f64, y: f64) {
	push(b, input.Event{Kind = input.EventKind.MouseUp, Button = btn, X = x, Y = y})
}

init :: proc() {
	mem.dynamic_arena_init(&g_arena)
	g_allocator = mem.dynamic_arena_allocator(&g_arena)
	g_log = logx.with(g_allocator)
}
