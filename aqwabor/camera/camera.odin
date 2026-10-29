package camera

import "aqwabor:ecs"

Camera :: struct {
	x, y:     f32,
	zoom:     f32,
	min_zoom: f32,
	max_zoom: f32,
	active:   u8,
}

register_ecs :: proc(w: ^ecs.World) -> (ecs.Comp(Camera), ecs.Error) {
	return ecs.register(w, Camera)
}

must_register_ecs :: proc(w: ^ecs.World) -> ecs.Comp(Camera) {
	c, err := register_ecs(w)
	if err != .None {
		panic(ecs.error_string(err))
	}
	return c
}

// view_proj_array is a column-major 4x4 matching the Go engine: world Y down,
// clip Y up, camera position at clip 0 on both axes.
view_proj_array :: proc(c: Camera, vp_w, vp_h: f32) -> [16]f32 {
	zoom := c.zoom
	if zoom == 0 { zoom = 1 }
	vp_w := vp_w
	vp_h := vp_h
	if vp_w == 0 { vp_w = 1 }
	if vp_h == 0 { vp_h = 1 }
	sx := zoom * 2 / vp_w
	sy := -zoom * 2 / vp_h
	tx := -c.x * zoom * 2 / vp_w
	ty := c.y * zoom * 2 / vp_h
	return [16]f32{
		sx, 0, 0, 0,
		0, sy, 0, 0,
		0, 0, 1, 0,
		tx, ty, 0, 1,
	}
}

clamp_zoom :: proc(c: ^Camera) {
	if c.min_zoom > 0 && c.zoom < c.min_zoom {
		c.zoom = c.min_zoom
	}
	if c.max_zoom > 0 && c.zoom > c.max_zoom {
		c.zoom = c.max_zoom
	}
}

pan :: proc(c: ^Camera, dx, dy: f32) {
	if c.zoom == 0 { return }
	inv := 1 / c.zoom
	c.x -= dx * inv
	c.y -= dy * inv
}

zoom_at :: proc(c: ^Camera, factor, cursor_x, cursor_y, vp_w, vp_h: f32) {
	bx := (cursor_x - vp_w / 2) / c.zoom + c.x
	by := (cursor_y - vp_h / 2) / c.zoom + c.y
	c.zoom *= factor
	clamp_zoom(c)
	ax := (cursor_x - vp_w / 2) / c.zoom + c.x
	ay := (cursor_y - vp_h / 2) / c.zoom + c.y
	c.x += bx - ax
	c.y += by - ay
}

fit :: proc(c: ^Camera, world_w, world_h, vp_w, vp_h: f32) {
	if world_w > 0 && world_h > 0 && vp_w > 0 && vp_h > 0 {
		c.zoom = min(vp_w / world_w, vp_h / world_h)
	} else {
		c.zoom = 1
	}
	clamp_zoom(c)
	c.x = world_w / 2
	c.y = world_h / 2
}

clamp_to_bounds :: proc(c: ^Camera, world_w, world_h, vp_w, vp_h: f32) {
	if c.zoom == 0 { return }
	visible_w := vp_w / c.zoom
	visible_h := vp_h / c.zoom
	if visible_w >= world_w {
		c.x = world_w / 2
	} else {
		c.x = clamp(c.x, visible_w / 2, world_w - visible_w / 2)
	}
	if visible_h >= world_h {
		c.y = world_h / 2
	} else {
		c.y = clamp(c.y, visible_h / 2, world_h - visible_h / 2)
	}
}

world_to_local :: proc(c: Camera, wx, wy, vp_w, vp_h: f32) -> (f32, f32) {
	lx := (wx - c.x) * c.zoom + vp_w / 2
	ly := (wy - c.y) * c.zoom + vp_h / 2
	return lx, ly
}

local_to_world :: proc(c: Camera, lx, ly, vp_w, vp_h: f32) -> (f32, f32) {
	wx := (lx - vp_w / 2) / c.zoom + c.x
	wy := (ly - vp_h / 2) / c.zoom + c.y
	return wx, wy
}
