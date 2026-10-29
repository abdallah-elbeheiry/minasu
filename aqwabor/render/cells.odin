package render

import "aqwabor:logx"
import "core:math"

// ============================================================================
// Cells - compact palette-indexed grid layer
// ============================================================================

Cells :: struct {
	gfx:         ^GPU,
	buf:         ^Subcell_Buffer,
	w, h:        int,
	chunk:       int,
	cw, ch:      int,
	slots:       int,
	size:        f32,
	origin_x:    f32,
	origin_y:    f32,
	dirty:       [dynamic]i32,
	seen:        [dynamic]bool,
	all:         bool,
	damaged:     [dynamic]View_Bounds,
	stats:       Cell_Stats,
}

Cells_Config :: struct {
	w, h:         int,
	cell_size:    f32,
	origin_x:     f32,
	origin_y:     f32,
	chunk:        int,
}

Cell_Stats :: struct {
	written:   int,
	submitted: int,
	draws:     int,
}

Cell_Sink :: struct {
	write_proc:     proc(index: int, inst: ^Subcell_Instance),
	write_all_proc: proc(insts: []Subcell_Instance),
}

new_cells :: proc(gfx: ^GPU, cfg: Cells_Config) -> ^Cells {
	chunk := cfg.chunk
	if chunk <= 0 {
		chunk = 32
	}
	cell_size := cfg.cell_size
	if cell_size <= 0 {
		cell_size = 1
	}

	c := &Cells{
		gfx        = gfx,
		w          = max(cfg.w, 0),
		h          = max(cfg.h, 0),
		chunk      = chunk,
		size       = cell_size,
		origin_x   = cfg.origin_x,
		origin_y   = cfg.origin_y,
	}
	c.cw = (c.w + c.chunk - 1) / c.chunk
	c.ch = (c.h + c.chunk - 1) / c.chunk
	c.seen = make([dynamic]bool, c.w * c.h)

	c.slots = c.cw * c.ch * c.chunk * c.chunk

	if gfx != nil {
		c.buf = new_subcell_buffer(device_proc(gfx), c.slots)
		set_cell_size(gfx, c.size, c.size)
	}
	cells_write_positions(c)
	return c
}

cells_write_positions :: proc(c: ^Cells) {
	if c.buf == nil || c.w == 0 || c.h == 0 {
		return
	}
	grid := make([dynamic]Subcell_Instance, c.slots)
	for y := 0; y < c.h; y += 1 {
		for x := 0; x < c.w; x += 1 {
			grid[cells_slot_of(c, x, y)] = Subcell_Instance{
				x = c.origin_x + (cast(f32) x + 0.5) * c.size,
				y = c.origin_y + (cast(f32) y + 0.5) * c.size,
			}
		}
	}
	instance_buffer_write_all(Subcell_Instance, c.buf, grid)
}

cells_slot_of :: proc(c: ^Cells, x, y: int) -> int {
	cx, cy := x / c.chunk, y / c.chunk
	chunk_start := (cy * c.cw + cx) * c.chunk * c.chunk
	return chunk_start + (y % c.chunk) * c.chunk + (x % c.chunk)
}

cells_touch :: proc(c: ^Cells, x, y: int) {
	if x < 0 || y < 0 || x >= c.w || y >= c.h {
		return
	}
	i := y * c.w + x
	for d in c.dirty {
		if d == cast(i32) i {
			return
		}
	}
	append(&c.dirty, cast(i32) i)
}

cells_touch_all :: proc(c: ^Cells) {
	c.all = true
}

cells_sync :: proc(c: ^Cells, materials: []u32) {
	c.stats.written = 0
	c.damaged = make([dynamic]View_Bounds, 0)
	if c.buf == nil || len(materials) < c.w * c.h {
		if len(materials) < c.w * c.h {
			logx.logger_error(g_log, "the materials array is smaller than the grid", "cells", c.w * c.h, "materials", len(materials))
		}
		return
	}

	if c.all {
		for y := 0; y < c.h; y += 1 {
			for x := 0; x < c.w; x += 1 {
				cells_write(c, x, y, materials[y * c.w + x])
			}
		}
		c.all = false
		cells_clear_dirty(c)
		return
	}

	for i in c.dirty {
		x, y := cast(int) i % c.w, cast(int) i / c.w
		cells_write(c, x, y, materials[i])
	}
	cells_clear_dirty(c)
}

cells_damage :: proc(c: ^Cells, x, y: int) {
	append(&c.damaged, View_Bounds{
		min_x = c.origin_x + cast(f32) x * c.size,
		min_y = c.origin_y + cast(f32) y * c.size,
		max_x = c.origin_x + cast(f32) (x + 1) * c.size,
		max_y = c.origin_y + cast(f32) (y + 1) * c.size,
	})
}

cells_damaged :: proc(c: ^Cells) -> [dynamic]View_Bounds {
	return c.damaged
}

cells_write :: proc(c: ^Cells, x, y: int, palette: u32) {
	inst := Subcell_Instance{
		x = c.origin_x + (cast(f32) x + 0.5) * c.size,
		y = c.origin_y + (cast(f32) y + 0.5) * c.size,
		palette = palette,
	}
	instance_buffer_write(Subcell_Instance, c.buf, cells_slot_of(c, x, y), &inst)
	cells_damage(c, x, y)
	c.stats.written += 1
}

cells_clear_dirty :: proc(c: ^Cells) {
	for i in c.dirty {
		c.seen[i] = false
	}
	c.dirty = make([dynamic]i32, 0)
}

cells_draw :: proc(c: ^Cells, view: View_Bounds) {
	c.stats.submitted = 0
	c.stats.draws = 0
	if c.buf == nil || c.w == 0 || c.h == 0 {
		return
	}

	batch := c.buf
	for r in cells_visible(c, view) {
		draw_subcells_range(c.gfx, batch, r.first, r.count)
		c.stats.submitted += r.count
		c.stats.draws += 1
	}
}

cells_visible :: proc(c: ^Cells, v: View_Bounds) -> [dynamic]Inst_Range {
	min_cx, min_cy := 0, 0
	max_cx, max_cy := c.cw - 1, c.ch - 1

	if v.min_x < v.max_x && v.min_y < v.max_y {
		min_cx = cells_chunk_at(c, v.min_x - c.origin_x, c.cw)
		max_cx = cells_chunk_at(c, v.max_x - c.origin_x, c.cw)
		min_cy = cells_chunk_at(c, v.min_y - c.origin_y, c.ch)
		max_cy = cells_chunk_at(c, v.max_y - c.origin_y, c.ch)
	}
	if min_cx > max_cx || min_cy > max_cy {
		return nil
	}

	area := c.chunk * c.chunk
	runs := make([dynamic]Inst_Range, 0)
	for cy := min_cy; cy <= max_cy; cy += 1 {
		first := (cy * c.cw + min_cx) * area
		append(&runs, Inst_Range{
			first = first,
			count = (max_cx - min_cx + 1) * area,
		})
	}
	return runs
}

cells_chunk_at :: proc(c: ^Cells, offset: f32, chunks: int) -> int {
	i := cast(int)(offset / (c.size * cast(f32) chunks))
	if i < 0 {
		return 0
	}
	if i >= chunks {
		return chunks - 1
	}
	return i
}

cells_stats :: proc(c: ^Cells) -> Cell_Stats {
	return c.stats
}

cells_release :: proc(c: ^Cells) {
	if c.buf != nil {
		instance_buffer_release(Subcell_Instance, c.buf)
	}
	c.buf = nil
}

// ============================================================================
// RampTable - palette for subcell instances
// ============================================================================

Ramp_Entries :: 1024

Ramp_Table :: struct {
	colors: [Ramp_Entries][4]f32,
}

ramp_table_set :: proc(t: ^Ramp_Table, material: int, r, g, b, a: f32) {
	if material < 0 || material >= Ramp_Entries {
		logx.logger_error(g_log, "material is outside the ramp table", "material", material, "entries", Ramp_Entries)
		return
	}
	t.colors[material] = [4]f32{r, g, b, a}
}

palette_of :: proc(material: int) -> u32 {
	return cast(u32) material + 1
}
