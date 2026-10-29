package triangulate

Ring_Clipper :: struct {
	xs, ys:  []f64,
	prev:    []i32,
	next:    []i32,
	reflex:  []bool,
	relaxed: bool,
	ccw:     bool,
}

ring :: proc(coords: []i32, scale: f64, allocator := context.allocator) -> []i32 {
	n := len(coords) / 2
	for n >= 2 && coords[0] == coords[(n - 1) * 2] && coords[1] == coords[(n - 1) * 2 + 1] {
		n -= 1
	}
	if n < 3 {
		return nil
	}
	coords := coords[:n * 2]

	c: Ring_Clipper
	c.xs = make([]f64, n, allocator)
	c.ys = make([]f64, n, allocator)
	c.prev = make([]i32, n, allocator)
	c.next = make([]i32, n, allocator)
	c.reflex = make([]bool, n, allocator)
	defer {
		delete(c.xs)
		delete(c.ys)
		delete(c.prev)
		delete(c.next)
		delete(c.reflex)
	}

	c.ccw = signed_area2(coords, scale) >= 0
	for i in 0 ..< n {
		c.xs[i] = f64(coords[i * 2]) / scale
		c.ys[i] = f64(coords[i * 2 + 1]) / scale
	}
	reset(&c, n)
	if out := clip(&c, n, allocator); out != nil {
		return out
	}
	c.relaxed = true
	reset(&c, n)
	if out := clip(&c, n, allocator); out != nil {
		return out
	}
	return fan_fallback(n, allocator)
}

clip :: proc(c: ^Ring_Clipper, n: int, allocator := context.allocator) -> []i32 {
	out := make([dynamic]i32, 0, allocator)
	remaining := n
	cur: i32 = 0
	stall := 0
	for remaining > 3 {
		p, nx := c.prev[cur], c.next[cur]
		if is_ear(c, p, cur, nx, remaining) {
			append(&out, p, cur, nx)
			c.next[p] = nx
			c.prev[nx] = p
			update_reflex(c, p)
			update_reflex(c, nx)
			remaining -= 1
			stall = 0
			cur = nx
			continue
		}
		cur = nx
		stall += 1
		if stall > remaining {
			delete(out)
			return nil
		}
	}
	append(&out, c.prev[cur], cur, c.next[cur])
	return out[:]
}

reset :: proc(c: ^Ring_Clipper, n: int) {
	for i in 0 ..< n {
		if c.ccw {
			c.next[i] = i32((i + 1) % n)
			c.prev[i] = i32((i - 1 + n) % n)
		} else {
			c.next[i] = i32((i - 1 + n) % n)
			c.prev[i] = i32((i + 1) % n)
		}
	}
	for i in 0 ..< n {
		update_reflex(c, i32(i))
	}
}

is_ear :: proc(c: ^Ring_Clipper, a, b, d: i32, remaining: int) -> bool {
	if c.reflex[b] {
		return false
	}
	min_x := min(c.xs[a], c.xs[b], c.xs[d])
	max_x := max(c.xs[a], c.xs[b], c.xs[d])
	min_y := min(c.ys[a], c.ys[b], c.ys[d])
	max_y := max(c.ys[a], c.ys[b], c.ys[d])
	j := c.next[d]
	for _ in 0 ..< remaining - 3 {
		if c.reflex[j] {
			x, y := c.xs[j], c.ys[j]
			if x >= min_x && x <= max_x && y >= min_y && y <= max_y && point_in_tri(c, j, a, b, d) {
				return false
			}
		}
		j = c.next[j]
	}
	return true
}

update_reflex :: proc(c: ^Ring_Clipper, i: i32) {
	c.reflex[i] = orient(c, c.prev[i], i, c.next[i]) <= 0
}

orient :: proc(c: ^Ring_Clipper, a, b, d: i32) -> f64 {
	return (c.xs[b] - c.xs[a]) * (c.ys[d] - c.ys[a]) - (c.ys[b] - c.ys[a]) * (c.xs[d] - c.xs[a])
}

point_in_tri :: proc(c: ^Ring_Clipper, p, a, b, d: i32) -> bool {
	if c.relaxed {
		return orient(c, a, b, p) > 0 && orient(c, b, d, p) > 0 && orient(c, d, a, p) > 0
	}
	return orient(c, a, b, p) >= 0 && orient(c, b, d, p) >= 0 && orient(c, d, a, p) >= 0
}

fan_fallback :: proc(n: int, allocator := context.allocator) -> []i32 {
	d := make([dynamic]i32, 0, allocator)
	for i in 1 ..< n - 1 {
		append(&d, 0, i32(i), i32(i + 1))
	}
	return d[:]
}

signed_area2 :: proc(coords: []i32, scale: f64) -> f64 {
	s := 0.0
	n := len(coords) / 2
	for i in 0 ..< n {
		j := (i + 1) % n
		s += f64(coords[i * 2]) / scale * (f64(coords[j * 2 + 1]) / scale) -
			f64(coords[j * 2]) / scale * (f64(coords[i * 2 + 1]) / scale)
	}
	return s
}
