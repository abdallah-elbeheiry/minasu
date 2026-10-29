package render

import "aqwabor:logx"

// ============================================================================
// Renderer - owns the per-frame render pass and all draw pipelines
// ============================================================================

Frame_Stats :: struct {
	draw_calls:  int,
	instances:   int,
	triangles:   int,
}

Camera_Group :: struct {
	buf:  Buffer,
	bgl:  Bind_Group_Layout,
	bg:   Bind_Group,
}

new_camera_group :: proc(dev: Device) -> ^Camera_Group {
	c := &Camera_Group{}

	buf, err := dev_create_buffer(dev, Buffer_Descriptor{
		label = "camera uniform",
		size  = Camera_Uniform_Size,
		usage = buffer_usage_or(Buffer_Usage_Uniform, Buffer_Usage_Copy_Dst),
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create camera uniform buffer", "err", err)
		return nil
	}
	c.buf = buf

	camera_bgl_entries := make([dynamic]Bind_Group_Layout_Entry, 1)
	camera_bgl_entries[0] = Bind_Group_Layout_Entry{binding = 0, visibility = 1 | 2, buffer = Buffer_Binding_Layout{type = 0}}
	c.bgl, err = dev_create_bind_group_layout(dev, Bind_Group_Layout_Descriptor{
		label = "camera bgl",
		entries = camera_bgl_entries,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create camera bind group layout", "err", err)
		return nil
	}

	camera_bg_entries := make([dynamic]Bind_Group_Entry, 1)
	camera_bg_entries[0] = Bind_Group_Entry{binding = 0, buffer = c.buf, size = Camera_Uniform_Size}
	c.bg, err = dev_create_bind_group(dev, Bind_Group_Descriptor{
		label = "camera bg",
		layout = c.bgl,
		entries = camera_bg_entries,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create camera bind group", "err", err)
		return nil
	}

	return c
}

camera_group_update :: proc(c: ^Camera_Group, queue: Queue, view_proj: [16]f32, viewport_w, viewport_h: f32) {
	u := Camera_Uniform{
		view_proj = view_proj,
		viewport  = [2]f32{viewport_w, viewport_h},
	}
	src := []u8{}
	_ = queue_write_buffer(queue, c.buf, 0, src)
}

camera_group_release :: proc(c: ^Camera_Group) {
	if c == nil {
		return
	}
	if c.bg != nil {
		bind_group_release(c.bg)
	}
	if c.bgl != nil {
		bind_group_layout_release(c.bgl)
	}
	if c.buf != nil {
		buffer_release(c.buf)
	}
}

// Pipeline manages a single instanced render pipeline.
Pipeline :: struct {
	pipe:   Render_Pipeline,
	pl:     Bind_Group_Layout,
	format: Texture_Format,
}

new_pipeline :: proc(dev: Device, format: Texture_Format, cam_bgl: Bind_Group_Layout) -> ^Pipeline {
	p := &Pipeline{format = format}
	p_create(p, dev, cam_bgl)
	return p
}

p_create :: proc(p: ^Pipeline, dev: Device, cam_bgl: Bind_Group_Layout) {
	_vert_mod, err := dev_create_shader_module(dev, Shader_Module_Descriptor{
		label = "instanced vert",
		wgsl  = instanced_vert_wgsl,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create instanced vertex shader module", "err", err)
		return
	}
	_ = _vert_mod

	_frag_mod := Shader_Module(nil)
	_frag_mod, err = dev_create_shader_module(dev, Shader_Module_Descriptor{
		label = "instanced frag",
		wgsl  = instanced_frag_wgsl,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create instanced fragment shader module", "err", err)
		return
	}
	_ = _frag_mod

	entries := make([dynamic]Bind_Group_Layout_Entry, 1)
	entries[0] = Bind_Group_Layout_Entry{binding = 0, visibility = 1 | 2, buffer = Buffer_Binding_Layout{type = 0}}
	p.pl, err = dev_create_bind_group_layout(dev, Bind_Group_Layout_Descriptor{
		label = "instanced pll",
		entries = entries,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create instanced pipeline layout", "err", err)
		return
	}

	vbufs := make([dynamic]Vertex_Buffer_Layout, 2)
	vbufs[0] = mesh_vertex_layout()
	vbufs[1] = instance_buffer_layout()
	cts := make([dynamic]Color_Target_State, 1)
	cts[0] = Color_Target_State{
		format = p.format,
		blend = Blend_Alpha(),
		write_mask = Color_Write_Mask.All,
	}
	p.pipe, err = dev_create_render_pipeline(dev, Render_Pipeline_Descriptor{
		label = "instanced pipeline",
		layout = p.pl,
		vertex = Vertex_State{
			buffers = vbufs,
		},
		fragment = &Fragment_State{
			targets = cts,
		},
		primitive = Primitive_State{topology = Primitive_Topology.Triangle_List},
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create instanced render pipeline", "err", err)
		return
	}
}

pipeline_pipeline :: proc(p: ^Pipeline) -> Render_Pipeline {
	return p.pipe
}

pipeline_release :: proc(p: ^Pipeline) {
	if p == nil {
		return
	}
	if p.pipe != nil {
		render_pipeline_release(p.pipe)
	}
	if p.pl != nil {
		bind_group_layout_release(p.pl)
	}
}

// SubcellPipeline draws the compact instances.
Subcell_Pipeline :: struct {
	pipe:      Render_Pipeline,
	bgl:       Bind_Group_Layout,
	pl:        Bind_Group_Layout,
	ramp_buf:  Buffer,
	cell_buf:  Buffer,
	bind_group: Bind_Group,
	format:    Texture_Format,
	mesh:      ^Mesh,
}

cell_uniform :: struct {
	size: [2]f32,
	_pad: [8]u8,
}

cell_uniform_size :: 16

subcell_vert_wgsl :: `
struct Camera {
    viewProj: mat4x4<f32>,
    viewport: vec2<f32>,
};

struct Ramp {
    colors: array<vec4<f32>, 1024>,
};

struct Cell {
    size: vec2<f32>,
};

@group(0) @binding(0) var<uniform> camera: Camera;
@group(1) @binding(0) var<uniform> ramp:   Ramp;
@group(1) @binding(1) var<uniform> cell:   Cell;

struct VSIn {
    @location(0) pos: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) instancePos: vec2<f32>,
    @location(3) instancePalette: u32,
};

struct VSOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) uv: vec2<f32>,
};

@vertex
fn vs_main(in: VSIn) -> VSOut {
    var out: VSOut;

    if (in.instancePalette == 0u) {
        out.pos = vec4<f32>(0.0, 0.0, 2.0, 1.0);
        out.color = vec4<f32>(0.0);
        out.uv = vec2<f32>(0.0);
        return out;
    }

    let local = in.pos * cell.size + in.instancePos;
    out.pos = camera.viewProj * vec4<f32>(local, 0.0, 1.0);
    out.color = ramp.colors[(in.instancePalette - 1u) % 1024u] * in.color;
    out.uv = in.pos + vec2<f32>(0.5);
    return out;
}
`

new_subcell_pipeline :: proc(dev: Device, queue: Queue, format: Texture_Format, cam_bgl: Bind_Group_Layout) -> ^Subcell_Pipeline {
	p := &Subcell_Pipeline{format = format}

	_vert_mod, err := dev_create_shader_module(dev, Shader_Module_Descriptor{
		label = "subcell vert",
		wgsl  = subcell_vert_wgsl,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create subcell vertex shader module", "err", err)
		return nil
	}
	_ = _vert_mod

	_frag_mod := Shader_Module(nil)
	_frag_mod, err = dev_create_shader_module(dev, Shader_Module_Descriptor{
		label = "subcell frag",
		wgsl  = instanced_frag_wgsl,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create subcell fragment shader module", "err", err)
		return nil
	}
	_ = _frag_mod

	uniform := buffer_usage_or(Buffer_Usage_Uniform, Buffer_Usage_Copy_Dst)
	p.ramp_buf, err = dev_create_buffer(dev, Buffer_Descriptor{
		label = "ramp table",
		size  = ramp_table_size,
		usage = uniform,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create ramp buffer", "err", err)
		return nil
	}
	p.cell_buf, err = dev_create_buffer(dev, Buffer_Descriptor{
		label = "cell size",
		size  = cell_uniform_size,
		usage = uniform,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create cell size buffer", "err", err)
		return nil
	}

	entries := make([dynamic]Bind_Group_Layout_Entry, 2)
	entries[0] = Bind_Group_Layout_Entry{binding = 0, visibility = 1 | 2, buffer = Buffer_Binding_Layout{type = 0}}
	entries[1] = Bind_Group_Layout_Entry{binding = 1, visibility = 1 | 2, buffer = Buffer_Binding_Layout{type = 0}}
	p.bgl, err = dev_create_bind_group_layout(dev, Bind_Group_Layout_Descriptor{
		label = "subcell params bgl",
		entries = entries,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create subcell bind group layout", "err", err)
		return nil
	}

	p.pl, err = dev_create_bind_group_layout(dev, Bind_Group_Layout_Descriptor{
		label = "subcell pll",
		entries = [dynamic]Bind_Group_Layout_Entry{},
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create subcell pipeline layout", "err", err)
		return nil
	}

	bgentries := make([dynamic]Bind_Group_Entry, 2)
	bgentries[0] = Bind_Group_Entry{binding = 0, buffer = p.ramp_buf, size = ramp_table_size}
	bgentries[1] = Bind_Group_Entry{binding = 1, buffer = p.cell_buf, size = cell_uniform_size}
	p.bind_group, err = dev_create_bind_group(dev, Bind_Group_Descriptor{
		label = "subcell params bg",
		layout = p.bgl,
		entries = bgentries,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create subcell bind group", "err", err)
		return nil
	}

	vbufs := make([dynamic]Vertex_Buffer_Layout, 2)
	vbufs[0] = mesh_vertex_layout()
	vbufs[1] = subcell_buffer_layout()
	cts := make([dynamic]Color_Target_State, 1)
	cts[0] = Color_Target_State{
		format = p.format,
		blend = Blend_Alpha(),
		write_mask = Color_Write_Mask.All,
	}
	p.pipe, err = dev_create_render_pipeline(dev, Render_Pipeline_Descriptor{
		label = "subcell pipeline",
		layout = p.pl,
		vertex = Vertex_State{
			buffers = vbufs,
		},
		fragment = &Fragment_State{
			targets = cts,
		},
		primitive = Primitive_State{topology = Primitive_Topology.Triangle_List},
	})
	if err != "" {
		logx.logger_error(g_log, "failed to create subcell render pipeline", "err", err)
		return nil
	}

	p.mesh = new_unit_quad(dev, queue)
	subcell_pipeline_set_cell_size(p, queue, 1, 1)
	return p
}

ramp_table_size :: 1024 * 16

subcell_pipeline_set_ramp :: proc(p: ^Subcell_Pipeline, queue: Queue, table: ^Ramp_Table) {
	src := []u8{}
	_ = queue_write_buffer(queue, p.ramp_buf, 0, src)
}

subcell_pipeline_set_cell_size :: proc(p: ^Subcell_Pipeline, queue: Queue, w, h: f32) {
	u := cell_uniform{size = [2]f32{w, h}}
	src := []u8{}
	_ = queue_write_buffer(queue, p.cell_buf, 0, src)
}

subcell_pipeline_pipeline :: proc(p: ^Subcell_Pipeline) -> Render_Pipeline {
	return p.pipe
}

subcell_pipeline_params_bind_group :: proc(p: ^Subcell_Pipeline) -> Bind_Group {
	return p.bind_group
}

subcell_pipeline_mesh :: proc(p: ^Subcell_Pipeline) -> ^Mesh {
	return p.mesh
}

subcell_pipeline_release :: proc(p: ^Subcell_Pipeline) {
	if p == nil {
		return
	}
	if p.pipe != nil { _ = p.pipe }
	if p.bgl != nil { _ = p.bgl }
	if p.pl != nil { _ = p.pl }
	if p.ramp_buf != nil { _ = p.ramp_buf }
	if p.cell_buf != nil { _ = p.cell_buf }
	if p.bind_group != nil { _ = p.bind_group }
	if p.pipe != nil { render_pipeline_release(p.pipe) }
	if p.bgl != nil { bind_group_layout_release(p.bgl) }
	if p.pl != nil { bind_group_layout_release(p.pl) }
	if p.ramp_buf != nil { buffer_release(p.ramp_buf) }
	if p.cell_buf != nil { buffer_release(p.cell_buf) }
	if p.bind_group != nil { bind_group_release(p.bind_group) }
	if p.mesh != nil {
		mesh_release(p.mesh)
	}
}

// ============================================================================
// Renderer
// ============================================================================

Renderer :: struct {
	dev:        Device,
	queue:      Queue,
	format:     Texture_Format,

	pass:       Render_Pass_Encoder,
	enc:        Command_Encoder,
	view:       Texture_View,
	frame_open: bool,
	pass_open:  bool,

	clear:       Clear,
	clear_first: bool,

	cam: ^Camera_Group,

	inst_pipe:    ^Pipeline,
	stroke_pipe:  ^Stroke_Pipeline,
	subcell_pipe: ^Subcell_Pipeline,

	stats: Frame_Stats,
}

new_renderer :: proc(dp: Device_Provider) -> ^Renderer {
	dev := dp.device()
	queue := dp.queue()
	format := dp.surface_format()

	r := &Renderer{
		dev    = dev,
		queue  = queue,
		format = format,
	}

	r.cam = new_camera_group(dev)
	if r.cam == nil {
		return nil
	}

	r.inst_pipe = new_pipeline(dev, format, r.cam.bgl)
	r.stroke_pipe = new_stroke_pipeline(dev, format, r.cam.bgl)

	return r
}

renderer_clear_and_begin_frame :: proc(r: ^Renderer, cr, cg, cb, ca: f32) -> bool {
	return begin_frame(r, true, Clear{r = cr, g = cg, b = cb, a = ca})
}

renderer_begin_frame :: proc(r: ^Renderer) -> bool {
	return begin_frame(r, false, Clear{})
}

begin_frame :: proc(r: ^Renderer, clear: bool, c: Clear) -> bool {
	_ = r.enc
	_ = r.view
	r.stats = Frame_Stats{}
	r.frame_open = true
	r.pass_open = false
	r.clear = c
	r.clear_first = clear
	return true
}

ensure_pass :: proc(r: ^Renderer) -> bool {
	if r.pass_open {
		return true
	}
	if !r.frame_open {
		return false
	}

	load_op := Load_Op.Load
	if r.clear_first {
		load_op = Load_Op.Clear
	}

	attachments := make([dynamic]Render_Pass_Color_Attachment, 1)
	attachments[0] = Render_Pass_Color_Attachment{
		view = r.view,
		load_op = load_op,
		store_op = Store_Op.Store,
		clear_value = r.clear,
	}
	pass, err := command_encoder_begin_render_pass(r.enc, Render_Pass_Descriptor{
		color_attachments = attachments,
	})
	if err != "" {
		logx.logger_error(g_log, "failed to open the render pass", "err", err)
		return false
	}
	r.pass = pass
	r.pass_open = true
	return true
}

renderer_pass_open :: proc(r: ^Renderer) -> bool {
	return r.pass_open
}

renderer_end_frame :: proc(r: ^Renderer) {
	if r.pass != nil {
		render_pass_end(r.pass)
		r.pass = nil
	}
	r.enc = nil
	r.view = nil
	r.frame_open = false
	r.pass_open = false
}

renderer_draw_instanced :: proc(r: ^Renderer, mesh: ^Mesh, instances: ^Instance_Buffer) {
	if instance_buffer_count(Instance_Data, instances) == 0 {
		return
	}
	if !ensure_pass(r) {
		return
	}
	instance_buffer_flush(Instance_Data, instances, r.queue)

	render_pass_set_pipeline(r.pass, r.inst_pipe.pipe)
	render_pass_set_bind_group(r.pass, 0, r.cam.bg, nil)
	render_pass_set_vertex_buffer(r.pass, 0, mesh.vertex_buffer, 0)
	render_pass_set_vertex_buffer(r.pass, 1, instances.buffer, 0)
	render_pass_set_index_buffer(r.pass, mesh.index_buffer, Index_Format.Uint32, 0)
	render_pass_draw_indexed(r.pass, mesh.index_count, cast(u32) instance_buffer_count(Instance_Data, instances), 0, 0, 0)

	r.stats.draw_calls += 1
	r.stats.instances += instance_buffer_count(Instance_Data, instances)
	r.stats.triangles += int(mesh.index_count / 3) * instance_buffer_count(Instance_Data, instances)
}

renderer_draw_instanced_range :: proc(r: ^Renderer, mesh: ^Mesh, instances: ^Instance_Buffer, first, count: int) {
	f := first
	c := count
	if f < 0 {
		f = 0
	}
	if f + c > instances.capacity {
		c = instances.capacity - f
	}
	if c <= 0 {
		return
	}
	if !ensure_pass(r) {
		return
	}
	instance_buffer_flush(Instance_Data, instances, r.queue)

	render_pass_set_pipeline(r.pass, r.inst_pipe.pipe)
	render_pass_set_bind_group(r.pass, 0, r.cam.bg, nil)
	render_pass_set_vertex_buffer(r.pass, 0, mesh.vertex_buffer, 0)
	render_pass_set_vertex_buffer(r.pass, 1, instances.buffer, cast(u64) f * instance_data_size)
	render_pass_set_index_buffer(r.pass, mesh.index_buffer, Index_Format.Uint32, 0)
	render_pass_draw_indexed(r.pass, mesh.index_count, cast(u32) c, 0, 0, 0)

	r.stats.draw_calls += 1
	r.stats.instances += count
	r.stats.triangles += int(mesh.index_count / 3) * count
}

renderer_draw_instanced_indirect :: proc(r: ^Renderer, mesh: ^Mesh, cull: ^Cull_Pipeline, slot: int) {
	if !ensure_pass(r) {
		return
	}
	render_pass_set_pipeline(r.pass, r.inst_pipe.pipe)
	render_pass_set_bind_group(r.pass, 0, r.cam.bg, nil)
	render_pass_set_vertex_buffer(r.pass, 0, mesh.vertex_buffer, 0)
	render_pass_set_vertex_buffer(r.pass, 1, cull.output_buf, cast(u64) slot * instance_data_size)
	render_pass_set_index_buffer(r.pass, mesh.index_buffer, Index_Format.Uint32, 0)
	render_pass_draw_indexed_indirect(r.pass, cull.indirect_buf, cast(u64) slot * slot_stride)
	r.stats.draw_calls += 1
}

renderer_update_camera :: proc(r: ^Renderer, view_proj: [16]f32, viewport_w, viewport_h: f32) {
	camera_group_update(r.cam, r.queue, view_proj, viewport_w, viewport_h)
}

renderer_subcell_pipeline :: proc(r: ^Renderer) -> ^Subcell_Pipeline {
	if r.subcell_pipe == nil {
		r.subcell_pipe = new_subcell_pipeline(r.dev, r.queue, r.format, r.cam.bgl)
	}
	return r.subcell_pipe
}

renderer_draw_subcells :: proc(r: ^Renderer, cells: ^Subcell_Buffer) {
	renderer_draw_subcells_range(r, cells, 0, cells.count)
}

renderer_draw_subcells_range :: proc(r: ^Renderer, cells: ^Subcell_Buffer, first, count: int) {
	f := first
	c := count
	if f < 0 {
		f = 0
	}
	if f + c > cells.capacity {
		c = cells.capacity - f
	}
	if c <= 0 {
		return
	}
	if !ensure_pass(r) {
		return
	}
	instance_buffer_flush(Subcell_Instance, cells, r.queue)

	p := renderer_subcell_pipeline(r)
	mesh := subcell_pipeline_mesh(p)
	render_pass_set_pipeline(r.pass, p.pipe)
	render_pass_set_bind_group(r.pass, 0, r.cam.bg, nil)
	render_pass_set_bind_group(r.pass, 1, subcell_pipeline_params_bind_group(p), nil)
	render_pass_set_vertex_buffer(r.pass, 0, mesh.vertex_buffer, 0)
	render_pass_set_vertex_buffer(r.pass, 1, cells.buffer, cast(u64) f * Subcell_Instance_Size)
	render_pass_set_index_buffer(r.pass, mesh.index_buffer, Index_Format.Uint32, 0)
	render_pass_draw_indexed(r.pass, mesh.index_count, cast(u32) c, 0, 0, 0)

	r.stats.draw_calls += 1
	r.stats.instances += c
	r.stats.triangles += int(mesh.index_count / 3) * c
}

renderer_draw_strokes :: proc(r: ^Renderer, segments: ^Stroke_Buffer) {
	renderer_draw_strokes_n(r, segments, segments.count)
}

renderer_draw_strokes_n :: proc(r: ^Renderer, segments: ^Stroke_Buffer, n: int) {
	count := n
	if count > segments.count {
		count = segments.count
	}
	if count <= 0 {
		return
	}
	if !ensure_pass(r) {
		return
	}
	stroke_buffer_flush(segments, r.queue)

	render_pass_set_pipeline(r.pass, r.stroke_pipe.pipe)
	render_pass_set_bind_group(r.pass, 0, r.cam.bg, nil)
	render_pass_set_vertex_buffer(r.pass, 0, stroke_pipeline_quad_vertex_buffer(r.stroke_pipe), 0)
	render_pass_set_vertex_buffer(r.pass, 1, segments.buffer, 0)
	render_pass_set_index_buffer(r.pass, stroke_pipeline_quad_index_buffer(r.stroke_pipe), Index_Format.Uint16, 0)
	render_pass_draw_indexed(r.pass, 6, cast(u32) count, 0, 0, 0)

	r.stats.draw_calls += 1
	r.stats.instances += count
	r.stats.triangles += 2 * count
}

renderer_draw_vertices :: proc(r: ^Renderer, pipe: Render_Pipeline, vertex_buffer: Buffer, vertex_count: u32) {
	if vertex_count == 0 {
		return
	}
	if !ensure_pass(r) {
		return
	}
	render_pass_set_pipeline(r.pass, pipe)
	render_pass_set_bind_group(r.pass, 0, r.cam.bg, nil)
	render_pass_set_vertex_buffer(r.pass, 0, vertex_buffer, 0)
	render_pass_draw(r.pass, vertex_count, 1, 0, 0)
	r.stats.draw_calls += 1
}

renderer_draw_vertices_range :: proc(r: ^Renderer, pipe: Render_Pipeline, vertex_buffer: Buffer, vertex_count, first_vertex: u32) {
	if vertex_count == 0 {
		return
	}
	if !ensure_pass(r) {
		return
	}
	render_pass_set_pipeline(r.pass, pipe)
	render_pass_set_bind_group(r.pass, 0, r.cam.bg, nil)
	render_pass_set_vertex_buffer(r.pass, 0, vertex_buffer, 0)
	render_pass_draw(r.pass, vertex_count, 1, first_vertex, 0)
	r.stats.draw_calls += 1
	r.stats.triangles += int(vertex_count) / 3
}

// --- Accessors ---

renderer_device :: proc(r: ^Renderer) -> Device {
	return r.dev
}

renderer_queue :: proc(r: ^Renderer) -> Queue {
	return r.queue
}

renderer_surface_format :: proc(r: ^Renderer) -> Texture_Format {
	return r.format
}

renderer_stats :: proc(r: ^Renderer) -> Frame_Stats {
	return r.stats
}

renderer_command_encoder :: proc(r: ^Renderer) -> Command_Encoder {
	return r.enc
}

renderer_camera_buffer :: proc(r: ^Renderer) -> Buffer {
	return r.cam.buf
}

renderer_camera_layout :: proc(r: ^Renderer) -> Bind_Group_Layout {
	return r.cam.bgl
}

renderer_release :: proc(r: ^Renderer) {
	if r == nil {
		return
	}
	if r.inst_pipe != nil {
		pipeline_release(r.inst_pipe)
	}
	if r.stroke_pipe != nil {
		stroke_pipeline_release(r.stroke_pipe)
	}
	if r.cam != nil {
		camera_group_release(r.cam)
		r.cam = nil
	}
	if r.subcell_pipe != nil {
		subcell_pipeline_release(r.subcell_pipe)
	}
}

// ============================================================================
// WGSL shader source strings
// ============================================================================

instanced_vert_wgsl :: `
struct Camera {
    viewProj: mat4x4<f32>,
    viewport: vec2<f32>,
};

@group(0) @binding(0)
var<uniform> camera: Camera;

struct VSIn {
    @location(0) pos: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) instancePos: vec2<f32>,
    @location(3) instanceScale: vec2<f32>,
    @location(4) instanceRot: f32,
    @location(5) instanceColor: vec4<f32>,
    @location(6) instanceUVOffset: vec2<f32>,
    @location(7) instanceLayer: f32,
};

struct VSOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) uv: vec2<f32>,
};

fn rotate2d(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(
        p.x * c - p.y * s,
        p.x * s + p.y * c
    );
}

@vertex
fn vs_main(in: VSIn) -> VSOut {
    var out: VSOut;

    var local = in.pos * in.instanceScale;
    local = rotate2d(local, in.instanceRot);
    local = local + in.instancePos;

    out.pos = camera.viewProj * vec4<f32>(local, 0.0, 1.0);
    out.color = in.instanceColor * in.color;
    out.uv = in.pos + vec2<f32>(0.5) + in.instanceUVOffset;

    return out;
}
`

// ============================================================================
// Vertex layout helpers
// ============================================================================

mesh_vertex_layout :: proc() -> Vertex_Buffer_Layout {
	attrs := make([dynamic]Vertex_Attribute, 2)
	attrs[0] = Vertex_Attribute{format = Vertex_Format_Float32x2, offset = 0,   shader_location = 0}
	attrs[1] = Vertex_Attribute{format = Vertex_Format_Float32x4, offset = 8,   shader_location = 1}
	return Vertex_Buffer_Layout{
		array_stride = Mesh_Vertex_Size,
		step_mode = Vertex_Step_Mode_Vertex,
		attributes = attrs,
	}
}

instance_buffer_layout :: proc() -> Vertex_Buffer_Layout {
	attrs := make([dynamic]Vertex_Attribute, 6)
	attrs[0] = Vertex_Attribute{format = Vertex_Format_Float32x2, offset = 0,   shader_location = 2}
	attrs[1] = Vertex_Attribute{format = Vertex_Format_Float32x2, offset = 8,   shader_location = 3}
	attrs[2] = Vertex_Attribute{format = Vertex_Format_Float32,   offset = 16,  shader_location = 4}
	attrs[3] = Vertex_Attribute{format = Vertex_Format_Float32x4, offset = 32,  shader_location = 5}
	attrs[4] = Vertex_Attribute{format = Vertex_Format_Float32x2, offset = 48,  shader_location = 6}
	attrs[5] = Vertex_Attribute{format = Vertex_Format_Float32,   offset = 56,  shader_location = 7}
	return Vertex_Buffer_Layout{
		array_stride = Instance_Data_Size,
		step_mode = Vertex_Step_Mode_Instance,
		attributes = attrs,
	}
}

subcell_buffer_layout :: proc() -> Vertex_Buffer_Layout {
	attrs := make([dynamic]Vertex_Attribute, 2)
	attrs[0] = Vertex_Attribute{format = Vertex_Format_Float32x2, offset = 0,  shader_location = 2}
	attrs[1] = Vertex_Attribute{format = Vertex_Format_Uint32,    offset = 8,  shader_location = 3}
	return Vertex_Buffer_Layout{
		array_stride = Subcell_Instance_Size,
		step_mode = Vertex_Step_Mode_Instance,
		attributes = attrs,
	}
}
