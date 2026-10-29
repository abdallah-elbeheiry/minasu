package ecs

Command_Fn :: proc(w: ^World)

Command_Buffer :: struct {
	destroy: [dynamic]Entity,
	apply:   [dynamic]Command_Fn,
}

@(private)
command_buffer_init :: proc(b: ^Command_Buffer, allocator := context.allocator) {
	b.destroy = make([dynamic]Entity, 0, 64, allocator)
	b.apply = make([dynamic]Command_Fn, 0, 64, allocator)
}

@(private)
command_buffer_destroy :: proc(b: ^Command_Buffer) {
	delete(b.destroy)
	delete(b.apply)
}

cmd_destroy :: proc(b: ^Command_Buffer, e: Entity) {
	append(&b.destroy, e)
}

cmd_do :: proc(b: ^Command_Buffer, fn: Command_Fn) {
	append(&b.apply, fn)
}

cmd_len :: proc(b: ^Command_Buffer) -> int {
	return len(b.destroy) + len(b.apply)
}

@(private)
command_buffer_clear :: proc(b: ^Command_Buffer) {
	clear(&b.destroy)
	clear(&b.apply)
}

@(private)
command_buffer_apply :: proc(b: ^Command_Buffer, w: ^World) {
	if cmd_len(b) == 0 {
		return
	}
	for fn in b.apply {
		fn(w)
	}
	for e in b.destroy {
		destroy(w, e)
	}
	command_buffer_clear(b)
}
