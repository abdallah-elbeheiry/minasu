package render

import "aqwabor:logx"

// Mesh is a shared, immutable geometry (vertex + index buffers).
Mesh :: struct {
	vertex_buffer: Buffer,
	index_buffer:  Buffer,
	index_count:   u32,
}

new_mesh :: proc(dev: Device, queue: Queue, vertices: []Mesh_Vertex, indices: []u32) -> ^Mesh {
	if len(vertices) == 0 || len(indices) == 0 {
		logx.logger_error(g_log, "mesh requires at least one vertex and one index")
		return nil
	}

	vert_buf, err := dev_create_buffer(dev, Buffer_Descriptor{
		label = "mesh vertices",
		size  = cast(u64) len(vertices) * Mesh_Vertex_Size,
		usage = buffer_usage_or(Buffer_Usage_Vertex, Buffer_Usage_Copy_Dst),
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create mesh vertex buffer", "err", err)
		return nil
	}
	vert_bytes := vertex_bytes(vertices)
	if err := queue_write_buffer(queue, vert_buf, 0, vert_bytes); err != "" {
		logx.logger_error(g_log, "failed to write mesh vertex buffer", "err", err)
		return nil
	}

	idx_buf: Buffer
	idx_buf, err = dev_create_buffer(dev, Buffer_Descriptor{
		label = "mesh indices",
		size  = cast(u64) len(indices) * 4,
		usage = buffer_usage_or(Buffer_Usage_Index, Buffer_Usage_Copy_Dst),
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create mesh index buffer", "err", err)
		return nil
	}
	idx_bytes := index_bytes(indices)
	if err := queue_write_buffer(queue, idx_buf, 0, idx_bytes); err != "" {
		logx.logger_error(g_log, "failed to write mesh index buffer", "err", err)
		return nil
	}

	m := new(Mesh)
	m.vertex_buffer = vert_buf
	m.index_buffer = idx_buf
	m.index_count = cast(u32) len(indices)
	return m
}

new_unit_quad :: proc(dev: Device, queue: Queue) -> ^Mesh {
	vertices := []Mesh_Vertex{
		{x = -0.5, y = -0.5, r = 1, g = 1, b = 1, a = 1},
		{x = 0.5, y = -0.5, r = 1, g = 1, b = 1, a = 1},
		{x = 0.5, y = 0.5, r = 1, g = 1, b = 1, a = 1},
		{x = -0.5, y = 0.5, r = 1, g = 1, b = 1, a = 1},
	}
	indices := []u32{0, 1, 2, 0, 2, 3}
	return new_mesh(dev, queue, vertices, indices)
}

mesh_release :: proc(m: ^Mesh) {
	if m == nil {
		return
	}
	if m.vertex_buffer != nil {
		buffer_release(m.vertex_buffer)
	}
	if m.index_buffer != nil {
		buffer_release(m.index_buffer)
	}
}

vertex_bytes :: proc(verts: []Mesh_Vertex) -> []u8 {
	b := make([]u8, len(verts) * Mesh_Vertex_Size)
	for i in 0 ..< len(verts) {
		v := verts[i]
		off := i * Mesh_Vertex_Size
		put_f32(b[off:], v.x)
		put_f32(b[off + 4:], v.y)
		put_f32(b[off + 8:], v.r)
		put_f32(b[off + 12:], v.g)
		put_f32(b[off + 16:], v.b)
		put_f32(b[off + 20:], v.a)
	}
	return b
}

index_bytes :: proc(indices: []u32) -> []u8 {
	b := make([]u8, len(indices) * 4)
	for i in 0 ..< len(indices) {
		idx := indices[i]
		off := i * 4
		b[off] = cast(u8) idx
		b[off + 1] = cast(u8) (idx >> 8)
		b[off + 2] = cast(u8) (idx >> 16)
		b[off + 3] = cast(u8) (idx >> 24)
	}
	return b
}

put_f32 :: proc(b: []u8, v: f32) {
	bits := cast(u32) v
	b[0] = cast(u8) bits
	b[1] = cast(u8) (bits >> 8)
	b[2] = cast(u8) (bits >> 16)
	b[3] = cast(u8) (bits >> 24)
}
