package window

import "core:c"
import "core:mem"
import "core:sync"
import "aqwabor:logx"
import SDL "vendor:sdl3"

WindowConfig :: struct {
	Title:     string,
	W, H:      int,
	Resizable: bool,
	OnDemand:  bool,
}

window_data :: struct {
	window:    ^SDL.Window,
	renderer:  ^SDL.Renderer,
	cfg:       WindowConfig,
	mu:        sync.Mutex,
	last_scale: f32,
}

Window :: ^window_data

g_log: ^logx.Logger
g_allocator: mem.Allocator
g_arena: mem.Dynamic_Arena

init :: proc() {
	mem.dynamic_arena_init(&g_arena)
	g_allocator = mem.dynamic_arena_allocator(&g_arena)
	g_log = logx.with(g_allocator)
}

NewWindow :: proc(cfg: WindowConfig) -> (Window, string) {
	_cfg := cfg
	if _cfg.W <= 0 || _cfg.H <= 0 {
		logx.logger_warn(g_log, "invalid size, falling back to default", "w", _cfg.W, "h", _cfg.H)
		_cfg.W = 1280
		_cfg.H = 720
	}
	if _cfg.Title == "" {
		_cfg.Title = "AqwaborEngine"
	}
	if SDL.Init(SDL.INIT_VIDEO) {
		title := cstring_from_string(_cfg.Title)
		w := SDL.CreateWindow(title, c.int(_cfg.W), c.int(_cfg.H), SDL.WindowFlags{})
		if w == nil {
			return nil, "failed to create window"
		}
		if _cfg.Resizable {
			SDL.SetWindowResizable(w, true)
		}
		SDL.SetWindowPosition(w, 100, 100)
		SDL.ShowWindow(w)
		SDL.RaiseWindow(w)
		SDL.RestoreWindow(w)
		SDL.SyncWindow(w)
		logx.logger_info(g_log, "window created", "title", _cfg.Title, "w", _cfg.W, "h", _cfg.H, "resizable", _cfg.Resizable, "onDemand", _cfg.OnDemand)
		out := new(window_data)
		out.window = w
		out.cfg = _cfg
		out.last_scale = 0
		out.renderer = SDL.CreateRenderer(w, nil)
		return out, ""
	}
	return nil, "failed to init SDL video"
}

Size :: proc(w: Window) -> (width: int, height: int) {
	if w.window == nil {
		return w.cfg.W, w.cfg.H
	}
	ww := c.int(0)
	hh := c.int(0)
	SDL.GetWindowSize(w.window, &ww, &hh)
	return int(ww), int(hh)
}

ScaleFactor :: proc(w: Window) -> f32 {
	if w.window == nil {
		return 1
	}
	return SDL.GetWindowDisplayScale(w.window)
}

OnResize :: proc(w: Window, fn: proc(width, height: int)) {
	_ = w
	_ = fn
}

Run :: proc(w: Window, onDraw: proc(), onUpdate: proc(dt: f64)) -> string {
	if w.window == nil {
		return ""
	}
	running := true
	last_ticks := SDL.Uint64(SDL.GetPerformanceCounter())
	freq := SDL.Uint64(SDL.GetPerformanceFrequency())
	for running {
		event := SDL.Event{}
		for SDL.PollEvent(&event) {
			if event.type == SDL.EventType.QUIT {
				running = false
			}
			if event.type == SDL.EventType.WINDOW_RESIZED {
				logx.logger_debug(g_log, "window resized", "w", event.window.data1, "h", event.window.data2)
			}
			if event.type == SDL.EventType.WINDOW_DISPLAY_SCALE_CHANGED {
				scale := SDL.GetWindowDisplayScale(w.window)
				watch_scale(w, scale)
			}
		}
		now := SDL.GetPerformanceCounter()
		dt := f64(now - last_ticks) / f64(freq)
		last_ticks = now
		if onUpdate != nil {
			onUpdate(dt)
		}
		if w.renderer != nil {
			SDL.SetRenderDrawColor(w.renderer, 20, 24, 36, 255)
			SDL.RenderClear(w.renderer)
		}
		if onDraw != nil {
			onDraw()
		}
		if w.renderer != nil {
			SDL.RenderPresent(w.renderer)
		}
	}
	SDL.Quit()
	return ""
}

watch_scale :: proc(w: Window, scale: f32) {
	sync.mutex_lock(&w.mu)
	defer sync.mutex_unlock(&w.mu)
	if w.last_scale == 0 {
		w.last_scale = scale
		return
	}
	if w.last_scale == scale {
		return
	}
	logx.logger_debug(g_log, "backing scale changed", "from", w.last_scale, "to", scale)
	w.last_scale = scale
}

RequestRedraw :: proc(w: Window) {
	_ = w
}

cstring_from_string :: proc(s: string) -> cstring {
	if len(s) == 0 {
		return nil
	}
	buf := make([]u8, len(s) + 1)
	for i in 0 ..< len(s) {
		buf[i] = s[i]
	}
	buf[len(s)] = 0
	return cast(cstring) &buf[0]
}

Renderer :: proc(w: Window) -> rawptr {
	if w == nil {
		return nil
	}
	return rawptr(w.renderer)
}

Close :: proc(w: Window) {
	if w == nil || w.window == nil {
		if w != nil && w.renderer != nil {
			SDL.DestroyRenderer(w.renderer)
			w.renderer = nil
		}
		return
	}
	if w.renderer != nil {
		SDL.DestroyRenderer(w.renderer)
		w.renderer = nil
	}
	logx.logger_debug(g_log, "window closed")
	SDL.DestroyWindow(w.window)
	w.window = nil
}
