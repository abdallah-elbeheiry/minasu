package ecs

import "base:runtime"

// A store holds every value of one component type in a dense array, with a
// sparse index from entity to the row holding that entity's value. Adding and
// removing are O(1) and move at most one row.
//
// The dense array is partitioned. Rows before awake are the entities a system
// iterates by default; rows from awake onward exist but are not visited.

@(private)
NO_ROW :: i32(-1)

@(private)
Store :: struct($T: typeid) {
	cid:          Component_ID,
	world:        ^World,
	allocator:    runtime.Allocator,
	destroy_elem: proc(data: ^T, allocator: runtime.Allocator), // optional per-element destructor
	dense:        [dynamic]T,
	owners:       [dynamic]Entity,
	sparse:       [dynamic]i32,
	awake:        int,
}

@(private)
Any_Store :: struct {
	impl:          rawptr,
	cid:           Component_ID,
	remove_entity: proc(impl: rawptr, e: Entity) -> bool,
	reset:         proc(impl: rawptr),
	destroy:       proc(impl: rawptr),
}

@(private)
store_init :: proc(s: ^Store($T), w: ^World, cid: Component_ID, allocator := context.allocator, destroy_cb: proc(data: ^T, allocator: runtime.Allocator) = nil) {
	s.cid = cid
	s.world = w
	s.allocator = allocator
	s.destroy_elem = destroy_cb
	s.dense = make([dynamic]T, 0, 64, allocator)
	s.owners = make([dynamic]Entity, 0, 64, allocator)
	s.sparse = make([dynamic]i32, 0, 64, allocator)
	s.awake = 0
}

@(private)
store_destroy :: proc(s: ^Store($T)) {
	if s.destroy_elem != nil {
		for i in 0 ..< len(s.dense) {
			s.destroy_elem(&s.dense[i], s.allocator)
		}
	}
	delete(s.dense)
	delete(s.owners)
	delete(s.sparse)
	free(s, s.allocator)
}

@(private)
store_row :: proc(s: ^Store($T), e: Entity) -> i32 {
	idx := int(index(e))
	if idx >= len(s.sparse) {
		return NO_ROW
	}
	r := s.sparse[idx]
	if r == NO_ROW {
		return NO_ROW
	}
	if s.owners[r] != e {
		return NO_ROW
	}
	return r
}

@(private)
store_has :: proc(s: ^Store($T), e: Entity) -> bool {
	return store_row(s, e) != NO_ROW
}

@(private)
store_grow_sparse :: proc(s: ^Store($T), idx: int) {
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
store_set :: proc(s: ^Store($T), e: Entity, v: T) {
	if r := store_row(s, e); r != NO_ROW {
		if s.destroy_elem != nil {
			s.destroy_elem(&s.dense[r], s.allocator)
		}
		s.dense[r] = v
		return
	}
	idx := int(index(e))
	store_grow_sparse(s, idx)
	append(&s.dense, v)
	append(&s.owners, e)
	s.sparse[idx] = i32(len(s.dense) - 1)
}

@(private)
store_get :: proc(s: ^Store($T), e: Entity) -> (^T, bool) {
	r := store_row(s, e)
	if r == NO_ROW {
		return nil, false
	}
	return &s.dense[r], true
}

@(private)
store_swap :: proc(s: ^Store($T), a, b: i32) {
	if a == b {
		return
	}
	s.dense[a], s.dense[b] = s.dense[b], s.dense[a]
	s.owners[a], s.owners[b] = s.owners[b], s.owners[a]
	s.sparse[index(s.owners[a])] = a
	s.sparse[index(s.owners[b])] = b
}

@(private)
store_remove :: proc(s: ^Store($T), e: Entity) -> bool {
	r := store_row(s, e)
	if r == NO_ROW {
		return false
	}
	if int(r) < s.awake {
		store_swap(s, r, i32(s.awake - 1))
		r = i32(s.awake - 1)
		s.awake -= 1
	}
	last := i32(len(s.dense) - 1)
	store_swap(s, r, last)
	// Destroy the removed element's heap data before dropping the row.
	if s.destroy_elem != nil {
		s.destroy_elem(&s.dense[last], s.allocator)
	}
	s.sparse[index(s.owners[last])] = NO_ROW
	pop(&s.dense)
	pop(&s.owners)
	return true
}

@(private)
store_wake :: proc(s: ^Store($T), e: Entity) -> bool {
	r := store_row(s, e)
	if r == NO_ROW || int(r) < s.awake {
		return false
	}
	store_swap(s, r, i32(s.awake))
	s.awake += 1
	return true
}

@(private)
store_sleep :: proc(s: ^Store($T), e: Entity) -> bool {
	r := store_row(s, e)
	if r == NO_ROW || int(r) >= s.awake {
		return false
	}
	store_swap(s, r, i32(s.awake - 1))
	s.awake -= 1
	return true
}

@(private)
store_is_awake :: proc(s: ^Store($T), e: Entity) -> bool {
	r := store_row(s, e)
	return r != NO_ROW && int(r) < s.awake
}

@(private)
store_reset :: proc(s: ^Store($T)) {
	if s.destroy_elem != nil {
		for i in 0 ..< len(s.dense) {
			s.destroy_elem(&s.dense[i], s.allocator)
		}
	}
	clear(&s.dense)
	clear(&s.owners)
	for i in 0 ..< len(s.sparse) {
		s.sparse[i] = NO_ROW
	}
	s.awake = 0
}

@(private)
make_any_store :: proc(s: ^Store($T)) -> Any_Store {
	return Any_Store{
		impl = s,
		cid = s.cid,
		remove_entity = proc(impl: rawptr, e: Entity) -> bool {
			return store_remove((^Store(T))(impl), e)
		},
		reset = proc(impl: rawptr) {
			store_reset((^Store(T))(impl))
		},
		destroy = proc(impl: rawptr) {
			store_destroy((^Store(T))(impl))
		},
	}
}
