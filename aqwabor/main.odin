package main

import "core:mem"
import "aqwabor:ecs"
import "aqwabor:logx"
import "aqwabor:schedulers"
import "aqwabor:triangulate"

main_arena: mem.Dynamic_Arena
main_allocator: mem.Allocator

main :: proc() {
	mem.dynamic_arena_init(&main_arena)
	main_allocator = mem.dynamic_arena_allocator(&main_arena)
	defer mem.dynamic_arena_destroy(&main_arena)

	logx.init({level = .Debug, color = true, has_time = true})
	logx.info("aqwabor smoke test start")

	// ECS
	w := ecs.new_world(main_allocator)
	Pos :: struct { x, y: f32 }
	pos := ecs.must_register(w, Pos)
	e := ecs.create(w)
	ecs.set(pos, e, Pos{x = 1, y = 2})
	ecs.wake(pos, e)
	for i in 0 ..< len(ecs.rows(pos)) {
		p := &ecs.rows(pos)[i]
		p.x += 1
	}
	if v, ok := ecs.get(pos, e); ok {
		logx.info("ecs", "pos", v.x, v.y)
	}

	// Schedulers
	s := schedulers.new_scheduler(main_allocator)
	schedulers.set_master_hz(s, 60)
	schedulers.run(s, proc(st: schedulers.Tick_State) {}, 30)
	schedulers.advance_ticks(s, 60)
	logx.info("scheduler", "sim_ticks", schedulers.sim_ticks(s))

	// Triangulate
	ring := []i32{0,0, 10,0, 10,10, 0,10}
	tris := triangulate.ring(ring, 1.0)
	logx.info("triangulate", "indices", len(tris))

	logx.info("aqwabor smoke test done")
}
