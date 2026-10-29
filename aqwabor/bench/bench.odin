package main

import "core:fmt"
import "core:mem"
import "core:time"
import "aqwabor:ecs"
import "aqwabor:schedulers"

main :: proc() {
	// ECS benchmark
	{
		ta: mem.Tracking_Allocator
		mem.tracking_allocator_init(&ta, context.allocator)
		defer mem.tracking_allocator_destroy(&ta)
		alloc := mem.tracking_allocator(&ta)

		w := ecs.new_world(alloc)
		Pos :: struct { x, y: f64 }
		pos := ecs.must_register(w, Pos)

		n :: 10_000
		start := time.now()
		for i in 0 ..< n {
			e := ecs.create(w)
			ecs.set(pos, e, Pos{x = f64(i), y = f64(i)})
			ecs.wake(pos, e)
		}
		create_dur := time.since(start)

		rows := ecs.rows(pos)
		start = time.now()
		for i in 0 ..< len(rows) {
			p := &rows[i]
			p.x += 1
			p.y *= 2
		}
		iter_dur := time.since(start)

		start = time.now()
		ecs.reset(w)
		reset_dur := time.since(start)

		ecs.destroy_world(w)
		fmt.printf("ECS create+wake %d: %v\n", n, create_dur)
		fmt.printf("ECS iterate %d: %v\n", n, iter_dur)
		fmt.printf("ECS reset: %v\n", reset_dur)
		fmt.printf("ECS memory: allocated=%d freed=%d peak=%d allocs=%d leaks=%d\n",
			ta.total_memory_allocated, ta.total_memory_freed, ta.peak_memory_allocated, ta.total_allocation_count, len(ta.allocation_map))
	}

	// Scheduler benchmark
	{
		ta: mem.Tracking_Allocator
		mem.tracking_allocator_init(&ta, context.allocator)
		defer mem.tracking_allocator_destroy(&ta)
		alloc := mem.tracking_allocator(&ta)

		s := schedulers.new_schedule(alloc)
		for i in 0 ..< 8 {
			schedulers.add(s, "sys", schedulers.reads(), proc(st: schedulers.Tick_State) {})
		}
		schedulers.build_schedule(s)

		start := time.now()
		schedulers.run_schedule(s, schedulers.Tick_State{tick = 1, hz = 60})
		run_dur := time.since(start)

		start = time.now()
		for _ in 0 ..< 100 {
			schedulers.run_schedule(s, schedulers.Tick_State{tick = 1, hz = 60})
		}
		run100_dur := time.since(start)

		schedulers.destroy_schedule(s)
		fmt.printf("Scheduler run 8 systems: %v\n", run_dur)
		fmt.printf("Scheduler run x100: %v\n", run100_dur)
		fmt.printf("Scheduler memory: allocated=%d freed=%d peak=%d allocs=%d leaks=%d\n",
			ta.total_memory_allocated, ta.total_memory_freed, ta.peak_memory_allocated, ta.total_allocation_count, len(ta.allocation_map))
	}
}
