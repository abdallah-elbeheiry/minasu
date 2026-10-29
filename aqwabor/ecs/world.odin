package ecs

import "base:runtime"
import "aqwabor:logx"

World :: struct {
	allocator: runtime.Allocator,
	log:      ^logx.Logger,
	entities: Entity_Allocator,
	registry: Component_Registry,
	stores:   [dynamic]Any_Store,
	cmd:      Command_Buffer,
	timers:   Timers,
	sets:     [dynamic]^Set,
	systems:  System_Manager,
}

new_world :: proc(allocator: runtime.Allocator) -> ^World {
	w := new(World, allocator)
	w.allocator = allocator
	w.log = logx.with(allocator)
	entity_allocator_init(&w.entities, allocator)
	w.registry.by_type = make(map[typeid]Component_ID, allocator)
	w.registry.types = make([dynamic]typeid, 0, 16, allocator)
	w.stores = make([dynamic]Any_Store, 0, 16, allocator)
	command_buffer_init(&w.cmd, allocator)
	timers_init(&w.timers, allocator)
	w.sets = make([dynamic]^Set, 0, 4, allocator)
	system_manager_init(&w.systems, allocator)
	if w.log != nil {
		logx.logger_info(w.log, "world created")
	}
	return w
}

destroy_world :: proc(w: ^World) {
	if w == nil {
		return
	}
	old_allocator := context.allocator
	context.allocator = w.allocator
	for s in w.stores {
		if s.destroy != nil {
			s.destroy(s.impl)
		}
	}
	delete(w.stores)
	delete(w.registry.by_type)
	delete(w.registry.types)
	entity_allocator_destroy(&w.entities)
	command_buffer_destroy(&w.cmd)
	timers_destroy(&w.timers)
	for set in w.sets {
		set_destroy(set)
	}
	delete(w.sets)
	system_manager_destroy(&w.systems)
	if w.log != nil {
		free(w.log)
	}
	free(w, w.allocator)
	context.allocator = old_allocator
}

create :: proc(w: ^World) -> Entity {
	e := entity_create(&w.entities)
	if w.log != nil && logx.logger_enabled(w.log, logx.Trace_Level) {
		logx.logger_trace(w.log, "entity created", "entity", u64(e))
	}
	return e
}

destroy :: proc(w: ^World, e: Entity) -> bool {
	if !entity_alive(&w.entities, e) {
		return false
	}
	for s in w.stores {
		s.remove_entity(s.impl, e)
	}
	for set in w.sets {
		set_remove(set, e)
	}
	timers_cancel(&w.timers, e)
	entity_destroy(&w.entities, e)
	if w.log != nil && logx.logger_enabled(w.log, logx.Trace_Level) {
		logx.logger_trace(w.log, "entity destroyed", "entity", u64(e))
	}
	return true
}

alive :: proc(w: ^World, e: Entity) -> bool {
	return entity_alive(&w.entities, e)
}

count :: proc(w: ^World) -> int {
	return entity_count(&w.entities)
}

component_count :: proc(w: ^World) -> int {
	return len(w.stores)
}

reset :: proc(w: ^World) {
	for s in w.stores {
		s.reset(s.impl)
	}
	for set in w.sets {
		set_clear(set)
	}
	entity_allocator_destroy(&w.entities)
	entity_allocator_init(&w.entities)
	command_buffer_clear(&w.cmd)
	timers_reset(&w.timers)
}

timers :: proc(w: ^World) -> ^Timers {
	return &w.timers
}

tick :: proc(w: ^World) -> u64 {
	return timers_now(&w.timers)
}

advance :: proc(w: ^World, fn: proc(e: Entity)) {
	timers_advance(&w.timers, fn)
}

flush :: proc(w: ^World) {
	command_buffer_apply(&w.cmd, w)
}

commands :: proc(w: ^World) -> ^Command_Buffer {
	return &w.cmd
}
