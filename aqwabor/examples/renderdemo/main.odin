package main

import "core:mem"
import "aqwabor:ecs"
import "aqwabor:logx"
import "aqwabor:camera"
import "aqwabor:render"
import "aqwabor:window"

main_arena: mem.Dynamic_Arena
main_allocator: mem.Allocator

// Components for the scene
Transform :: struct { x, y: f32, rot: f32, sx, sy: f32 }
Color :: struct { r, g, b, a: f32 }
Sprite :: struct { layer: f32, uvx: f32, uvy: f32, flags: u32 }

SceneComponents :: struct {
	transform: ecs.Comp(Transform),
	color:     ecs.Comp(Color),
	sprite:    ecs.Comp(Sprite),
	camera:    ecs.Comp(camera.Camera),
}

register_scene_components :: proc(w: ^ecs.World) -> SceneComponents {
	c: SceneComponents
	err: ecs.Error

	c.transform, err = ecs.register(w, Transform)
	if err != .None { panic(ecs.error_string(err)) }
	c.color, err = ecs.register(w, Color)
	if err != .None { panic(ecs.error_string(err)) }
	c.sprite, err = ecs.register(w, Sprite)
	if err != .None { panic(ecs.error_string(err)) }
	c.camera, err = camera.register_ecs(w)
	if err != .None { panic(ecs.error_string(err)) }
	return c
}

main :: proc() {
	mem.dynamic_arena_init(&main_arena)
	main_allocator = mem.dynamic_arena_allocator(&main_arena)
	defer mem.dynamic_arena_destroy(&main_arena)

	logx.init({level = .Debug, color = true, has_time = true})
	logx.info("renderdemo: starting")

	// Create window
	win_cfg := window.WindowConfig{
		Title     = "Aqwabor Render Demo",
		W         = 1280,
		H         = 720,
		Resizable = true,
	}
	win, err := window.NewWindow(win_cfg)
	if err != "" || win == nil {
		logx.errorf("window: %s", err)
		return
	}
	defer window.Close(win)
	logx.info("renderdemo: window created", "w", win_cfg.W, "h", win_cfg.H)

	// Create ECS world and scene
	w := ecs.new_world(main_allocator)
	comps := register_scene_components(w)

	// Create a camera entity
	cam_e := ecs.create(w)
	cam := camera.Camera{zoom = 1.0, x = 640, y = 360}
	ecs.set(comps.camera, cam_e, cam)
	ecs.wake(comps.camera, cam_e)

	// Create some sprite entities
	for i in 0 ..< 10 {
		e := ecs.create(w)
		t := Transform{x = f32(i * 120 + 40), y = 360, sx = 1.0, sy = 1.0}
		c := Color{r = 0.2 + f32(i) * 0.08, g = 0.4, b = 0.8 - f32(i) * 0.05, a = 1.0}
		s := Sprite{layer = 0, uvx = 0, uvy = 0, flags = 0}
		ecs.set(comps.transform, e, t)
		ecs.set(comps.color, e, c)
		ecs.set(comps.sprite, e, s)
		ecs.wake(comps.transform, e)
	}
	logx.info("renderdemo: created scene with 10 sprites + camera")

	// Test Scene creation (will need GPU, so just test the API)
	// gfx, gpu_err := render.new_gpu(...) - requires Vulkan
	// For now we just test the scene construction logic
	logx.info("renderdemo: scene components registered, GPU creation skipped (needs Vulkan)")

	// Run the window loop
	window.Run(win, 
		// onDraw
		proc() {
			// Here we would call render.draw_scene(gfx, scene, camera)
			// For headless demo, just log once
		},
		// onUpdate
		proc(dt: f64) {
			// Here we would update scene, handle input, etc.
		}
	)

	logx.info("renderdemo: done")
}