package ecs

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
