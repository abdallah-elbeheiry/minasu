package ecs

import "base:runtime"

Set :: struct {
	world:      ^World,
	allocator:  runtime.Allocator,
	dense:      [dynamic]Entity,
	sparse:     [dynamic]i32,
}

new_set :: proc(w: ^World, allocator: runtime.Allocator = {}) -> ^Set {
	alloc := allocator
	if alloc == (runtime.Allocator{}) {
		alloc = w.allocator
	}
	s := new(Set, alloc)
	s.world = w
	s.allocator = alloc
	s.dense = make([dynamic]Entity, 0, 64, alloc)
	s.sparse = make([dynamic]i32, 0, 64, alloc)
	append(&w.sets, s)
	return s
}

@(private)
set_destroy :: proc(s: ^Set) {
	delete(s.dense)
	delete(s.sparse)
	free(s, s.allocator)
}

@(private)
set_grow_sparse :: proc(s: ^Set, idx: int) {
	if idx < len(s.sparse) {
		return
	}
	old := len(s.sparse)
	resize(&s.sparse, idx + 1)
	for i in old ..< len(s.sparse) {
		s.sparse[i] = NO_ROW
	}
}

@(private)
set_row :: proc(s: ^Set, e: Entity) -> i32 {
	idx := int(index(e))
	if idx >= len(s.sparse) {
		return NO_ROW
	}
	r := s.sparse[idx]
	if r == NO_ROW || s.dense[r] != e {
		return NO_ROW
	}
	return r
}

set_add :: proc(s: ^Set, e: Entity) -> bool {
	if !alive(s.world, e) || set_row(s, e) != NO_ROW {
		return false
	}
	idx := int(index(e))
	set_grow_sparse(s, idx)
	append(&s.dense, e)
	s.sparse[idx] = i32(len(s.dense) - 1)
	return true
}

set_remove :: proc(s: ^Set, e: Entity) -> bool {
	r := set_row(s, e)
	if r == NO_ROW {
		return false
	}
	last := i32(len(s.dense) - 1)
	if r != last {
		moved := s.dense[last]
		s.dense[r] = moved
		s.sparse[index(moved)] = r
	}
	s.sparse[index(e)] = NO_ROW
	pop(&s.dense)
	return true
}

set_has :: proc(s: ^Set, e: Entity) -> bool {
	return set_row(s, e) != NO_ROW
}

set_len :: proc(s: ^Set) -> int {
	return len(s.dense)
}

set_clear :: proc(s: ^Set) {
	for e in s.dense {
		s.sparse[index(e)] = NO_ROW
	}
	clear(&s.dense)
}

set_each :: proc(s: ^Set, fn: proc(e: Entity)) {
	for e in s.dense {
		fn(e)
	}
}

set_entities :: proc(s: ^Set) -> []Entity {
	return s.dense[:]
}

each_in :: proc(s: ^Set, c: Comp($T), fn: proc(e: Entity, v: ^T)) {
	if s == nil || c.s == nil {
		return
	}
	for e in s.dense {
		if v, ok := store_get(c.s, e); ok {
			fn(e, v)
		}
	}
}

each_in2 :: proc(s: ^Set, a: Comp($A), b: Comp($B), fn: proc(e: Entity, av: ^A, bv: ^B)) {
	if s == nil || a.s == nil || b.s == nil {
		return
	}
	for e in s.dense {
		av, ok_a := store_get(a.s, e)
		if !ok_a {
			continue
		}
		bv, ok_b := store_get(b.s, e)
		if !ok_b {
			continue
		}
		fn(e, av, bv)
	}
}
