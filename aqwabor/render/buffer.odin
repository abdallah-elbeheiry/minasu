package render

import "aqwabor:logx"

// ============================================================================
// Generic instance buffer with dirty-range tracking
// ============================================================================

Instance_Buffer_Of :: struct($T: typeid) {
	dev:          Device,
	stride:       int,
	label:        string,
	buffer:       Buffer,
	cpu_data:     [dynamic]T,
	capacity:     int,
	dirty_ranges: [dynamic][2]int,
	count:        int,
	retired:      [dynamic]^Retired_Buffer,
	frame:        u64,
}

Retired_Buffer :: struct {
	buf:  Buffer,
	frame: u64,
}

buffer_retire_after :: 3

new_instance_buffer_of :: proc($T: typeid, dev: Device, capacity: int, label: string, allocator := context.allocator) -> ^Instance_Buffer_Of(T) {
	stride := cast(int) size_of(T)
	buf, err := dev_create_buffer(dev, Buffer_Descriptor{
		label = label,
		size  = cast(u64) capacity * cast(u64) stride,
		usage = buffer_usage_or(buffer_usage_or(Buffer_Usage_Vertex, Buffer_Usage_Copy_Dst), Buffer_Usage_Storage),
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create instance buffer", "label", label, "err", err)
		return nil
	}
	ib := new(Instance_Buffer_Of(T))
	ib.dev = dev
	ib.stride = stride
	ib.label = label
	ib.buffer = buf
	ib.cpu_data = make([dynamic]T, capacity, allocator)
	ib.capacity = capacity
	ib.dirty_ranges = make([dynamic][2]int, 0, 8, allocator)
	return ib
}

instance_buffer_grow :: proc($T: typeid, ib: ^Instance_Buffer_Of(T), n: int) -> bool {
	if n <= ib.capacity {
		return true
	}
	if ib.dev == nil {
		logx.logger_error(g_log, "instance buffer cannot grow without a device", "want", n, "capacity", ib.capacity)
		return false
	}

	capacity := max(ib.capacity, 1)
	for capacity < n {
		capacity *= 2
	}

	buf, err := dev_create_buffer(ib.dev, Buffer_Descriptor{
		label = ib.label,
		size  = cast(u64) capacity * cast(u64) ib.stride,
		usage = buffer_usage_or(buffer_usage_or(Buffer_Usage_Vertex, Buffer_Usage_Copy_Dst), Buffer_Usage_Storage),
	})
	if err != "" {
		logx.logger_error(g_log, "failed to grow instance buffer", "capacity", capacity, "err", err)
		return false
	}

	if ib.buffer != nil {
		rb := new(Retired_Buffer)
		rb.buf = ib.buffer
		rb.frame = ib.frame
		ib.retired = append_retired(ib.retired, rb)
	}
	ib.buffer = buf

	grown := make([dynamic]T, capacity)
	for i in 0 ..< ib.count {
		grown[i] = ib.cpu_data[i]
	}
	ib.cpu_data = grown
	ib.capacity = capacity
	return true
}

append_retired :: proc(retired: [dynamic]^Retired_Buffer, rb: ^Retired_Buffer) -> [dynamic]^Retired_Buffer {
	r := retired
	append_elems(&r, rb)
	return r
}

instance_buffer_begin_frame :: proc($T: typeid, ib: ^Instance_Buffer_Of(T)) {
	ib.dirty_ranges = make([dynamic][2]int, 0)
	ib.count = 0
}

instance_buffer_release :: proc($T: typeid, ib: ^Instance_Buffer_Of(T)) {
	if ib.buffer != nil {
		buffer_release(ib.buffer)
	}
}

instance_buffer_write :: proc($T: typeid, ib: ^Instance_Buffer_Of(T), index: int, data: ^T) {
	if index < 0 {
		logx.logger_error(g_log, "instance index is negative", "index", index)
		return
	}
	if index >= ib.capacity && !instance_buffer_grow(T, ib, index + 1) {
		return
	}
	ib.cpu_data[index] = data^
	if ib.count <= index + 1 {
		ib.count = index + 1
	}
	dr := ib.dirty_ranges
	append_elems(&dr, [2]int{index, index + 1})
	ib.dirty_ranges = dr
}

instance_buffer_write_all :: proc($T: typeid, ib: ^Instance_Buffer_Of(T), src: [dynamic]T) {
	n := len(src)
	if n > ib.capacity && !instance_buffer_grow(T, ib, n) {
		return
	}
	for i in 0 ..< n {
		ib.cpu_data[i] = src[i]
	}
	ib.count = n
	if n > 0 {
		dr := ib.dirty_ranges
		append_elems(&dr, [2]int{0, n})
		ib.dirty_ranges = dr
	}
}

instance_buffer_write_at :: proc($T: typeid, ib: ^Instance_Buffer_Of(T), start: int, src: []T) {
	n := len(src)
	if n == 0 {
		return
	}
	if start < 0 {
		logx.logger_error(g_log, "instance write starts before zero", "start", start)
		return
	}
	if start + n > ib.capacity && !instance_buffer_grow(ib, start + n) {
		return
	}
	for i in 0 ..< n {
		ib.cpu_data[start + i] = src[i]
	}
	end := start + n
	if ib.count < end {
		ib.count = end
	}
	dr := ib.dirty_ranges
	append_elems(&dr, [2]int{start, end})
	ib.dirty_ranges = dr
}

instance_buffer_flush :: proc($T: typeid, ib: ^Instance_Buffer_Of(T), queue: Queue) {
	if len(ib.dirty_ranges) == 0 {
		return
	}

	merged := merge_stroke_ranges(ib.dirty_ranges)

	if len(merged) > 8 {
		min_start, max_end := merged[0][0], merged[0][1]
		dirty := 0
		for r in merged {
			if r[0] < min_start {
				min_start = r[0]
			}
			if r[1] > max_end {
				max_end = r[1]
			}
			dirty += r[1] - r[0]
		}
		span := max_end - min_start
		if span > 0 && dirty * 2 >= span {
			merged = make([dynamic][2]int, 1)
			merged[0] = [2]int{min_start, max_end}
		}
	}

	for r in merged {
		start, end := r[0], r[1]
		byte_start := cast(u64) start * cast(u64) ib.stride
		byte_size := cast(u64) (end - start) * cast(u64) ib.stride
		_ = queue_write_buffer(queue, ib.buffer, byte_start, []u8{})
	}

	ib.dirty_ranges = make([dynamic][2]int, 0)
}

instance_buffer_reset :: proc($T: typeid, ib: ^Instance_Buffer_Of(T)) {
	ib.count = 0
	ib.dirty_ranges = make([dynamic][2]int, 0)
}

instance_buffer_set_count :: proc($T: typeid, ib: ^Instance_Buffer_Of(T), n: int) {
	if n < 0 || n > ib.capacity {
		logx.logger_error(g_log, "SetCount: out of range", "n", n)
		return
	}
	ib.count = n
}

Instance_Buffer :: Instance_Buffer_Of(Instance_Data)
Subcell_Buffer :: Instance_Buffer_Of(Subcell_Instance)

new_instance_buffer :: proc(dev: Device, capacity: int, allocator := context.allocator) -> ^Instance_Buffer {
	return new_instance_buffer_of(Instance_Data, dev, capacity, "instance buffer", allocator)
}

new_subcell_buffer :: proc(dev: Device, capacity: int, allocator := context.allocator) -> ^Subcell_Buffer {
	return new_instance_buffer_of(Subcell_Instance, dev, capacity, "subcell buffer", allocator)
}

instance_buffer_count :: proc($T: typeid, ib: ^Instance_Buffer_Of(T)) -> int {
	return ib.count
}
