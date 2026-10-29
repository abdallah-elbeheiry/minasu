package window

import "core:c"
import "core:mem"
import "core:strings"
import "aqwabor:logx"
import "aqwabor:input"
import SDL "vendor:sdl3"

WindowConfig :: struct {
	Title:     string,
	W, H:      int,
	Resizable: bool,
	OnDemand:  bool,
}

window_data :: struct {
	window:          ^SDL.Window,
	gpu_device:      ^SDL.GPUDevice,
	cfg:             WindowConfig,
	last_scale:      f32,
	inputQueue:      [dynamic]input.Event,
	allocator:       mem.Allocator,
	log:             ^logx.Logger,
	current_cmd:     ^SDL.GPUCommandBuffer,
	current_swap:    ^SDL.GPUTexture,
	swap_w:          int,
	swap_h:          int,
}

Window :: ^window_data

// PollInput drains and returns the input events collected since the last call.
PollInput :: proc(w: Window) -> [dynamic]input.Event {
	q := w.inputQueue
	alloc := w.allocator
	if alloc == (mem.Allocator{}) {
		alloc = context.allocator
	}
	w.inputQueue = make([dynamic]input.Event, 0, 16, alloc)
	return q
}

g_log: ^logx.Logger
g_allocator: mem.Allocator

init :: proc(allocator := context.allocator) {
	g_allocator = allocator
	g_log = logx.with(allocator)
}

NewWindow :: proc(cfg: WindowConfig, allocator := context.allocator) -> (Window, string) {
	_cfg := cfg
	if _cfg.W <= 0 || _cfg.H <= 0 {
		logx.logger_warn(g_log, "invalid size, falling back to default", "w", _cfg.W, "h", _cfg.H)
		_cfg.W = 1280
		_cfg.H = 720
	}
	if _cfg.Title == "" {
		_cfg.Title = "AqwaborEngine"
	}
	if g_allocator == (mem.Allocator{}) {
		g_allocator = allocator
	}
	if g_log == nil {
		g_log = logx.with(g_allocator)
	}
	if SDL.Init(SDL.INIT_VIDEO) {
		title := strings.clone_to_cstring(_cfg.Title, allocator)
		defer delete(title, allocator)
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
		out := new(window_data, allocator)
		out.window = w
		out.cfg = _cfg
		out.last_scale = 0
		out.allocator = allocator
		out.log = g_log
		out.gpu_device = SDL.CreateGPUDevice({.SPIRV}, false, nil)
		if out.gpu_device == nil {
			SDL.DestroyWindow(w)
			return nil, "failed to create gpu device"
		}
		if !SDL.ClaimWindowForGPUDevice(out.gpu_device, w) {
			SDL.DestroyGPUDevice(out.gpu_device)
			SDL.DestroyWindow(w)
			return nil, "failed to claim window for gpu device"
		}
		out.inputQueue = make([dynamic]input.Event, 0, 16, allocator)
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

Run :: proc(w: Window, onDraw: proc(), onUpdate: proc(dt: f64), onKey: proc(key: string) = nil, onKeyUp: proc(key: string) = nil) -> string {
	if w.window == nil || w.gpu_device == nil {
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
			if event.type == SDL.EventType.KEY_DOWN {
				name := SDL.GetKeyName(event.key.key)
				if name != nil && onKey != nil {
					onKey(string(name))
				}
				append(&w.inputQueue, input.Event{Kind = .KeyDown, Key = sdl_key_to_input(event.key.key)})
			}
			if event.type == SDL.EventType.KEY_UP {
				name := SDL.GetKeyName(event.key.key)
				if name != nil && onKeyUp != nil {
					onKeyUp(string(name))
				}
				append(&w.inputQueue, input.Event{Kind = .KeyUp, Key = sdl_key_to_input(event.key.key)})
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
		cmd := SDL.AcquireGPUCommandBuffer(w.gpu_device)
		w.current_cmd = cmd
		w.current_swap = nil
		sw: ^SDL.GPUTexture
		sw_w, sw_h: SDL.Uint32
		if SDL.AcquireGPUSwapchainTexture(cmd, w.window, &sw, &sw_w, &sw_h) {
			w.current_swap = sw
			w.swap_w = int(sw_w)
			w.swap_h = int(sw_h)
			if sw != nil {
				color_info := SDL.GPUColorTargetInfo{
					texture = sw,
					load_op = SDL.GPULoadOp.CLEAR,
					store_op = SDL.GPUStoreOp.STORE,
					clear_color = SDL.FColor{0.1, 0.1, 0.15, 1.0},
				}
				pass := SDL.BeginGPURenderPass(cmd, &color_info, 1, nil)
				SDL.EndGPURenderPass(pass)
			}
		}
		if onDraw != nil {
			onDraw()
		}
		_ = SDL.SubmitGPUCommandBuffer(cmd)
		w.current_cmd = nil
		w.current_swap = nil
	}
	SDL.ReleaseWindowFromGPUDevice(w.gpu_device, w.window)
	SDL.DestroyGPUDevice(w.gpu_device)
	w.gpu_device = nil
	SDL.Quit()
	return ""
}

watch_scale :: proc(w: Window, scale: f32) {
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

GPUDevice :: proc(w: Window) -> ^SDL.GPUDevice {
	if w == nil { return nil }
	return w.gpu_device
}

CurrentCommandBuffer :: proc(w: Window) -> ^SDL.GPUCommandBuffer {
	if w == nil { return nil }
	return w.current_cmd
}

CurrentSwapchainTexture :: proc(w: Window) -> ^SDL.GPUTexture {
	if w == nil { return nil }
	return w.current_swap
}

SwapchainSize :: proc(w: Window) -> (int, int) {
	if w == nil { return 0, 0 }
	return w.swap_w, w.swap_h
}

Close :: proc(w: Window) {
	if w == nil {
		return
	}
	if w.window != nil {
		if w.gpu_device != nil {
			SDL.ReleaseWindowFromGPUDevice(w.gpu_device, w.window)
		}
		logx.logger_debug(g_log, "window closed")
		SDL.DestroyWindow(w.window)
		w.window = nil
	}
	if w.gpu_device != nil {
		SDL.DestroyGPUDevice(w.gpu_device)
		w.gpu_device = nil
	}
	alloc := w.allocator
	free(w, alloc)
}
