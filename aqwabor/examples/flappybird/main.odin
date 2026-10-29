package main

import "core:fmt"
import "core:mem"
import "aqwabor:logx"
import "aqwabor:window"
import "aqwabor:image"
import "aqwabor:input"
import "aqwabor:ecs"
import "aqwabor:schedulers"

main_arena: mem.Dynamic_Arena
g_win: window.Window
g_manager: ^input.Manager
g_world: ^ecs.World
g_sch: ^schedulers.Schedule
g_frame: u64 = 0
g_acc: f32 = 0

Position :: struct { x, y: f32 }
Velocity :: struct { vy: f32 }

g_pos: ecs.Comp(Position)
g_vel: ecs.Comp(Velocity)
g_bird: ecs.Entity

GameState :: enum u8 { Menu, Playing, GameOver }
g_state: GameState = .Menu
g_score: int = 0

Pipe :: struct { x, gap_top: f32, scored: bool }

g_pipes: [dynamic]Pipe
g_pipe_timer: f32 = 0

g_bird_y, g_bird_vy, g_bird_anim, g_ground_x: f32
g_bird_frame: int

g_bg, g_bu, g_bm, g_bd, g_pu, g_pd, g_ground: image.Texture
g_digits: [10]image.Texture

SCREEN_W  : f32 = 480
SCREEN_H  : f32 = 720
BIRD_X    : f32 = 100
GRAVITY   : f32 = 900
FLAP      : f32 = -330
MAX_VY    : f32 = 560
PIPE_SPEED: f32 = 150
PIPE_W    : f32 = 58
PIPE_GAP  : f32 = 150
PIPE_SPAWN: f32 = 1.35
GROUND_H  : f32 = 58
BIRD_W    : f32 = 40
BIRD_H    : f32 = 28
FIXED_DT  : f32 = 1 / 144.0

g_seed: u32 = 20261029
rand :: proc(min, max: f32) -> f32 {
	g_seed = g_seed * 1664525 + 1013904223
	return min + f32(g_seed) / 4294967296.0 * (max - min)
}

reset :: proc() {
	g_state = .Playing
	g_score = 0
	g_pipes = nil
	g_pipe_timer = 0
	g_bird_y = SCREEN_H / 2
	g_bird_vy = 0
	g_bird_anim = 0
	g_bird_frame = 0
	g_ground_x = 0
	ecs.set(g_pos, g_bird, Position{BIRD_X, g_bird_y})
	ecs.set(g_vel, g_bird, Velocity{0})
}

flap :: proc(_: input.Context) {
	switch g_state {
	case .Menu: reset()
	case .Playing: g_bird_vy = FLAP; g_bird_frame = 1; g_bird_anim = 0
	case .GameOver: reset()
	}
}

update :: proc(dt: f32) {
	if g_state != .Playing {
		ecs.set(g_pos, g_bird, Position{BIRD_X, g_bird_y})
		return
	}

	g_bird_vy += GRAVITY * dt
	if g_bird_vy > MAX_VY { g_bird_vy = MAX_VY }
	g_bird_y += g_bird_vy * dt

	g_bird_anim += dt
	if g_bird_anim >= 0.12 { g_bird_anim = 0; g_bird_frame = 1 - g_bird_frame }
	if g_bird_vy < -80 { g_bird_frame = 1 }

	g_pipe_timer += dt
	if g_pipe_timer >= PIPE_SPAWN {
		g_pipe_timer = 0
		gt := rand(f32(70), SCREEN_H - GROUND_H - PIPE_GAP - f32(70))
		append(&g_pipes, Pipe{x = SCREEN_W + 40, gap_top = gt, scored = false})
	}

	for i in 0 ..< len(g_pipes) { g_pipes[i].x -= PIPE_SPEED * dt }
	for i in 0 ..< len(g_pipes) {
		if !g_pipes[i].scored && g_pipes[i].x + PIPE_W / 2 < BIRD_X {
			g_pipes[i].scored = true
			g_score += 1
		}
	}
	for i := len(g_pipes) - 1; i >= 0; i -= 1 {
		if g_pipes[i].x + PIPE_W / 2 < 0 {
			last := len(g_pipes) - 1
			g_pipes[i] = g_pipes[last]
			pop(&g_pipes)
		}
	}

	if collide() { g_state = .GameOver }
	ecs.set(g_pos, g_bird, Position{BIRD_X, g_bird_y})
	ecs.set(g_vel, g_bird, Velocity{g_bird_vy})
}

collide :: proc() -> bool {
	if g_bird_y + 10 > SCREEN_H - GROUND_H { return true }
	b0, b1 := BIRD_X - 10, BIRD_X + 10
	for p in g_pipes {
		if b1 < p.x - PIPE_W / 2 + 6 || b0 > p.x + PIPE_W / 2 - 6 { continue }
		if g_bird_y - 10 < p.gap_top || g_bird_y + 10 > p.gap_top + PIPE_GAP { return true }
	}
	return false
}

draw_bg :: proc(sw, sh: int) {
	bh := f32(sh)
	bw := bh * f32(g_bg.w) / f32(g_bg.h)
	image.draw_rect(g_win, g_bg, bw / 2, f32(sh) / 2, bw, bh, .NONE)
}

draw_pipes :: proc(sh: int) {
	for p in g_pipes {
		gb := p.gap_top + PIPE_GAP
		image.draw_rect(g_win, g_pu, p.x, p.gap_top / 2, PIPE_W, p.gap_top, .VERTICAL)
		image.draw_rect(g_win, g_pd, p.x, gb + (f32(sh) - gb) / 2, PIPE_W, f32(sh) - gb, .VERTICAL)
	}
}

bird_tex :: proc() -> image.Texture {
	if g_state == .Playing && g_bird_vy < -80 { return g_bu }
	if g_bird_frame == 0 { return g_bm }
	return g_bd
}

draw_bird :: proc() {
	p, ok := ecs.get(g_pos, g_bird)
	if ok { image.draw_rect(g_win, bird_tex(), BIRD_X, p^.y, BIRD_W, BIRD_H, .NONE) }
}

draw_ground :: proc(sw, sh: int) {
	image.draw_rect(g_win, g_ground, g_ground_x + f32(sw) / 2, f32(sh) - GROUND_H / 2, f32(sw), GROUND_H, .NONE)
	image.draw_rect(g_win, g_ground, g_ground_x + f32(sw) / 2 + f32(sw), f32(sh) - GROUND_H / 2, f32(sw), GROUND_H, .NONE)
}

draw_score :: proc(sw: int) {
	s := fmt.aprintf("%d", g_score)
	tw := len(s) * 24
	x := f32(sw) / 2 - f32(tw) / 2
	for ch in s {
		image.draw_rect(g_win, g_digits[int(ch) - 48], x + 12, 50, 24, 36, .NONE)
		x += 24
	}
	delete(s, context.allocator)
}

on_draw :: proc() {
	sw, sh := window.Size(g_win)
	draw_bg(sw, sh)
	draw_pipes(sh)
	draw_bird()
	draw_ground(sw, sh)
	draw_score(sw)
}

backend_poll :: proc() -> [dynamic]input.Event {
	return window.PollInput(g_win)
}

main :: proc() {
	mem.dynamic_arena_init(&main_arena)
	defer mem.dynamic_arena_destroy(&main_arena)

	logx.init({level = .Info, color = true, has_time = true})

	win, err := window.NewWindow(window.WindowConfig{
		Title = "Flappy Bird - Aqwabor",
		W = 480,
		H = 720,
		Resizable = false,
	})
	if err != "" || win == nil { logx.errorf("window: %s", err); return }
	defer window.Close(win)
	g_win = win

	load :: proc(name: string) -> image.Texture {
		cands := [3]string{
			fmt.aprintf("resources/%s", name),
			fmt.aprintf("aqwabor/examples/flappybird/resources/%s", name),
			fmt.aprintf("/home/teracura/minasu/aqwabor/examples/flappybird/resources/%s", name),
		}
		for c in cands {
			t := image.load_texture(g_win, c)
			if t.handle != nil { return t }
			delete(c, context.allocator)
		}
		return {}
	}

	g_bg = load("background_day.png")
	g_bu = load("bird_up.png")
	g_bm = load("bird_mid.png")
	g_bd = load("bird_down.png")
	g_pu = load("pipe_up.png")
	g_pd = load("pipe_down.png")
	g_ground = load("ground.png")
	for i in 0 ..< 10 { g_digits[i] = load(fmt.aprintf("digit_%d.png", i)) }

	if g_bg.handle == nil || g_bu.handle == nil || g_bm.handle == nil || g_bd.handle == nil ||
		g_pu.handle == nil || g_pd.handle == nil || g_ground.handle == nil {
		logx.errorf("image: failed to load core assets")
		return
	}

	g_manager = input.NewManager(backend_poll)
	fl := input.ActionMgr(g_manager, "flap")
	input.BindKey(g_manager, fl, input.Key.Space)
	input.BindMouseButton(g_manager, fl, input.MouseButton.Left)
	input.OnPressed(fl, flap)

	g_world = ecs.new_world(mem.dynamic_arena_allocator(&main_arena))
	g_pos = ecs.must_register(g_world, Position)
	g_vel = ecs.must_register(g_world, Velocity)
	g_bird = ecs.create(g_world)
	ecs.set(g_pos, g_bird, Position{BIRD_X, SCREEN_H / 2})
	ecs.set(g_vel, g_bird, Velocity{0})
	ecs.wake(g_pos, g_bird)
	ecs.wake(g_vel, g_bird)

	g_sch = schedulers.new_schedule(mem.dynamic_arena_allocator(&main_arena))
	schedulers.add(g_sch, "game", schedulers.reads(), proc(st: schedulers.Tick_State) {
		update(FIXED_DT)
	})
	schedulers.build_schedule(g_sch)

	logx.info("flappybird: window created")

	window.Run(win,
		on_draw,
		proc(dt: f64) {
			g_frame += 1
			g_acc += f32(dt)
			for g_acc >= FIXED_DT {
				g_acc -= FIXED_DT
				schedulers.run_schedule(g_sch, schedulers.Tick_State{tick = g_frame, hz = 144})
			}
			input.Update(g_manager, dt)
		},
	)
	logx.info("flappybird: done")
}
