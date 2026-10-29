package main

import "core:mem"
import "aqwabor:logx"
import "aqwabor:window"
import "aqwabor:image"
import "aqwabor:input"
import "aqwabor:ecs"
import "aqwabor:schedulers"

main_arena: mem.Dynamic_Arena
g_win: window.Window
g_texture: image.Texture
g_zoom: f32 = 1.0
g_manager: ^input.Manager
g_world: ^ecs.World
g_sprites: ecs.Comp(Sprite)
g_schedule: ^schedulers.Schedule
g_frame: u64 = 0

Sprite :: struct {
	x, y:  f32,
	scale: f32,
}

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
	if g_texture.handle == nil {
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

	g_world = ecs.new_world(mem.dynamic_arena_allocator(&main_arena))
	g_sprites = ecs.must_register(g_world, Sprite)
	e := ecs.create(g_world)
	ecs.set(g_sprites, e, Sprite{x = 0, y = 0, scale = 1.0})
	ecs.wake(g_sprites, e)

	g_schedule = schedulers.new_schedule(mem.dynamic_arena_allocator(&main_arena))
	schedulers.add(g_schedule, "animate", schedulers.reads(), proc(st: schedulers.Tick_State) {
		rows := ecs.rows(g_sprites)
		for i in 0 ..< len(rows) {
			rows[i].scale += 0.002
			if rows[i].scale > 1.6 {
				rows[i].scale = 0.6
			}
			g_zoom = rows[i].scale
		}
	})
	schedulers.build_schedule(g_schedule)

	logx.info("windowdemo: window created")

	window.Run(win,
		proc() {
			image.draw(g_win, g_texture, g_zoom)
		},
		proc(dt: f64) {
			g_frame += 1
			schedulers.run_schedule(g_schedule, schedulers.Tick_State{tick = g_frame, hz = 60})
			input.Update(g_manager, dt)
		},
	)
	logx.info("windowdemo: done")
}
