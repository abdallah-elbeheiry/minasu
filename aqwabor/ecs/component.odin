package ecs

import "base:runtime"
import "aqwabor:logx"

Error :: enum {
	None,
	Component_Has_Pointers,
	Component_Not_Concrete,
	System_Already_Registered,
}

error_string :: proc(e: Error) -> string {
	switch e {
	case .None: return ""
	case .Component_Has_Pointers:
		return "component type contains pointers (slices, maps, strings, interfaces, or pointers); components must be plain data"
	case .Component_Not_Concrete:
		return "component type must be a concrete struct or scalar, not an interface"
	case .System_Already_Registered:
		return "system is already registered"
	}
	return "unknown ecs error"
}

Component_ID :: distinct u32

// Comp is what register returns and the only way to reach a component value.
Comp :: struct($T: typeid) {
	id: Component_ID,
	s:  ^Store(T),
}

id :: proc(c: Comp($T)) -> Component_ID {
	return c.id
}

valid :: proc(c: Comp($T)) -> bool {
	return c.s != nil
}

get :: proc(c: Comp($T), e: Entity) -> (^T, bool) {
	if c.s == nil {
		return nil, false
	}
	return store_get(c.s, e)
}

has :: proc(c: Comp($T), e: Entity) -> bool {
	return c.s != nil && store_has(c.s, e)
}

set :: proc(c: Comp($T), e: Entity, v: T) -> bool {
	if c.s == nil || !alive(c.s.world, e) {
		return false
	}
	store_set(c.s, e, v)
	return true
}

remove :: proc(c: Comp($T), e: Entity) -> bool {
	if c.s == nil {
		return false
	}
	return store_remove(c.s, e)
}

wake :: proc(c: Comp($T), e: Entity) -> bool {
	if c.s == nil || !alive(c.s.world, e) {
		return false
	}
	return store_wake(c.s, e)
}

sleep :: proc(c: Comp($T), e: Entity) -> bool {
	if c.s == nil {
		return false
	}
	return store_sleep(c.s, e)
}

awake :: proc(c: Comp($T), e: Entity) -> bool {
	return c.s != nil && store_is_awake(c.s, e)
}

comp_len :: proc(c: Comp($T)) -> int {
	if c.s == nil {
		return 0
	}
	return len(c.s.dense)
}

awake_len :: proc(c: Comp($T)) -> int {
	if c.s == nil {
		return 0
	}
	return c.s.awake
}

@(private)
Component_Registry :: struct {
	by_type: map[typeid]Component_ID,
	types:   [dynamic]typeid,
}


register :: proc(w: ^World, $T: typeid, allocator: runtime.Allocator = {}) -> (Comp(T), Error) {
	alloc := allocator
	if alloc == (runtime.Allocator{}) {
		alloc = w.allocator
	}
	tid := typeid_of(T)
	info := type_info_of(T)
	if info == nil {
		return {}, .Component_Not_Concrete
	}
	if _, is_any := info.variant.(runtime.Type_Info_Any); is_any {
		return {}, .Component_Not_Concrete
	}

	if existing, ok := w.registry.by_type[tid]; ok {
		s := (^Store(T))(w.stores[existing].impl)
		return Comp(T){id = existing, s = s}, .None
	}

	id := Component_ID(len(w.stores))
	s := new(Store(T), alloc)
	store_init(s, w, id, alloc)
	w.registry.by_type[tid] = id
	append(&w.registry.types, tid)
	append(&w.stores, make_any_store(s))

	if w.log != nil {
		logx.logger_info(w.log, "component registered", "type", tid, "id", u32(id), "size", size_of(T))
	}
	return Comp(T){id = id, s = s}, .None
}

must_register :: proc(w: ^World, $T: typeid, allocator: runtime.Allocator = {}) -> Comp(T) {
	alloc := allocator
	if alloc == (runtime.Allocator{}) {
		alloc = w.allocator
	}
	c, err := register(w, T, alloc)
	if err != .None {
		panic(error_string(err))
	}
	return c
}

component_type :: proc(w: ^World, id: Component_ID) -> (typeid, bool) {
	if int(id) >= len(w.registry.types) {
		return nil, false
	}
	return w.registry.types[id], true
}
