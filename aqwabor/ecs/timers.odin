package ecs

HORIZON_BITS :: 12
HORIZON_SIZE :: 1 << HORIZON_BITS
HORIZON_MASK :: HORIZON_SIZE - 1

Timer_State :: enum i8 {
	None,
	Ring,
	Far,
}

Timer_Slot :: struct {
	owner: Entity,
	tick:  u64,
	pos:   i32,
	state: Timer_State,
}

Timers :: struct {
	now:   u64,
	ring:  [HORIZON_SIZE][dynamic]Entity,
	far:   map[u64][dynamic]Entity,
	slots: [dynamic]Timer_Slot,
}

@(private)
timers_init :: proc(t: ^Timers, allocator := context.allocator) {
	t.now = 0
	t.far = make(map[u64][dynamic]Entity, allocator)
	t.slots = make([dynamic]Timer_Slot, 0, 256, allocator)
	for i in 0 ..< HORIZON_SIZE {
		t.ring[i] = make([dynamic]Entity, 0, 4, allocator)
	}
}

@(private)
timers_destroy :: proc(t: ^Timers) {
	for i in 0 ..< HORIZON_SIZE {
		delete(t.ring[i])
	}
	for _, bucket in t.far {
		delete(bucket)
	}
	delete(t.far)
	delete(t.slots)
}

timers_now :: proc(t: ^Timers) -> u64 {
	return t.now
}

@(private)
timers_grow_slots :: proc(t: ^Timers, idx: int) {
	for len(t.slots) <= idx {
		append(&t.slots, Timer_Slot{state = .None})
	}
}

@(private)
timers_slot :: proc(t: ^Timers, e: Entity) -> ^Timer_Slot {
	idx := int(index(e))
	if idx >= len(t.slots) {
		return nil
	}
	s := &t.slots[idx]
	if s.state == .None || s.owner != e {
		return nil
	}
	return s
}

timers_at :: proc(t: ^Timers, e: Entity, tick: u64) {
	timers_cancel(t, e)
	tick := tick
	if tick <= t.now {
		tick = t.now + 1
	}
	idx := int(index(e))
	timers_grow_slots(t, idx)
	if tick - t.now < HORIZON_SIZE {
		b := int(tick & HORIZON_MASK)
		append(&t.ring[b], e)
		t.slots[idx] = Timer_Slot{owner = e, tick = tick, pos = i32(len(t.ring[b]) - 1), state = .Ring}
		return
	}
	bucket, ok := t.far[tick]
	if !ok {
		bucket = make([dynamic]Entity, 0, 4)
	}
	append(&bucket, e)
	t.far[tick] = bucket
	t.slots[idx] = Timer_Slot{owner = e, tick = tick, pos = i32(len(bucket) - 1), state = .Far}
}

timers_after :: proc(t: ^Timers, e: Entity, ticks: u64) {
	timers_at(t, e, t.now + ticks)
}

timers_scheduled :: proc(t: ^Timers, e: Entity) -> (u64, bool) {
	s := timers_slot(t, e)
	if s == nil {
		return 0, false
	}
	return s.tick, true
}

timers_cancel :: proc(t: ^Timers, e: Entity) -> bool {
	s := timers_slot(t, e)
	if s == nil {
		return false
	}
	state := s.state
	tick := s.tick
	pos := int(s.pos)

	swap_remove :: proc(bucket: ^[dynamic]Entity, e: Entity, pos: int, t: ^Timers) {
		if pos < len(bucket^) && bucket[pos] == e {
			last := len(bucket^) - 1
			bucket[pos] = bucket[last]
			if pos != last {
				moved := bucket[pos]
				if ms := timers_slot(t, moved); ms != nil {
					ms.pos = i32(pos)
				}
			}
			pop(bucket)
		}
	}

	switch state {
	case .Ring:
		swap_remove(&t.ring[int(tick & HORIZON_MASK)], e, pos, t)
	case .Far:
		bucket, ok := t.far[tick]
		if ok {
			swap_remove(&bucket, e, pos, t)
			if len(bucket) == 0 {
				delete(bucket)
				delete_key(&t.far, tick)
			} else {
				t.far[tick] = bucket
			}
		}
	case .None:
		return false
	}

	s.state = .None
	return true
}

timers_advance :: proc(t: ^Timers, fn: proc(e: Entity)) {
	t.now += 1
	b := int(t.now & HORIZON_MASK)

	due := t.ring[b]
	clear(&t.ring[b])
	for e in due {
		if s := timers_slot(t, e); s != nil && s.tick == t.now {
			s.state = .None
			fn(e)
		}
	}

	if far, ok := t.far[t.now]; ok {
		delete_key(&t.far, t.now)
		for e in far {
			if s := timers_slot(t, e); s != nil && s.tick == t.now {
				s.state = .None
				fn(e)
			}
		}
		delete(far)
	}
}

timers_pending :: proc(t: ^Timers) -> int {
	n := 0
	for i in 0 ..< HORIZON_SIZE {
		n += len(t.ring[i])
	}
	for _, bucket in t.far {
		n += len(bucket)
	}
	return n
}

@(private)
timers_reset :: proc(t: ^Timers) {
	for i in 0 ..< HORIZON_SIZE {
		clear(&t.ring[i])
	}
	for _, bucket in t.far {
		delete(bucket)
	}
	clear(&t.far)
	clear(&t.slots)
	t.now = 0
}
