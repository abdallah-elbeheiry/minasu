package input

import "aqwabor:logx"

// bindingKind distinguishes how a Binding maps hardware input to an Action.
bindingKind :: enum u8 {
    Key,   // the Action is active while key is down.
    Mouse, // the Action is active while the button is down.
    Combo, // the Action is active only while ALL combo keys are down.
}

// Binding maps hardware input to an Action.
//
//   - bindKey:    the Action is active while key is down.
//   - bindMouse:  the Action is active while the button is down.
//   - bindCombo:  the Action is active only while ALL combo keys are down.
//
// An Action with multiple bindings is active if ANY binding is active.
Binding :: struct {
	kind:   bindingKind,
	key:    Key,
	button: MouseButton,
	combo:  []Key,
}

// currentDown reports whether the Action should currently be considered
// pressed, based on its bindings and the live Manager state.
currentDown :: proc(a: ^Action, m: ^Manager) -> bool {
	for b in a.bindings {
		switch b.kind {
		case .Key:
			if m.keysDown[b.key] {
				return true
			}
		case .Mouse:
			if cast(int) b.button < cast(int) MouseButton.Count && m.mouseDown[cast(int) b.button] {
				return true
			}
		case .Combo:
			allDown := true
			for k in b.combo {
				if !m.keysDown[k] {
					allDown = false
					break
				}
			}
			if allDown {
				return true
			}
		}
	}
	return false
}

// holdHandler pairs a hold threshold with its callback.
holdHandler :: struct {
	threshold: f64,
	fn:        proc(Context),
}

// Action is the single user-facing input object. The user binds hardware to
// it, attaches callbacks to it, and controls it directly via Enable,
// Disable and Unbind.
Action :: struct {
	name:     string,
	mgr:      ^Manager,
	enabled:  bool,

	bindings: []Binding,

	onPress:   []proc(Context),
	onRelease: []proc(Context),
	onHold:    []holdHandler,
	onTap:     []proc(Context),
	onToggle:  []proc(bool, Context),
	onDrag:    []proc(f64, f64, Context),

	// Live state.
	down:       bool,
	downTime:   f64,
	active:     bool, // toggle state
	lastDragX:  f64,
	lastDragY:  f64,
}

// Name returns the Action's identifier.
Name :: proc(a: ^Action) -> string {
	return a.name
}

// Enabled reports whether the Action is currently delivering events.
Enabled :: proc(a: ^Action) -> bool {
	return a.enabled
}

// Enable resumes event delivery. Callbacks and bindings are preserved.
Enable :: proc(a: ^Action) {
	a.enabled = true
}

// Disable stops event delivery but keeps callbacks and bindings. Input state
// for the Action stays up to date so re-enabling does not emit a stale press.
Disable :: proc(a: ^Action) {
	a.enabled = false
}

// Unbind clears all hardware bindings. Callbacks and live state (including
// the pressed flag) are reset, so no release is synthesized for a key that
// was physically still held.
Unbind :: proc(a: ^Action) {
	a.bindings = nil
	a.down = false
}

// IsDown reports whether the Action is currently pressed.
IsDownAction :: proc(a: ^Action) -> bool {
	return a.down
}

// IsActive reports the current toggle state.
IsActive :: proc(a: ^Action) -> bool {
	return a.active
}

// OnPressed registers a callback fired once on the press edge.
OnPressed :: proc(a: ^Action, fn: proc(Context)) {
	op := a.onPress
	append_slice_proc_ctx(&op, fn)
	a.onPress = op
}

// OnReleased registers a callback fired once on the release edge.
OnReleased :: proc(a: ^Action, fn: proc(Context)) {
	or := a.onRelease
	append_slice_proc_ctx(&or, fn)
	a.onRelease = or
}

// OnHold registers a callback fired every frame the Action has been held
// longer than its own threshold (seconds). Each handler is gated on its own
// threshold, so OnHold(0.1) and OnHold(1.0) fire independently. Because the
// callback fires every frame, scale accumulations by ctx.Dt() to stay
// frame-rate independent.
OnHold :: proc(a: ^Action, threshold: f64, fn: proc(Context)) {
	oh := a.onHold
	append_slice_holdHandler(&oh, holdHandler{threshold = threshold, fn = fn})
	a.onHold = oh
}

// OnTap registers a callback fired on a quick press+release, where "quick"
// means shorter than defaultTapMax (0.22s). The tap window is fixed and does
// not depend on any OnHold threshold.
OnTap :: proc(a: ^Action, fn: proc(Context)) {
	ot := a.onTap
	append_slice_proc_ctx(&ot, fn)
	a.onTap = ot
}

// OnToggle registers a callback fired on every press edge, carrying the new
// toggle state (true after an odd number of presses).
OnToggle :: proc(a: ^Action, fn: proc(bool, Context)) {
	otg := a.onToggle
	append_slice_proc_bool_ctx(&otg, fn)
	a.onToggle = otg
}

// OnDrag registers a callback fired whenever the pointer moves while the
// Action is held. dx, dy are the per-frame movement deltas.
OnDrag :: proc(a: ^Action, fn: proc(f64, f64, Context)) {
	od := a.onDrag
	append_slice_proc_f64_f64_ctx(&od, fn)
	a.onDrag = od
}

// process updates the Action's state from the live Manager state and
// dispatches any derived events. It is called once per frame per Action.
process :: proc(a: ^Action, m: ^Manager) {
	down := currentDown(a, m)

	if down != a.down {
		a.down = down
		if down {
			a.downTime = m.clock
			a.lastDragX, a.lastDragY = m.mouseX, m.mouseY
			// Toggle state advances regardless of enabled, so re-enabling
			// after a press while disabled yields a consistent logical state.
			a.active = !a.active
			if a.enabled {
				m.ctx.action = a
				record(m, .Pressed, false, 0, 0)
				logx.logger_trace(g_log, "action pressed", "action", a.name, "toggle", a.active, "press_cbs", len(a.onPress), "toggle_cbs", len(a.onToggle))
				for fn in a.onPress {
					fn(m.ctx)
				}
				record(m, .Toggle, a.active, 0, 0)
				for fn in a.onToggle {
					fn(a.active, m.ctx)
				}
			}
		} else {
			duration := m.clock - a.downTime
			if a.enabled {
				m.ctx.action = a
				record(m, .Released, false, 0, 0)
				logx.logger_trace(g_log, "action released", "action", a.name, "held_s", duration)
				for fn in a.onRelease {
					fn(m.ctx)
				}
				handleTap(a, duration, m)
			}
		}
	}

	if a.down && a.enabled {
		m.ctx.action = a
		for h in a.onHold {
			if m.clock-a.downTime >= h.threshold {
				record(m, .Hold, false, 0, 0)
				logx.logger_trace(g_log, "action hold", "action", a.name, "threshold_s", h.threshold, "held_s", m.clock-a.downTime)
				h.fn(m.ctx)
			}
		}
		if len(a.onDrag) > 0 {
			dx := m.mouseX - a.lastDragX
			dy := m.mouseY - a.lastDragY
			a.lastDragX, a.lastDragY = m.mouseX, m.mouseY
			if dx != 0 || dy != 0 {
				m.ctx.action = a
				record(m, .Drag, false, dx, dy)
				logx.logger_trace(g_log, "action drag", "action", a.name, "dx", dx, "dy", dy)
				for fn in a.onDrag {
					fn(dx, dy, m.ctx)
				}
			}
		}
	}
}

// handleTap fires the tap callback for a completed press whose duration
// qualifies as a tap.
handleTap :: proc(a: ^Action, duration: f64, m: ^Manager) {
	if duration > 0.22 {
		return
	}

	record(m, .Tap, false, 0, 0)
	for fn in a.onTap {
		fn(m.ctx)
	}
}
