package ecs

each :: proc(c: Comp($T), fn: proc(e: Entity, v: ^T)) {
	if c.s == nil {
		return
	}
	s := c.s
	n := s.awake
	for i in 0 ..< n {
		fn(s.owners[i], &s.dense[i])
	}
}

each_until :: proc(c: Comp($T), fn: proc(e: Entity, v: ^T) -> bool) {
	if c.s == nil {
		return
	}
	s := c.s
	n := s.awake
	for i in 0 ..< n {
		if !fn(s.owners[i], &s.dense[i]) {
			return
		}
	}
}

all :: proc(c: Comp($T), fn: proc(e: Entity, v: ^T)) {
	if c.s == nil {
		return
	}
	s := c.s
	for i in 0 ..< len(s.dense) {
		fn(s.owners[i], &s.dense[i])
	}
}

rows :: proc(c: Comp($T)) -> []T {
	if c.s == nil {
		return nil
	}
	return c.s.dense[:c.s.awake]
}

owners :: proc(c: Comp($T)) -> []Entity {
	if c.s == nil {
		return nil
	}
	return c.s.owners[:c.s.awake]
}

all_rows :: proc(c: Comp($T)) -> []T {
	if c.s == nil {
		return nil
	}
	return c.s.dense[:]
}

each2 :: proc(a: Comp($A), b: Comp($B), fn: proc(e: Entity, av: ^A, bv: ^B)) {
	if a.s == nil || b.s == nil {
		return
	}
	sa := a.s
	n := sa.awake
	for i in 0 ..< n {
		e := sa.owners[i]
		if bv, ok := store_get(b.s, e); ok {
			fn(e, &sa.dense[i], bv)
		}
	}
}

each3 :: proc(a: Comp($A), b: Comp($B), c: Comp($C), fn: proc(e: Entity, av: ^A, bv: ^B, cv: ^C)) {
	if a.s == nil || b.s == nil || c.s == nil {
		return
	}
	sa := a.s
	n := sa.awake
	for i in 0 ..< n {
		e := sa.owners[i]
		bv, ok_b := store_get(b.s, e)
		if !ok_b {
			continue
		}
		cv, ok_c := store_get(c.s, e)
		if !ok_c {
			continue
		}
		fn(e, &sa.dense[i], bv, cv)
	}
}

collect :: proc(c: Comp($T), allocator := context.allocator) -> []Entity {
	if c.s == nil {
		return nil
	}
	out := make([]Entity, c.s.awake, allocator)
	copy(out, c.s.owners[:c.s.awake])
	return out
}

wake_all :: proc(c: Comp($T)) {
	if c.s == nil {
		return
	}
	c.s.awake = len(c.s.dense)
}

sleep_all :: proc(c: Comp($T)) {
	if c.s == nil {
		return
	}
	c.s.awake = 0
}
