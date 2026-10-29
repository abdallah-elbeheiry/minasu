package main

import "core:mem"
import "aqwabor:logx"
import "aqwabor:window"
import "aqwabor:image"
import SDL "vendor:sdl3"

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

	renderer := window.Renderer(win)
	if renderer == nil {
		logx.errorf("renderer: failed")
		return
	}

	texture := image.load_texture(renderer, "resources/new pfp.png")
	if texture == nil {
		logx.errorf("image: failed to load")
		return
	}
	defer SDL.DestroyTexture(texture)

	logx.info("windowdemo: window created")

	running := true
	for running {
		event := SDL.Event{}
		for SDL.PollEvent(&event) {
			if event.type == SDL.EventType.QUIT {
				running = false
			}
		}
		SDL.SetRenderDrawColor(renderer, 20, 24, 36, 255)
		SDL.RenderClear(renderer)
		SDL.RenderTexture(renderer, texture, nil, nil)
		SDL.RenderPresent(renderer)
	}
	logx.info("windowdemo: done")
}
