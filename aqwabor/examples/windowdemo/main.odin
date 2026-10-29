package main

import "core:mem"
import "aqwabor:logx"
import "aqwabor:window"

main_arena: mem.Dynamic_Arena
main_allocator: mem.Allocator

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

	logx.info("windowdemo: window created")
	window.Run(win,
		proc() {},
		proc(dt: f64) {},
	)
	logx.info("windowdemo: done")
}
