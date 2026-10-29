package render

// SpriteBatch wraps an InstanceBuffer for sprite rendering.
Sprite_Batch :: struct {
	mesh: ^Mesh,
	buf:  ^Instance_Buffer,
}

new_sprite_batch :: proc(dev: Device, queue: Queue, mesh: ^Mesh, capacity: int, allocator := context.allocator) -> ^Sprite_Batch {
	m := mesh
	if m == nil {
		m = new_unit_quad(dev, queue)
	}
	sb := new(Sprite_Batch)
	sb.mesh = m
	sb.buf = new_instance_buffer(dev, capacity, allocator)
	return sb
}

sprite_batch_set :: proc(sb: ^Sprite_Batch, index: int, sprite: Instance_Data) {
	s := sprite
	instance_buffer_write(Instance_Data, sb.buf, index, &s)
}

sprite_batch_set_all :: proc(sb: ^Sprite_Batch, sprites: [dynamic]Instance_Data) {
	instance_buffer_write_all(Instance_Data, sb.buf, sprites)
}

sprite_batch_count :: proc(sb: ^Sprite_Batch) -> int {
	return sb.buf.count
}

sprite_batch_capacity :: proc(sb: ^Sprite_Batch) -> int {
	return sb.buf.capacity
}

sprite_batch_begin_frame :: proc(sb: ^Sprite_Batch) {
	instance_buffer_begin_frame(Instance_Data, sb.buf)
}

sprite_batch_reset :: proc(sb: ^Sprite_Batch) {
	instance_buffer_reset(Instance_Data, sb.buf)
}

sprite_batch_mesh :: proc(sb: ^Sprite_Batch) -> ^Mesh {
	return sb.mesh
}

sprite_batch_buffer :: proc(sb: ^Sprite_Batch) -> ^Instance_Buffer {
	return sb.buf
}

sprite_batch_release :: proc(sb: ^Sprite_Batch) {
	if sb == nil {
		return
	}
	if sb.mesh != nil {
		mesh_release(sb.mesh)
		sb.mesh = nil
	}
	if sb.buf != nil {
		instance_buffer_release(Instance_Data, sb.buf)
		sb.buf = nil
	}
}
