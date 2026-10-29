package render

import "aqwabor:logx"

// Stroke segment instances (72 bytes, matches WGSL Segment struct).
// Defined in gpu.odin as Stroke_Segment.

// Quad vertices for stroke expansion (unit quad corners).
stroke_quad_verts :: [4]Stroke_Quad_Vertex{
	{x = -1, y = -1},
	{x = 1, y = -1},
	{x = 1, y = 1},
	{x = -1, y = 1},
}

Stroke_Quad_Vertex :: struct {
	x, y: f32,
}

stroke_quad_indices :: [6]u16{0, 1, 2, 0, 2, 3}

stroke_quad_vertex_layout :: proc() -> Vertex_Buffer_Layout {
	attrs := make([dynamic]Vertex_Attribute, 1)
	attrs[0] = Vertex_Attribute{format = Vertex_Format_Float32x2, offset = 0, shader_location = 0}
	return Vertex_Buffer_Layout{
		array_stride = 8,
		step_mode = Vertex_Step_Mode_Vertex,
		attributes = attrs,
	}
}

stroke_segment_layout :: proc() -> Vertex_Buffer_Layout {
	attrs := make([dynamic]Vertex_Attribute, 8)
	attrs[0] = Vertex_Attribute{format = Vertex_Format_Float32x2, offset = 0,   shader_location = 0}
	attrs[1] = Vertex_Attribute{format = Vertex_Format_Float32x2, offset = 8,   shader_location = 1}
	attrs[2] = Vertex_Attribute{format = Vertex_Format_Float32x2, offset = 16,  shader_location = 2}
	attrs[3] = Vertex_Attribute{format = Vertex_Format_Float32x2, offset = 24,  shader_location = 3}
	attrs[4] = Vertex_Attribute{format = Vertex_Format_Float32x4, offset = 32,  shader_location = 4}
	attrs[5] = Vertex_Attribute{format = Vertex_Format_Float32x4, offset = 48,  shader_location = 5}
	attrs[6] = Vertex_Attribute{format = Vertex_Format_Float32,   offset = 64,  shader_location = 6}
	attrs[7] = Vertex_Attribute{format = Vertex_Format_Uint8x2,   offset = 68,  shader_location = 7}
	return Vertex_Buffer_Layout{
		array_stride = Stroke_Segment_Size,
		step_mode = Vertex_Step_Mode_Instance,
		attributes = attrs,
	}
}

// Stroke_Pipeline renders screen-space-width polylines via vertex-shader
// expansion of segment instances.
Stroke_Pipeline :: struct {
	pipe:   Render_Pipeline,
	pl:     Bind_Group_Layout,
	format: Texture_Format,

	quad_verts: Buffer,
	quad_idx:   Buffer,
}

new_stroke_pipeline :: proc(dev: Device, format: Texture_Format, cam_bgl: Bind_Group_Layout) -> ^Stroke_Pipeline {
	sp := &Stroke_Pipeline{
		format = format,
	}

	_vert_mod, err := dev_create_shader_module(dev, Shader_Module_Descriptor{
		label = "stroke vert",
		wgsl = stroke_vert_wgsl,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create stroke vertex shader module", "err", err)
		return nil
	}
	_ = _vert_mod

	_frag_mod: Shader_Module
	_frag_mod, err = dev_create_shader_module(dev, Shader_Module_Descriptor{
		label = "stroke frag",
		wgsl = instanced_frag_wgsl,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create stroke fragment shader module", "err", err)
		return nil
	}
	_ = _frag_mod

	sp.pl, err = dev_create_bind_group_layout(dev, Bind_Group_Layout_Descriptor{
		label = "stroke pll",
		entries = [dynamic]Bind_Group_Layout_Entry{},
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create stroke pipeline layout", "err", err)
		return nil
	}

	// Quad vertex buffer
	sp.quad_verts, err = dev_create_buffer(dev, Buffer_Descriptor{
		label = "stroke quad verts",
		size = cast(u64) len(stroke_quad_verts) * 8,
		usage = Buffer_Usage_Vertex,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create stroke quad vertex buffer", "err", err)
		return nil
	}

	// Quad index buffer
	sp.quad_idx, err = dev_create_buffer(dev, Buffer_Descriptor{
		label = "stroke quad idx",
		size = cast(u64) len(stroke_quad_indices) * 2,
		usage = Buffer_Usage_Index,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create stroke quad index buffer", "err", err)
		return nil
	}

	sp.pipe, err = dev_create_render_pipeline(dev, Render_Pipeline_Descriptor{
		label = "stroke pipeline",
		layout = sp.pl,
		vertex = Vertex_State{},
		fragment = nil,
		primitive = Primitive_State{topology = Primitive_Topology.Triangle_List},
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create stroke render pipeline", "err", err)
		return nil
	}

	return sp
}

stroke_pipeline_pipeline :: proc(sp: ^Stroke_Pipeline) -> Render_Pipeline {
	return sp.pipe
}

stroke_pipeline_quad_vertex_buffer :: proc(sp: ^Stroke_Pipeline) -> Buffer {
	return sp.quad_verts
}

stroke_pipeline_quad_index_buffer :: proc(sp: ^Stroke_Pipeline) -> Buffer {
	return sp.quad_idx
}

stroke_pipeline_release :: proc(sp: ^Stroke_Pipeline) {
	if sp == nil {
		return
	}
	if sp.pipe != nil {
		render_pipeline_release(sp.pipe)
	}
	if sp.pl != nil {
		bind_group_layout_release(sp.pl)
	}
	if sp.quad_verts != nil {
		buffer_release(sp.quad_verts)
	}
	if sp.quad_idx != nil {
		buffer_release(sp.quad_idx)
	}
}

// ============================================================================
// StrokeBuffer - GPU buffer for stroke segment instances
// ============================================================================

Stroke_Buffer :: struct {
	buffer:       Buffer,
	cpu_data:     [dynamic]Stroke_Segment,
	capacity:     int,
	dirty_ranges: [dynamic][2]int,
	count:        int,
}

new_stroke_buffer :: proc(dev: Device, capacity: int) -> ^Stroke_Buffer {
	size := cast(u64) capacity * Stroke_Segment_Size
	buf, err := dev_create_buffer(dev, Buffer_Descriptor{
		label = "stroke buffer",
		size = size,
		usage = buffer_usage_or(buffer_usage_or(Buffer_Usage_Vertex, Buffer_Usage_Copy_Dst), Buffer_Usage_Storage),
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create stroke buffer", "err", err)
		return nil
	}
	sb := new(Stroke_Buffer)
	sb.buffer = buf
	sb.cpu_data = make([dynamic]Stroke_Segment, capacity)
	sb.capacity = capacity
	return sb
}

stroke_buffer_write :: proc(sb: ^Stroke_Buffer, index: int, seg: ^Stroke_Segment) {
	if index < 0 || index >= sb.capacity {
		logx.logger_error(g_log, "stroke segment index out of bounds", "index", index)
		return
	}
	if sb.count <= index + 1 {
		sb.count = index + 1
	}
	sb.cpu_data[index] = seg^
	dr := sb.dirty_ranges
	append(&dr, [2]int{index, index + 1})
	sb.dirty_ranges = dr
}

stroke_buffer_write_all :: proc(sb: ^Stroke_Buffer, src: []Stroke_Segment) {
	n := len(src)
	if n > sb.capacity {
		logx.logger_error(g_log, "WriteAll: src exceeds stroke buffer capacity")
		return
	}
	copy(sb.cpu_data[:n], src)
	sb.count = n
	if n > 0 {
		dr := sb.dirty_ranges
		append(&dr, [2]int{0, n})
		sb.dirty_ranges = dr
	}
}

stroke_buffer_write_at :: proc(sb: ^Stroke_Buffer, start: int, src: []Stroke_Segment) {
	n := len(src)
	if n == 0 {
		return
	}
	if start < 0 || start + n > sb.capacity {
		logx.logger_error(g_log, "WriteAt: range exceeds stroke buffer capacity")
		return
	}
	copy(sb.cpu_data[start:start + n], src)
	end := start + n
	if sb.count < end {
		sb.count = end
	}
	dr := sb.dirty_ranges
	append(&dr, [2]int{start, end})
	sb.dirty_ranges = dr
}

stroke_buffer_flush :: proc(sb: ^Stroke_Buffer, queue: Queue) {
	if len(sb.dirty_ranges) == 0 {
		return
	}

	merged := merge_stroke_ranges(sb.dirty_ranges)

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
		byte_start := cast(u64) start * Stroke_Segment_Size
		byte_size := cast(u64) (end - start) * Stroke_Segment_Size
		_ = queue_write_buffer(queue, sb.buffer, byte_start, []u8{})
	}

	sb.dirty_ranges = make([dynamic][2]int, 0)
}

stroke_buffer_reset :: proc(sb: ^Stroke_Buffer) {
	sb.count = 0
	sb.dirty_ranges = make([dynamic][2]int, 0)
}

stroke_buffer_set_count :: proc(sb: ^Stroke_Buffer, n: int) {
	if n < 0 || n > sb.capacity {
		logx.logger_error(g_log, "SetCount: out of range", "n", n)
		return
	}
	sb.count = n
}

stroke_buffer_release :: proc(sb: ^Stroke_Buffer) {
	if sb == nil {
		return
	}
	if sb.buffer != nil {
		buffer_release(sb.buffer)
	}
}

stroke_buffer_buffer :: proc(sb: ^Stroke_Buffer) -> Buffer {
	return sb.buffer
}

stroke_buffer_count :: proc(sb: ^Stroke_Buffer) -> int {
	return sb.count
}

stroke_buffer_capacity :: proc(sb: ^Stroke_Buffer) -> int {
	return sb.capacity
}

merge_stroke_ranges :: proc(ranges: [dynamic][2]int) -> [dynamic][2]int {
	if len(ranges) == 0 {
		return nil
	}
	for i in 1 ..< len(ranges) {
		for j := i; j > 0 && ranges[j][0] < ranges[j - 1][0]; j -= 1 {
			ranges[j], ranges[j - 1] = ranges[j - 1], ranges[j]
		}
	}

	out := make([dynamic][2]int, 1, len(ranges))
	out[0] = ranges[0]
	for r in ranges[1:] {
		last := &out[len(out) - 1]
		if r[0] <= last[1] {
			if r[1] > last[1] {
				last[1] = r[1]
			}
		} else {
			o := out
			append(&o, r)
			out = o
		}
	}
	return out
}

// WGSL shader source strings (embedded from Go shaders/)
stroke_vert_wgsl :: `
// Stroke vertex shader: expands segment instances into screen-space quads.
//
// Each instance is one line segment with adjacency data for miter joins.
// The 4 vertices of a unit quad (slot 0) are offset by +/-normal*halfWidth
// along the segment, producing a screen-space-width polyline.
//
// Bindings:
//   group(0) binding(0) = Camera uniform (viewProj + viewport)

struct Camera {
    viewProj: mat4x4<f32>,
    viewport: vec2<f32>,
};

@group(0) @binding(0) var<uniform> camera: Camera;

// Segment instance (slot 1).  Must match Go StrokeSegment (72 bytes).
struct Segment {
    p0:     vec2<f32>,
    p1:     vec2<f32>,
    prev:   vec2<f32>,
    next:   vec2<f32>,
    color0: vec4<f32>,
    color1: vec4<f32>,
    width:  f32,
    flags:  u32,   // low 8 bits: 0=pixels, 1=world
    layer:  u32,
    _pad:   vec2<u32>,
};

struct VSOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) uv:    vec2<f32>,
};

fn toScreen(world: vec2<f32>) -> vec2<f32> {
    let clip = camera.viewProj * vec4<f32>(world, 0.0, 1.0);
    return vec2<f32>(
        (clip.x / clip.w * 0.5 + 0.5) * camera.viewport.x,
        (1.0 - (clip.y / clip.w * 0.5 + 0.5)) * camera.viewport.y,
    );
}

fn screenDir(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let sa = toScreen(a);
    let sb = toScreen(b);
    let d = sb - sa;
    let len = length(d);
    if (len < 0.001) {
        return vec2<f32>(1.0, 0.0);
    }
    return d / len;
}

fn screenNormal(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let d = screenDir(a, b);
    return vec2<f32>(-d.y, d.x);
}

@vertex
fn vs_main(
    @location(8) quadVert:  vec2<f32>,
    @location(0) segP0:     vec2<f32>,
    @location(1) segP1:     vec2<f32>,
    @location(2) segPrev:   vec2<f32>,
    @location(3) segNext:   vec2<f32>,
    @location(4) segColor0: vec4<f32>,
    @location(5) segColor1: vec4<f32>,
    @location(6) segWidth:  f32,
    @location(7) segFlags:  vec2<u32>,
) -> VSOut {
    var out: VSOut;

    let n0 = screenNormal(segPrev, segP0);
    let n1 = screenNormal(segP1, segNext);
    let ns = screenNormal(segP0, segP1);

    let nMiter0 = normalize(n0 + ns);
    let nMiter1 = normalize(ns + n1);

    let miterLen0 = min(1.0 / max(dot(nMiter0, ns), 0.01), 2.0);
    let miterLen1 = min(1.0 / max(dot(nMiter1, ns), 0.01), 2.0);

    let halfW = segWidth * 0.5;

    let side = quadVert.x;
    let endT = (quadVert.y + 1.0) * 0.5;

    let centerWorld = mix(segP0, segP1, endT);
    let centerClip = camera.viewProj * vec4<f32>(centerWorld, 0.0, 1.0);

    let n = mix(nMiter0, nMiter1, endT);
    let miterL = mix(miterLen0, miterLen1, endT);

    let offset = side * n * halfW * miterL;
    let clipOffset = vec2<f32>(
        offset.x / (camera.viewport.x * 0.5),
        -offset.y / (camera.viewport.y * 0.5),
    );

    out.pos = vec4<f32>(
        centerClip.xy + clipOffset * centerClip.w,
        centerClip.zw,
    );

    out.color = mix(segColor0, segColor1, endT);
    out.uv = vec2<f32>(side * 0.5 + 0.5, endT);

    return out;
}
`

instanced_frag_wgsl :: `
struct VSOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) color: vec4<f32>,
};

@fragment
fn fs_main(in: VSOut) -> @location(0) vec4<f32> {
    return in.color;
}
`

// BuildSegments converts a polyline into StrokeSegments with adjacency.
build_segments :: proc(points: [dynamic][2]f32, color: [4]f32, width: f32, flags: u8, layer: u8) -> [dynamic]Stroke_Segment {
	n := len(points)
	if n < 2 {
		return nil
	}
	segs := make([dynamic]Stroke_Segment, 0)
	for i in 0 ..< n - 1 {
		prev := points[i]
		if i > 0 {
			prev = points[i - 1]
		}
		next := points[i + 1]
		if i + 2 < n {
			next = points[i + 2]
		}
		s := segs
		append_elems(&s, Stroke_Segment{
			p0 = points[i],
			p1 = points[i + 1],
			prev = prev,
			next = next,
			color0 = color,
			color1 = color,
			width = width,
			flags = flags,
			layer = layer,
		})
		segs = s
	}
	return segs
}
