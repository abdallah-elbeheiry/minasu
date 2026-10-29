package main

import "core:mem"
import "aqwabor:logx"
import "aqwabor:window"
import "aqwabor:image"

main_arena: mem.Dynamic_Arena
main_allocator: mem.Allocator

g_win: window.Window
g_texture: image.Texture

main :: proc() {
	mem.dynamic_arena_init(&main_arena)
	main_allocator = mem.dynamic_arena_allocator(&main_arena)
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

	logx.info("windowdemo: window created")

	window.Run(win,
		proc() {
			image.draw(g_win, g_texture)
		},
		proc(dt: f64) {},
	)
	logx.info("windowdemo: done")
}
