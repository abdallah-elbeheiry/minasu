package main

import "core:mem"
import "aqwabor:logx"
import "aqwabor:window"
import "aqwabor:image"
import "aqwabor:input"

main_arena: mem.Dynamic_Arena
g_win: window.Window
g_texture: image.Texture
g_zoom: f32 = 1.0
g_manager: ^input.Manager

backend_poll :: proc() -> [dynamic]input.Event {
	return window.PollInput(g_win)
}

main :: proc() {
	mem.dynamic_arena_init(&main_arena)
	defer mem.dynamic_arena_destroy(&main_arena)

	logx.init({level = .Info, color = true, has_time = true})
	logx.info("windowdemo: starting")

	win, err := window.NewWindow(window.WindowConfig{
		Title     = "Aqwabor Window Demo",
		W         = 800,
		H         = 600,
		Resizable = true,
	})
	if err != "" || win == nil {
		logx.errorf("window: %s", err)
		return
	}
	defer window.Close(win)
	g_win = win

	g_texture = image.load_texture(win, "resources/new pfp.png")
	if g_texture == nil {
		logx.errorf("image: failed to load")
		return
	}
	defer image.destroy(g_texture)

	g_manager = input.NewManager(backend_poll)
	input.SetRecording(g_manager, true)

	zoom_in := input.ActionMgr(g_manager, "zoom_in")
	zoom_out := input.ActionMgr(g_manager, "zoom_out")
	input.BindKey(g_manager, zoom_in, input.Key.Equal)
	input.BindKey(g_manager, zoom_out, input.Key.Minus)

	input.OnPressed(zoom_in, proc(ctx: input.Context) {
		g_zoom *= 1.1
	})
	input.OnPressed(zoom_out, proc(ctx: input.Context) {
		g_zoom /= 1.1
		if g_zoom < 0.1 {
			g_zoom = 0.1
		}
	})

	logx.info("windowdemo: window created")

	window.Run(win,
		proc() {
			image.draw(g_win, g_texture, g_zoom)
		},
		proc(dt: f64) {
			input.Update(g_manager, dt)
		},
	)
	logx.info("windowdemo: done")
}
