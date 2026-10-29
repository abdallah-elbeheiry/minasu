package ecs

import "core:math/rand"
import "core:mem"
import "core:testing"
import "aqwabor:logx"

Position :: struct { x, y: f64 }
Velocity :: struct { x, y: f64 }
Heat :: struct { kelvin: i32 }
Tag :: struct {}

@(private)
test_world :: proc() -> (^World, ^mem.Dynamic_Arena) {
	logx.discard()
	arena := new(mem.Dynamic_Arena, context.allocator)
	mem.dynamic_arena_init(arena)
	allocator := mem.dynamic_arena_allocator(arena)
	w := new_world(allocator)
	return w, arena
}

@(test)
test_entity_lifetime :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)

	e := create(w)
	testing.expect(t, alive(w, e), "new entity is not alive")
	testing.expect_value(t, count(w), 1)
	testing.expect(t, destroy(w, e), "destroy reported nothing to do")
	testing.expect(t, !alive(w, e), "destroyed entity is still alive")
	testing.expect_value(t, count(w), 0)
	testing.expect(t, !destroy(w, e), "destroying twice reported success")
}

@(test)
test_stale_handle_reaches_nothing :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	pos := must_register(w, Position)

	first := create(w)
	set(pos, first, Position{x = 1})
	destroy(w, first)

	second := create(w)
	set(pos, second, Position{x = 2})

	testing.expect_value(t, index(first), index(second))
	testing.expect(t, first != second, "generation did not move")
	testing.expect(t, !alive(w, first))
	testing.expect(t, !has(pos, first))
	_, ok := get(pos, first)
	testing.expect(t, !ok)
	testing.expect(t, !set(pos, first, Position{x = 99}))
	testing.expect(t, !remove(pos, first))
	testing.expect(t, !wake(pos, first))
	testing.expect(t, !destroy(w, first))
	testing.expect(t, alive(w, second))
	v, ok2 := get(pos, second)
	testing.expect(t, ok2 && v.x == 2)
}

@(test)
test_zero_size_component :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	tag := must_register(w, Tag)
	e := create(w)
	testing.expect(t, set(tag, e, Tag{}))
	testing.expect(t, has(tag, e))
	wake(tag, e)
	each(tag, proc(e: Entity, v: ^Tag) {})
	testing.expect_value(t, awake_len(tag), 1)
	testing.expect(t, remove(tag, e))
}

@(test)
test_set_overwrites :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	pos := must_register(w, Position)
	e := create(w)
	set(pos, e, Position{x = 1})
	set(pos, e, Position{x = 2})
	v, _ := get(pos, e)
	testing.expect_value(t, v.x, 2.0)
	testing.expect_value(t, comp_len(pos), 1)
}

@(test)
test_pointer_components_rejected :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)

	With_Slice :: struct { parts: []int }
	With_String :: struct { name: string }
	With_Pointer :: struct { next: ^Position }
	With_Map :: struct { m: map[int]int }
	Nested :: struct { inner: With_Slice }
	With_Array_Of_Bad :: struct { arr: [4]With_String }

	_, e1 := register(w, With_Slice)
	testing.expect_value(t, e1, Error.Component_Has_Pointers)
	_, e2 := register(w, With_String)
	testing.expect_value(t, e2, Error.Component_Has_Pointers)
	_, e3 := register(w, With_Pointer)
	testing.expect_value(t, e3, Error.Component_Has_Pointers)
	_, e4 := register(w, With_Map)
	testing.expect_value(t, e4, Error.Component_Has_Pointers)
	_, e5 := register(w, Nested)
	testing.expect_value(t, e5, Error.Component_Has_Pointers)
	_, e6 := register(w, With_Array_Of_Bad)
	testing.expect_value(t, e6, Error.Component_Has_Pointers)
}

@(test)
test_register_is_idempotent :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	c1, _ := register(w, Position)
	c2, _ := register(w, Position)
	testing.expect(t, c1.id == c2.id && c1.s == c2.s)
}

@(test)
test_destroy_clears_every_store :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	pos := must_register(w, Position)
	vel := must_register(w, Velocity)
	e := create(w)
	set(pos, e, Position{x = 1, y = 2})
	set(vel, e, Velocity{x = 3, y = 4})
	wake(pos, e)
	wake(vel, e)
	destroy(w, e)
	testing.expect_value(t, comp_len(pos), 0)
	testing.expect_value(t, comp_len(vel), 0)
	testing.expect_value(t, count(w), 0)
}

@(test)
test_awake_partition_holds :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	pos := must_register(w, Position)

	for i in 0 ..< 10000 {
		e := create(w)
		set(pos, e, Position{x = f64(i), y = f64(i * 2)})
		wake(pos, e)
	}
	testing.expect_value(t, awake_len(pos), 10000)

	for i in 0 ..< 5000 {
		e := create(w)
		set(pos, e, Position{x = f64(i), y = f64(i * 2)})
	}
	for i in 5000 ..< 10000 {
		destroy(w, Entity(u64(i)))
	}
	testing.expect_value(t, awake_len(pos), 5000)
}

@(test)
test_each_n :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	pos := must_register(w, Position)
	vel := must_register(w, Velocity)
	heat := must_register(w, Heat)

	both, all3 := 0, 0
	for i in 0 ..< 100 {
		e := create(w)
		set(pos, e, Position{x = 1})
		wake(pos, e)
		if i % 2 == 0 {
			set(vel, e, Velocity{x = 2})
			both += 1
		}
		if i % 4 == 0 {
			set(heat, e, Heat{kelvin = 300})
			all3 += 1
		}
	}

	each2(pos, vel, proc(_e: Entity, p: ^Position, v: ^Velocity) {
		p.x += v.x
	})
	n := 0
	prows := rows(pos)
	powners := owners(pos)
	for i in 0 ..< len(prows) {
		e := powners[i]
		if has(vel, e) {
			n += 1
		}
	}
	testing.expect_value(t, n, both)

	n = 0
	for i in 0 ..< len(prows) {
		e := powners[i]
		if has(vel, e) && has(heat, e) {
			n += 1
		}
	}
	testing.expect_value(t, n, all3)
}

@(test)
test_command_buffer_defers_change :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	pos := must_register(w, Position)
	for i in 0 ..< 10 {
		e := create(w)
		set(pos, e, Position{x = f64(i)})
		wake(pos, e)
	}
	cmd := commands(w)
	prows := rows(pos)
	powners := owners(pos)
	for i in 0 ..< len(prows) {
		if prows[i].x < 5 {
			cmd_destroy(cmd, powners[i])
		}
	}
	cmd_do(cmd, proc(w: ^World) {
		p := must_register(w, Position)
		e := create(w)
		set(p, e, Position{x = 100})
		wake(p, e)
	})
	testing.expect_value(t, count(w), 10)
	flush(w)
	testing.expect_value(t, count(w), 6)
	testing.expect_value(t, cmd_len(cmd), 0)
}

@(test)
test_reset_keeps_handles :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	pos := must_register(w, Position)
	for _ in 0 ..< 100 {
		e := create(w)
		set(pos, e, Position{})
		wake(pos, e)
	}
	reset(w)
	testing.expect_value(t, count(w), 0)
	testing.expect_value(t, comp_len(pos), 0)
}

Test_System :: struct {
	name: string,
}

@(test)
test_system_registry :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	s := new(Test_System)
	defer free(s)
	s.name = "power"
	testing.expect_value(t, register_system(w, s), Error.None)
	other := new(Test_System)
	defer free(other)
	other.name = "other"
	testing.expect_value(t, register_system(w, other), Error.System_Already_Registered)
	got, ok := get_system(w, Test_System)
	testing.expect(t, ok && got.name == "power")
}

@(test)
test_set_membership :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	set := new_set(w)
	a, b := create(w), create(w)
	testing.expect(t, set_add(set, a))
	testing.expect(t, !set_add(set, a))
	set_add(set, b)
	testing.expect_value(t, set_len(set), 2)
	testing.expect(t, set_remove(set, a) && !set_remove(set, a))
	testing.expect(t, !set_has(set, a) && set_len(set) == 1)
}

@(test)
test_destroy_leaves_every_set :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	one, two := new_set(w), new_set(w)
	e := create(w)
	set_add(one, e)
	set_add(two, e)
	destroy(w, e)
	testing.expect_value(t, set_len(one), 0)
	testing.expect_value(t, set_len(two), 0)
}

@(test)
test_timer_fires_on_its_tick :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	tm := timers(w)
	e := create(w)
	timers_after(tm, e, 5)
	for i in 1 ..= 4 {
		timers_advance(tm, proc(_: Entity) {})
		testing.expect_value(t, timers_pending(tm), 1)
		_ = i
	}
	timers_advance(tm, proc(_: Entity) {})
	testing.expect_value(t, timers_pending(tm), 0)
	_, ok := timers_scheduled(tm, e)
	testing.expect(t, !ok)
}

@(test)
test_timer_beyond_horizon :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	tm := timers(w)
	e := create(w)
	far := u64(HORIZON_SIZE * 3)
	timers_after(tm, e, far)
	got, ok := timers_scheduled(tm, e)
	testing.expect(t, ok && got == far)
	for _ in 0 ..< int(far) {
		timers_advance(tm, proc(_: Entity) {})
	}
	testing.expect_value(t, timers_now(tm), far)
	_, ok2 := timers_scheduled(tm, e)
	testing.expect(t, !ok2)
}

@(test)
test_timer_cancel :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	tm := timers(w)
	a, b, c := create(w), create(w), create(w)
	timers_after(tm, a, 3)
	timers_after(tm, b, 3)
	timers_after(tm, c, 3)
	testing.expect(t, timers_cancel(tm, b))
	testing.expect(t, !timers_cancel(tm, b))
	testing.expect_value(t, timers_pending(tm), 2)
	for _ in 0 ..< 3 {
		timers_advance(tm, proc(_: Entity) {})
	}
	testing.expect_value(t, timers_pending(tm), 0)
}

@(test)
test_timer_reschedule_replaces :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	tm := timers(w)
	e := create(w)
	timers_after(tm, e, 5)
	timers_after(tm, e, 9)
	testing.expect_value(t, timers_pending(tm), 1)
	for _ in 0 ..< 12 {
		timers_advance(tm, proc(_: Entity) {})
	}
	testing.expect_value(t, timers_now(tm), 12)
	_, ok := timers_scheduled(tm, e)
	testing.expect(t, !ok)
}

@(test)
test_timer_in_the_past_fires_next :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	tm := timers(w)
	for _ in 0 ..< 10 {
		timers_advance(tm, proc(_: Entity) {})
	}
	e := create(w)
	timers_at(tm, e, 3)
	timers_advance(tm, proc(_: Entity) {})
	_, ok := timers_scheduled(tm, e)
	testing.expect(t, !ok)
}

@(test)
test_destroy_cancels_timer :: proc(t: ^testing.T) {
	w, arena := test_world()
	defer destroy_world(w)
	defer free(arena, context.allocator)
	defer mem.dynamic_arena_destroy(arena)
	tm := timers(w)
	e := create(w)
	timers_after(tm, e, 3)
	destroy(w, e)
	testing.expect_value(t, timers_pending(tm), 0)
}
