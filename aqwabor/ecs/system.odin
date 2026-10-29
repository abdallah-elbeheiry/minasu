package ecs

import "aqwabor:logx"

@(private)
System_Entry :: struct {
	ptr: rawptr,
	tid: typeid,
}

@(private)
System_Manager :: struct {
	systems: [dynamic]System_Entry,
	by_type: map[typeid]int,
}

@(private)
system_manager_init :: proc(m: ^System_Manager, allocator := context.allocator) {
	m.systems = make([dynamic]System_Entry, 0, 8, allocator)
	m.by_type = make(map[typeid]int, allocator)
}

@(private)
system_manager_destroy :: proc(m: ^System_Manager) {
	delete(m.systems)
	delete(m.by_type)
}

register_system :: proc(w: ^World, sys: ^$T) -> Error {
	tid := typeid_of(T)
	if _, exists := w.systems.by_type[tid]; exists {
		return .System_Already_Registered
	}
	w.systems.by_type[tid] = len(w.systems.systems)
	append(&w.systems.systems, System_Entry{ptr = sys, tid = tid})
	if w.log != nil {
		logx.logger_info(w.log, "system registered", "type", tid, "total", len(w.systems.systems))
	}
	return .None
}

must_register_system :: proc(w: ^World, sys: ^$T) {
	if err := register_system(w, sys); err != .None {
		panic(error_string(err))
	}
}

get_system :: proc(w: ^World, $T: typeid) -> (^T, bool) {
	tid := typeid_of(T)
	idx, ok := w.systems.by_type[tid]
	if !ok {
		return nil, false
	}
	return (^T)(w.systems.systems[idx].ptr), true
}
