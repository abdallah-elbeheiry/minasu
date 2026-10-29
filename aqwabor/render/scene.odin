package render

import "aqwabor:ecs"
import "aqwabor:logx"

// ============================================================================
// Draw plan entry for scene culling
// ============================================================================

Draw_Plan_Entry :: struct {
	layer:  int,
	culled: ^Cull_Pipeline,
	direct: Inst_Range,
	ok:     bool,
	slot:   int,
}

// ============================================================================
// ECS component types (from ecs.go in the Go source)
// ============================================================================

Transform :: struct {
	x, y:   f32,
	rot:    f32,
	sx, sy: f32,
}

Color :: struct {
	r, g, b, a: f32,
}

Sprite :: struct {
	layer: f32,
	uvx:   f32,
	uvy:   f32,
	flags: u32,
}

Components :: struct {
	transform: ecs.Comp(Transform),
	color:     ecs.Comp(Color),
	sprite:    ecs.Comp(Sprite)
}

register_ecs :: proc(w: ^ecs.World) -> (Components, ecs.Error) {
	c: Components
	err: ecs.Error

	c.transform, err = ecs.register(w, Transform)
	if err != .None {
		return c, err
	}
	c.color, err = ecs.register(w, Color)
	if err != .None {
		return c, err
	}
	c.sprite, err = ecs.register(w, Sprite)
	if err != .None {
		return c, err
	}
	return c, .None
}

must_register_ecs :: proc(w: ^ecs.World) -> Components {
	c, err := register_ecs(w)
	if err != .None {
		logx.logger_error(g_log, "render.RegisterECS", "err", ecs.error_string(err))
	}
	return c
}

// ============================================================================
// Scene - draws what a world holds
// ============================================================================

Scene :: struct {
	gfx:      ^GPU,
	world:    ^ecs.World,
	comps:    Components,
	layers:   [dynamic]^Scene_Layer,
	layer_of: map[ecs.Entity]int,
	awake:    [dynamic]ecs.Entity,
	damaged:  [dynamic]View_Bounds,
	instances: map[ecs.Entity]View_Bounds,
	stats:    Scene_Stats,
}

Scene_Config :: struct {
	chunk_size: f32,
	layers:     int,
}

Scene_Stats :: struct {
	written:   int,
	rebuilt:   int,
	submitted: int,
	draws:     int,
}

Scene_Layer :: struct {
	grid:  ^Grid,
	batch: ^Sprite_Batch,
	sweep: int,
	sink:  ^Instance_Sink,
	scratch: [dynamic]Instance_Data,
}

Instance_Sink :: struct {
	batch: ^Sprite_Batch,
}

cull_from :: 64

new_scene :: proc(gfx: ^GPU, w: ^ecs.World, comps: Components, cfg: Scene_Config, allocator := context.allocator) -> ^Scene {
	layers := cfg.layers
	if layers < 1 {
		layers = 1
	}

	s := &Scene{
		gfx       = gfx,
		world     = w,
		comps     = comps,
		layer_of  = make(map[ecs.Entity]int, allocator),
		instances = make(map[ecs.Entity]View_Bounds, allocator),
	}
	for i in 0 ..< layers {
		ls := s.layers
		append_elems(&ls, &Scene_Layer{grid = new_grid(cfg.chunk_size), sink = nil})
		s.layers = ls
	}
	return s
}

scene_spawn :: proc(s: ^Scene, t: Transform, c: Color, sp: Sprite) -> ecs.Entity {
	e := ecs.create(s.world)
	ecs_comp_set(Transform, s.comps.transform, e, t)
	ecs_comp_set(Color, s.comps.color, e, c)
	ecs_comp_set(Sprite, s.comps.sprite, e, sp)
	ecs_comp_wake(Transform, s.comps.transform, e)
	return e
}

scene_drop :: proc(s: ^Scene, e: ecs.Entity) {
	li, ok := s.layer_of[e]
	if !ok {
		return
	}
	if idx, had := scene_grid_remove(s.layers[li].grid, e); had && s.layers[li].sink != nil {
		scene_sink_set(s.layers[li].sink, idx, Instance_Data{})
		s.stats.written += 1
	}
	if was, ok := s.instances[e]; ok {
		scene_damage_rect(s, was)
	}
}

scene_sync :: proc(s: ^Scene) {
	s.stats.written = 0
	s.stats.rebuilt = 0
	s.damaged = make([dynamic]View_Bounds, 0)

	s.awake = make([dynamic]ecs.Entity, 0)
	if s.comps.transform.s != nil {
		for e in s.comps.transform.s.owners {
			aw := s.awake
			append_elems(&aw, e)
			s.awake = aw
		}
	}
	for e in s.awake {
		scene_sync_entity(s, e)
	}

	for li := 0; li < len(s.layers); li += 1 {
		scene_sweep_one(s, li)
	}

	for l, li in s.layers {
		if l.grid.stale {
			scene_rebuild(s, li)
			continue
		}
		if len(l.grid.moved) > 0 {
			scene_rewrite_moved(s, li)
		}
	}
}

scene_sync_entity :: proc(s: ^Scene, e: ecs.Entity) {
	if !ecs.alive(s.world, e) {
		scene_drop(s, e)
		return
	}
	t, ok := ecs_comp_get(Transform, s.comps.transform, e)
	if !ok {
		scene_drop(s, e)
		return
	}
	sp, ok_sprite := ecs_comp_get(Sprite, s.comps.sprite, e)
	if !ok_sprite {
		scene_drop(s, e)
		return
	}

	li := scene_layer_for(s, sp^)
	if was, ok := s.layer_of[e]; ok && was != li {
		if idx, had := scene_grid_remove(s.layers[was].grid, e); had {
			scene_sink_set(s.layers[was].sink, idx, Instance_Data{})
			s.stats.written += 1
		}
	}
	s.layer_of[e] = li

	l := s.layers[li]
	sx, sy := scale_of(t^)

	if was, ok := s.instances[e]; ok {
		scene_damage_rect(s, was)
	}
	now := View_Bounds{
		min_x = t.x - sx / 2,
		min_y = t.y - sy / 2,
		max_x = t.x + sx / 2,
		max_y = t.y + sy / 2,
	}
	scene_damage_rect(s, now)
	s.instances[e] = now

	idx, vacated, freed := grid_place(l.grid, e, t.x, t.y, sx, sy)
	scene_ensure(s, li)
	if freed {
		scene_sink_set(l.sink, vacated, Instance_Data{})
		s.stats.written += 1
	}
	scene_sink_set(l.sink, idx, scene_instance(s, e, t^, sp^))
	s.stats.written += 1
}

scene_rewrite_moved :: proc(s: ^Scene, li: int) {
	l := s.layers[li]
	scene_ensure(s, li)

	for key in l.grid.moved {
		ci, ok := l.grid.by_key[key]
		if !ok {
			continue
		}
		c := &l.grid.chunks[ci]
		for slot := 0; slot < len(c.slots); slot += 1 {
			e := c.slots[slot]
			if e == ecs.NO_ENTITY {
				scene_sink_set(l.sink, c.start + slot, Instance_Data{})
				s.stats.written += 1
				continue
			}
			t, okT := ecs_comp_get(Transform, s.comps.transform, e)
			sp, okS := ecs_comp_get(Sprite, s.comps.sprite, e)
			if !okT || !okS {
				scene_sink_set(l.sink, c.start + slot, Instance_Data{})
				s.stats.written += 1
				continue
			}
			scene_sink_set(l.sink, c.start + slot, scene_instance(s, e, t^, sp^))
			s.stats.written += 1
		}
	}
	l.grid.moved = make([dynamic]Chunk_Key, 0)
}

scene_sweep_one :: proc(s: ^Scene, li: int) {
	l := s.layers[li]
	if len(l.grid.chunks) == 0 {
		return
	}
	if l.grid.sweep >= len(l.grid.chunks) {
		l.grid.sweep = 0
	}
	c := &l.grid.chunks[l.grid.sweep]
	l.grid.sweep += 1

	for e in c.slots {
		if e == ecs.NO_ENTITY || ecs.alive(s.world, e) {
			continue
		}
		scene_drop(s, e)
	}
}

scene_rebuild :: proc(s: ^Scene, li: int) {
	l := s.layers[li]
	grid_relayout(l.grid)
	scene_ensure(s, li)

	if cap(l.scratch) < l.grid.total {
		l.scratch = make([dynamic]Instance_Data, l.grid.total, context.allocator)
	}
	for i := 0; i < l.grid.total; i += 1 {
		l.scratch[i] = Instance_Data{}
	}

	for ci := 0; ci < len(l.grid.chunks); ci += 1 {
		c := &l.grid.chunks[ci]
		for slot := 0; slot < len(c.slots); slot += 1 {
			e := c.slots[slot]
			if e == ecs.NO_ENTITY {
				continue
			}
			t, ok := ecs_comp_get(Transform, s.comps.transform, e)
			if !ok {
				continue
			}
			sp, ok_sprite := ecs_comp_get(Sprite, s.comps.sprite, e)
			if !ok_sprite {
				continue
			}
			l.scratch[c.start + slot] = scene_instance(s, e, t^, sp^)
		}
	}

	scene_sink_set_all(l.sink, l.scratch)
	s.stats.written += len(l.scratch)
	s.stats.rebuilt += 1
}

scene_draw :: proc(s: ^Scene, view: View_Bounds) {
	s.stats.submitted = 0
	s.stats.draws = 0

	slots := cull_slots
	plan := make([dynamic]Draw_Plan_Entry, 0)

	for l, li in s.layers {
		if l.batch == nil || l.grid.total == 0 {
			continue
		}
		for r in grid_visible(l.grid, view, slots) {
			s.stats.submitted += r.count
			if r.count >= cull_from && slots > 0 {
				c := gpu_cull_sprites_range(s.gfx, l.batch, r.first, r.count, view)
				if c.ok {
					slots -= 1
				pe := Draw_Plan_Entry{
					layer = li,
					culled = c.cull,
					direct = Inst_Range{first = c.slot, count = 0},
					ok = c.ok,
					slot = c.slot,
				}
				p := plan
				append_elems(&p, pe)
				plan = p
				continue
				}
			}
			pe := Draw_Plan_Entry{
				layer = li,
				direct = r,
			}
			p := plan
			append_elems(&p, pe)
			plan = p
		}
	}

	for p in plan {
		if p.ok {
			_ = p
		} else {
			gpu_draw_sprites_range(s.gfx, s.layers[p.layer].batch, p.direct.first, p.direct.count)
		}
		s.stats.draws += 1
	}
}

scene_damage_rect :: proc(s: ^Scene, r: View_Bounds) {
	d := s.damaged
	append_elems(&d, r)
	s.damaged = d
}

scene_damaged :: proc(s: ^Scene) -> [dynamic]View_Bounds {
	return s.damaged
}

scene_stats :: proc(s: ^Scene) -> Scene_Stats {
	return s.stats
}

scene_release :: proc(s: ^Scene) {
	for l in s.layers {
		if l.batch != nil {
			sprite_batch_release(l.batch)
			l.batch = nil
		}
	}
}

scene_layer_for :: proc(s: ^Scene, sp: Sprite) -> int {
	li := cast(int) sp.layer
	if li < 0 {
		return 0
	}
	if li >= len(s.layers) {
		return len(s.layers) - 1
	}
	return li
}

scene_ensure :: proc(s: ^Scene, li: int) {
	l := s.layers[li]
	if l.sink != nil {
		return
	}
	l.batch = gpu_sprites(s.gfx, max(l.grid.total, 64))
	l.sink = &Instance_Sink{batch = l.batch}
}

scene_instance :: proc(s: ^Scene, e: ecs.Entity, t: Transform, sp: Sprite) -> Instance_Data {
	col := Color{r = 1, g = 1, b = 1, a = 1}
	if c, ok := ecs_comp_get(Color, s.comps.color, e); ok {
		col = c^
	}
	sx, sy := scale_of(t)
	return Instance_Data{
		position  = [2]f32{t.x, t.y},
		scale     = [2]f32{sx, sy},
		rotation  = t.rot,
		color     = [4]f32{col.r, col.g, col.b, col.a},
		uv_offset = [2]f32{sp.uvx, sp.uvy},
		layer     = sp.layer,
		pad       = 0,
	}
}

scale_of :: proc(t: Transform) -> (f32, f32) {
	sx, sy := t.sx, t.sy
	if sx == 0 {
		sx = 1
	}
	if sy == 0 {
		sy = 1
	}
	return sx, sy
}

clamp_255 :: proc(v: f32) -> u32 {
	if v <= 0 {
		return 0
	}
	if v >= 1 {
		return 255
	}
	return cast(u32) v * 255
}

// ============================================================================
// Grid / chunks (from chunks.go)
// ============================================================================

slack :: 8

Chunk_Key :: struct {
	cx, cy: i32,
}

Grid_Chunk :: struct {
	key:   Chunk_Key,
	slots: [dynamic]ecs.Entity,
	used:  int,
	start: int,
	min_x, min_y, max_x, max_y: f32,
}

grid_chunk_empty :: proc(c: ^Grid_Chunk) -> bool {
	return c.used == 0
}

grid_chunk_cover :: proc(c: ^Grid_Chunk, x, y, w, h: f32) {
	hw, hh := w / 2, h / 2
	if x - hw < c.min_x {
		c.min_x = x - hw
	}
	if x + hw > c.max_x {
		c.max_x = x + hw
	}
	if y - hh < c.min_y {
		c.min_y = y - hh
	}
	if y + hh > c.max_y {
		c.max_y = y + hh
	}
}

Home :: struct {
	key:  Chunk_Key,
	slot: int,
}

Grid :: struct {
	size:   f32,
	chunks: [dynamic]Grid_Chunk,
	by_key: map[Chunk_Key]int,
	homes:  map[ecs.Entity]Home,
	total:  int,
	wasted: int,
	moved:  [dynamic]Chunk_Key,
	stale:  bool,
	sweep:  int,
}

new_grid :: proc(size: f32) -> ^Grid {
	s := size
	if s <= 0 {
		s = 64
	}
	g := new(Grid)
	g.size = s
	g.by_key = make(map[Chunk_Key]int)
	g.homes = make(map[ecs.Entity]Home)
	return g
}

grid_alloc :: proc(g: ^Grid, n: int) -> int {
	start := g.total
	g.total += n
	return start
}

grid_key_for :: proc(g: ^Grid, x, y: f32) -> Chunk_Key {
	return Chunk_Key{cx = floor_div(x, g.size), cy = floor_div(y, g.size)}
}

floor_div :: proc(v, size: f32) -> i32 {
	q := v / size
	i := cast(i32) q
	if q < 0 && cast(f32) i != q {
		i -= 1
	}
	return i
}

grid_place :: proc(g: ^Grid, e: ecs.Entity, x, y, w, h: f32) -> (idx: int, vacated: int, freed: bool) {
	key := grid_key_for(g, x, y)

	if prev, ok := g.homes[e]; ok {
		if prev.key == key {
			c := &g.chunks[g.by_key[key]]
			grid_chunk_cover(c, x, y, w, h)
			return c.start + prev.slot, 0, false
		}
		if ci, ok := g.by_key[prev.key]; ok {
			vacated, freed = g.chunks[ci].start + prev.slot, true
		}
		grid_take(g, e, prev)
	}

	ci := grid_chunk_for(g, key)
	c := &g.chunks[ci]
	slot, ok := grid_chunk_free(c)
	if !ok {
		by := max(slack, len(c.slots) / 4)
		slot = len(c.slots)
		old_slots := c.slots
		c.slots = make([dynamic]ecs.Entity, len(c.slots) + by, context.allocator)
		for i := 0; i < len(old_slots); i += 1 {
			c.slots[i] = old_slots[i]
		}
		for i := slot; i < len(c.slots); i += 1 {
			c.slots[i] = ecs.NO_ENTITY
		}
		g.wasted += slot
		c.start = grid_alloc(g, len(c.slots))
		mv := g.moved
		append_elems(&mv, c.key)
		g.moved = mv
		grid_check_compaction(g)
	}
	c.slots[slot] = e
	c.used += 1
	grid_chunk_cover(c, x, y, w, h)
	g.homes[e] = Home{key = key, slot = slot}
	return c.start + slot, vacated, freed
}

grid_remove :: proc(g: ^Grid, e: ecs.Entity) -> (int, bool) {
	h, ok := g.homes[e]
	if !ok {
		return 0, false
	}
	idx := g.chunks[g.by_key[h.key]].start + h.slot
	grid_take(g, e, h)
	return idx, true
}

grid_note_empty :: proc(g: ^Grid, c: ^Grid_Chunk) {
	g.wasted += len(c.slots)
	grid_check_compaction(g)
}

grid_take :: proc(g: ^Grid, e: ecs.Entity, h: Home) {
	ci, ok := g.by_key[h.key]
	if !ok {
		return
	}
	c := &g.chunks[ci]
	if h.slot < len(c.slots) && c.slots[h.slot] == e {
		c.slots[h.slot] = ecs.NO_ENTITY
		c.used -= 1
		if c.used == 0 {
			grid_note_empty(g, c)
		}
	}
}

grid_chunk_free :: proc(c: ^Grid_Chunk) -> (int, bool) {
	for e, i in c.slots {
		if e == ecs.NO_ENTITY {
			return i, true
		}
	}
	return 0, false
}

grid_chunk_for :: proc(g: ^Grid, key: Chunk_Key) -> int {
	if i, ok := g.by_key[key]; ok {
		return i
	}

	at := 0
	for i := 0; i < len(g.chunks); i += 1 {
		if !chunk_key_before(g.chunks[i].key, key) {
			at = i
			break
		}
		at = i + 1
	}

	c := Grid_Chunk{
		key    = key,
		slots  = make([dynamic]ecs.Entity, slack, context.allocator),
		start  = 0,
		min_x  = cast(f32) key.cx * g.size,
		min_y  = cast(f32) key.cy * g.size,
		max_x  = cast(f32) (key.cx + 1) * g.size,
		max_y  = cast(f32) (key.cy + 1) * g.size,
	}
	for i := 0; i < len(c.slots); i += 1 {
		c.slots[i] = ecs.NO_ENTITY
	}

	c.start = grid_alloc(g, slack)

	new_chunks := make([dynamic]Grid_Chunk, len(g.chunks) + 1, context.allocator)
	for i := 0; i < at; i += 1 {
		new_chunks[i] = g.chunks[i]
	}
	new_chunks[at] = c
	for i := at; i < len(g.chunks); i += 1 {
		new_chunks[i + 1] = g.chunks[i]
	}
	g.chunks = new_chunks

	grid_reindex(g)
	return at
}

grid_check_compaction :: proc(g: ^Grid) {
	if g.total > 0 && g.wasted * 2 >= g.total {
		g.stale = true
	}
}

chunk_key_before :: proc(a, b: Chunk_Key) -> bool {
	if a.cy != b.cy {
		return a.cy < b.cy
	}
	return a.cx < b.cx
}

grid_reindex :: proc(g: ^Grid) {
	delete(g.by_key)
	for i := 0; i < len(g.chunks); i += 1 {
		g.by_key[g.chunks[i].key] = i
	}
}

grid_relayout :: proc(g: ^Grid) {
	kept := make([dynamic]Grid_Chunk, 0, len(g.chunks))
	for i := 0; i < len(g.chunks); i += 1 {
		if !grid_chunk_empty(&g.chunks[i]) {
			kt := kept
			append_elems(&kt, g.chunks[i])
			kept = kt
		}
	}
	g.chunks = kept

	at := 0
	for i := 0; i < len(g.chunks); i += 1 {
		g.chunks[i].start = at
		at += len(g.chunks[i].slots)
	}
	g.total = at
	g.wasted = 0
	g.moved = make([dynamic]Chunk_Key, 0)
	grid_reindex(g)
	g.stale = false
}

grid_index_of :: proc(g: ^Grid, e: ecs.Entity) -> (int, bool) {
	h, ok := g.homes[e]
	if !ok {
		return 0, false
	}
	ci, ok_by_key := g.by_key[h.key]
	if !ok_by_key {
		return 0, false
	}
	return g.chunks[ci].start + h.slot, true
}

Inst_Range :: struct {
	first: int,
	count: int,
}

grid_visible :: proc(g: ^Grid, v: View_Bounds, max: int) -> [dynamic]Inst_Range {
	m := max
	if m < 1 {
		m = 1
	}

	found := make([dynamic]Inst_Range, 0)
	for i := 0; i < len(g.chunks); i += 1 {
		c := &g.chunks[i]
		if c.used == 0 || !grid_chunk_overlaps(c, v) {
			continue
		}
		f := found
		append_elems(&f, Inst_Range{first = c.start, count = len(c.slots)})
		found = f
	}

	for i in 1 ..< len(found) {
		for j := i; j > 0 && found[j].first < found[j - 1].first; j -= 1 {
			found[j], found[j - 1] = found[j - 1], found[j]
		}
	}

	runs := make([dynamic]Inst_Range, 0)
	for r in found {
		n := len(runs)
		if n > 0 && runs[n - 1].first + runs[n - 1].count == r.first {
			rn := runs
			rn[n - 1].count += r.count
			runs = rn
			continue
		}
		ru := runs
		append_elems(&ru, r)
		runs = ru
	}

	for len(runs) > m {
		best := 0
		best_gap := -1
		for i := 0; i + 1 < len(runs); i += 1 {
			gap := runs[i + 1].first - (runs[i].first + runs[i].count)
			if best_gap < 0 || gap < best_gap {
				best, best_gap = i, gap
			}
		}
		runs[best].count = runs[best + 1].first + runs[best + 1].count - runs[best].first
		new_runs := make([dynamic]Inst_Range, 0, len(runs) - 1)
		for i in 0 ..< len(runs) {
			if i != best + 1 {
				nr := new_runs
				append_elems(&nr, runs[i])
				new_runs = nr
			}
		}
		runs = new_runs
	}
	return runs
}

grid_chunk_overlaps :: proc(c: ^Grid_Chunk, v: View_Bounds) -> bool {
	if v.min_x >= v.max_x || v.min_y >= v.max_y {
		return true
	}
	return c.max_x >= v.min_x && c.min_x <= v.max_x && c.max_y >= v.min_y && c.min_y <= v.max_y
}

// ============================================================================
// ECS comp helpers
// ============================================================================

ecs_comp_set :: proc($T: typeid, c: ecs.Comp(T), e: ecs.Entity, v: T) -> bool {
	return ecs.set(c, e, v)
}

ecs_comp_get :: proc($T: typeid, c: ecs.Comp(T), e: ecs.Entity) -> (^T, bool) {
	return ecs.get(c, e)
}

ecs_comp_wake :: proc($T: typeid, c: ecs.Comp(T), e: ecs.Entity) -> bool {
	return ecs.wake(c, e)
}

ecs_comp_sleep :: proc(c: ecs.Comp($T), e: ecs.Entity) -> bool {
	return ecs.sleep(c, e)
}

scene_grid_remove :: proc(g: ^Grid, e: ecs.Entity) -> (int, bool) {
	return grid_remove(g, e)
}

scene_sink_set :: proc(sink: ^Instance_Sink, index: int, inst: Instance_Data) {
	if sink != nil && sink.batch != nil {
		sprite_batch_set(sink.batch, index, inst)
	}
}

scene_sink_set_all :: proc(sink: ^Instance_Sink, insts: [dynamic]Instance_Data) {
	if sink != nil && sink.batch != nil {
		sprite_batch_set_all(sink.batch, insts)
	}
}

gpu_cull_sprites_range :: proc(gfx: ^GPU, batch: ^Sprite_Batch, first, count: int, view_bounds: View_Bounds) -> Culled {
	return cull_sprites_range(gfx, batch, first, count, view_bounds)
}

gpu_draw_sprites_range :: proc(gfx: ^GPU, batch: ^Sprite_Batch, first, count: int) {
	draw_sprites_range(gfx, batch, first, count)
}

gpu_sprites :: proc(gfx: ^GPU, capacity: int) -> ^Sprite_Batch {
	return sprites(gfx, capacity)
}
