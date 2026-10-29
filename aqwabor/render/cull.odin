package render

import "aqwabor:logx"

// ============================================================================
// Compute cull pipeline and indirect draw support
// ============================================================================

Indirect_Cmd :: struct {
	index_count:    u32,
	instance_count: u32,
	first_index:    u32,
	base_vertex:    i32,
	first_instance: u32,
}

indirect_cmd_size :: 20

cull_slots :: 8
slot_stride :: 256

Cull_Params :: struct {
	instance_count: u32,
	output_base:    u32,
	input_base:     u32,
	_pad:           u32,
	min_bounds:     [2]f32,
	max_bounds:     [2]f32,
}

cull_params_size :: 32

max_cull_bytes :: 128 << 20
instance_data_size :: Instance_Data_Size

Cull_Pipeline :: struct {
	dev:           Device,
	queue:         Queue,
	pipe:          Compute_Pipeline,
	bgl:           Bind_Group_Layout,
	pl:            Bind_Group_Layout,
	indirect_buf:  Buffer,
	output_buf:    Buffer,
	params_buf:    Buffer,
	max_instances: int,

	used:  int,
	base:  [cull_slots]int,

	cached: [cull_slots]^Slot_Binding,
	next:   int,
}

Slot_Binding :: struct {
	indirect_offset: u64,
	params_offset:   u64,
}

new_cull_pipeline :: proc(dev: Device, queue: Queue, max_instances: int) -> ^Cull_Pipeline {
	mi := max_instances
	if mi > max_cull_bytes / instance_data_size {
		logx.logger_warn(g_log, "cull capped at storage buffer limit", "asked", mi, "capped", max_cull_bytes / instance_data_size)
		mi = max_cull_bytes / instance_data_size
	}

	cp := &Cull_Pipeline{
		dev = dev,
		queue = queue,
		max_instances = mi,
		used = 0,
		next = 0,
	}

	for i in 0 ..< cull_slots {
		cp.base[i] = 0
		cp.cached[i] = nil
	}

	indirect_size := cast(u64) slot_stride * cull_slots
	ib, err := dev_create_buffer(dev, Buffer_Descriptor{
		label = "cull indirect",
		size = indirect_size,
		usage = buffer_usage_or(buffer_usage_or(Buffer_Usage_Storage, Buffer_Usage_Indirect), Buffer_Usage_Copy_Dst),
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create cull indirect buffer", "err", err)
		return nil
	}
	cp.indirect_buf = ib

	params_size := cast(u64) slot_stride * cull_slots
	pb: Buffer
	pb, err = dev_create_buffer(dev, Buffer_Descriptor{
		label = "cull params",
		size = params_size,
		usage = buffer_usage_or(Buffer_Usage_Storage, Buffer_Usage_Copy_Dst),
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create cull params buffer", "err", err)
		return nil
	}
	cp.params_buf = pb

	out_size := cast(u64) mi * instance_data_size
	ob: Buffer
	ob, err = dev_create_buffer(dev, Buffer_Descriptor{
		label = "cull output",
		size = out_size,
		usage = buffer_usage_or(Buffer_Usage_Storage, Buffer_Usage_Copy_Dst),
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create cull output buffer", "err", err)
		return nil
	}
	cp.output_buf = ob

	return cp
}

cull_release :: proc(cp: ^Cull_Pipeline) {
	if cp == nil {
		return
	}
	if cp.indirect_buf != nil {
		buffer_release(cp.indirect_buf)
	}
	if cp.output_buf != nil {
		buffer_release(cp.output_buf)
	}
	if cp.params_buf != nil {
		buffer_release(cp.params_buf)
	}
}

cull_begin_frame :: proc(cp: ^Cull_Pipeline) {
	cp.used = 0
	cp.next = 0
}

cull_fits :: proc(cp: ^Cull_Pipeline, n: int) -> bool {
	return cp.next + n <= cull_slots && cp.used + n <= cp.max_instances
}

cull_claim :: proc(cp: ^Cull_Pipeline, n: int) -> (slot: int, ok: bool) {
	if cp.next >= cull_slots || cp.used + n > cp.max_instances {
		return -1, false
	}
	slot = cp.next
	cp.next += n
	cp.used += n
	return slot, true
}

cull_slots_left :: proc(cp: ^Cull_Pipeline) -> int {
	return cull_slots - cp.next
}

cull_reset_indirect :: proc(cp: ^Cull_Pipeline, slot: int, index_count: u32) {
	cmd := Indirect_Cmd{
		index_count = index_count,
		instance_count = 0,
		first_index = 0,
		base_vertex = 0,
		first_instance = 0,
	}
	_ = cmd
	_ = queue_write_buffer(cp.queue, cp.indirect_buf, cast(u64) slot * slot_stride, nil)
}

cull_encode_dispatch :: proc(cp: ^Cull_Pipeline, enc: Command_Encoder, slot: int, instance_buffer: Buffer, camera_buffer: Buffer, first: int, count: int, min_bounds: [2]f32, max_bounds: [2]f32) {
	_ = cp
	_ = enc
	_ = slot
	_ = instance_buffer
	_ = camera_buffer
	_ = first
	_ = count
	_ = min_bounds
	_ = max_bounds
}

cull_claim_slot :: proc(cp: ^Cull_Pipeline) -> int {
	if cp.next >= cull_slots {
		return -1
	}
	slot := cp.next
	cp.next += 1
	return slot
}
