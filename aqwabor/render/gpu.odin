package render

import "aqwabor:logx"
import "core:mem"
import "core:sync"
import vulkan "vendor:vulkan"

g_log: ^logx.Logger
g_allocator: mem.Allocator
g_arena: mem.Dynamic_Arena

init :: proc() {
	mem.dynamic_arena_init(&g_arena)
	g_allocator = mem.dynamic_arena_allocator(&g_arena)
	g_log = logx.with(g_allocator)
}

// ============================================================================
// Vulkan handle types (wrapping vendor:vulkan handles)
// ============================================================================

Device :: distinct rawptr
Queue :: distinct rawptr
Buffer :: distinct rawptr
Render_Pipeline :: distinct rawptr
Compute_Pipeline :: distinct rawptr
Bind_Group :: distinct rawptr
Bind_Group_Layout :: distinct rawptr
Shader_Module :: distinct rawptr
Command_Encoder :: distinct rawptr
Render_Pass_Encoder :: distinct rawptr
Compute_Pass_Encoder :: distinct rawptr
Texture_View :: distinct rawptr
Swapchain :: distinct rawptr
Surface :: distinct rawptr
Instance :: distinct rawptr
Physical_Device :: distinct rawptr
Command_Pool :: distinct rawptr
Fence :: distinct rawptr
Semaphore :: distinct rawptr
Descriptor_Set :: distinct rawptr
Descriptor_Pool :: distinct rawptr
Descriptor_Set_Layout :: distinct rawptr
Pipeline_Layout :: distinct rawptr
Framebuffer :: distinct rawptr
Render_Pass :: distinct rawptr
Image :: distinct rawptr
Image_View :: distinct rawptr
Sampler :: distinct rawptr
Device_Memory :: distinct rawptr

Texture_Format :: distinct u32

Texture_Format_Undefined       :: Texture_Format(0)
Texture_Format_R8Unorm         :: Texture_Format(1)
Texture_Format_R8Snorm         :: Texture_Format(2)
Texture_Format_R8Uint          :: Texture_Format(3)
Texture_Format_R8Sint          :: Texture_Format(4)
Texture_Format_R16Uint         :: Texture_Format(5)
Texture_Format_R16Sint         :: Texture_Format(6)
Texture_Format_R16Float        :: Texture_Format(7)
Texture_Format_Rg8Unorm        :: Texture_Format(8)
Texture_Format_Rg8Snorm        :: Texture_Format(9)
Texture_Format_Rg8Uint         :: Texture_Format(10)
Texture_Format_Rg8Sint         :: Texture_Format(11)
Texture_Format_R32Uint         :: Texture_Format(12)
Texture_Format_R32Sint         :: Texture_Format(13)
Texture_Format_R32Float        :: Texture_Format(14)
Texture_Format_Rg16Uint        :: Texture_Format(15)
Texture_Format_Rg16Sint        :: Texture_Format(16)
Texture_Format_Rg16Float       :: Texture_Format(17)
Texture_Format_Rgba8Unorm      :: Texture_Format(18)
Texture_Format_Rgba8UnormSrgb  :: Texture_Format(19)
Texture_Format_Rgba8Snorm      :: Texture_Format(20)
Texture_Format_Rgba8Uint       :: Texture_Format(21)
Texture_Format_Rgba8Sint       :: Texture_Format(22)
Texture_Format_Bgra8Unorm      :: Texture_Format(23)
Texture_Format_Bgra8UnormSrgb  :: Texture_Format(24)
Texture_Format_Rgb10a2Unorm    :: Texture_Format(25)
Texture_Format_Rgb10a2Uint     :: Texture_Format(26)
Texture_Format_Rgb10a2Sint     :: Texture_Format(27)
Texture_Format_Rg11b10ufloat   :: Texture_Format(28)
Texture_Format_R9e5ufloat      :: Texture_Format(29)
Texture_Format_Rg16Uint_DUP    :: Texture_Format(30)
Texture_Format_Rg16Sint_DUP    :: Texture_Format(31)
Texture_Format_Rg16Float_DUP   :: Texture_Format(32)
Texture_Format_Rg32Uint        :: Texture_Format(33)
Texture_Format_Rg32Sint        :: Texture_Format(34)
Texture_Format_Rg32Float       :: Texture_Format(35)
Texture_Format_Rgba16Uint      :: Texture_Format(36)
Texture_Format_Rgba16Sint      :: Texture_Format(37)
Texture_Format_Rgba16Float     :: Texture_Format(38)
Texture_Format_Rgba32Uint      :: Texture_Format(39)
Texture_Format_Rgba32Sint      :: Texture_Format(40)
Texture_Format_Rgba32Float     :: Texture_Format(41)

// ============================================================================
// Core data types (must match shader layouts)
// ============================================================================

Instance_Data :: struct {
	position:   [2]f32,
	scale:      [2]f32,
	rotation:   f32,
	_pad1:      [12]u8,
	color:      [4]f32,
	uv_offset:  [2]f32,
	layer:      f32,
	pad:        f32,
}

Instance_Data_Size :: 64

Subcell_Instance :: struct {
	x:      f32,
	y:      f32,
	palette: u32,
	_pad:   u32,
}

Subcell_Instance_Size :: 16

Stroke_Segment :: struct {
	p0:     [2]f32,
	p1:     [2]f32,
	prev:   [2]f32,
	next:   [2]f32,
	color0: [4]f32,
	color1: [4]f32,
	width:  f32,
	flags:  u8,
	layer:  u8,
	_pad:   [2]u8,
}

Stroke_Segment_Size :: 72

Width_Mode_Pixels :: 0
Width_Mode_World  :: 1

Camera_Uniform :: struct {
	view_proj: [16]f32,
	viewport:  [2]f32,
	_pad:      [8]u8,
}

Camera_Uniform_Size :: 80

Mesh_Vertex :: struct {
	x, y: f32,
	r, g, b, a: f32,
}

Mesh_Vertex_Size :: 24

// ============================================================================
// Vertex buffer layout descriptions
// ============================================================================

Vertex_Attribute :: struct {
	format:          u32,
	offset:          u64,
	shader_location: u32,
}

Vertex_Buffer_Layout :: struct {
	array_stride:   u64,
	step_mode:      u32,
	attributes:     [dynamic]Vertex_Attribute,
}

Vertex_Format_Float32x2 :: u32(0)
Vertex_Format_Float32x4 :: u32(1)
Vertex_Format_Float32   :: u32(2)
Vertex_Format_Uint8x2   :: u32(3)
Vertex_Format_Uint32    :: u32(4)

Vertex_Step_Mode_Vertex   :: u32(0)
Vertex_Step_Mode_Instance :: u32(1)

// ============================================================================
// Pipeline state
// ============================================================================

Blend_Factor :: enum u8 {
	Zero,
	One,
	Src_Color,
	One_Minus_Src_Color,
	Src_Alpha,
	One_Minus_Src_Alpha,
	Dst_Color,
	One_Minus_Dst_Color,
	Dst_Alpha,
	One_Minus_Dst_Alpha,
	Src_Alpha_Saturated,
	Blend_Color,
	One_Minus_Blend_Color,
}

Blend_Operation :: enum u8 {
	Add,
	Subtract,
	Reverse_Subtract,
	Min,
	Max,
}

Color_Write_Mask :: enum u8 {
	None   = 0,
	Red    = 1,
	Green  = 2,
	Blue   = 4,
	Alpha  = 8,
	All    = 15,
}

Blend_Component :: struct {
	src_factor:   Blend_Factor,
	dst_factor:   Blend_Factor,
	operation:    Blend_Operation,
}

Blend_State :: struct {
	color:   Blend_Component,
	alpha:   Blend_Component,
}

Blend_Alpha :: proc() -> Blend_State {
	s := Blend_State{
		color = Blend_Component{
			src_factor = Blend_Factor.Src_Alpha,
			dst_factor = Blend_Factor.One_Minus_Src_Alpha,
			operation = Blend_Operation.Add,
		},
		alpha = Blend_Component{
			src_factor = Blend_Factor.One,
			dst_factor = Blend_Factor.One_Minus_Src_Alpha,
			operation = Blend_Operation.Add,
		},
	}
	return s
}

// ============================================================================
// Buffer usage (bitflags)
// ============================================================================

Buffer_Usage :: distinct u32

Buffer_Usage_None             :: Buffer_Usage(0)
Buffer_Usage_Vertex           :: Buffer_Usage(1 << 0)
Buffer_Usage_Index            :: Buffer_Usage(1 << 1)
Buffer_Usage_Uniform          :: Buffer_Usage(1 << 2)
Buffer_Usage_Storage          :: Buffer_Usage(1 << 3)
Buffer_Usage_Indirect         :: Buffer_Usage(1 << 4)
Buffer_Usage_Copy_Dst         :: Buffer_Usage(1 << 5)
Buffer_Usage_Copy_Src         :: Buffer_Usage(1 << 6)

buffer_usage_or :: proc(a, b: Buffer_Usage) -> Buffer_Usage {
	return Buffer_Usage(u32(a) | u32(b))
}

// ============================================================================
// Primitive topology
// ============================================================================

Primitive_Topology :: enum u8 {
	Point_List,
	Line_List,
	Line_Strip,
	Triangle_List,
	Triangle_Strip,
}

// ============================================================================
// Index format
// ============================================================================

Index_Format :: enum u8 {
	Uint16,
	Uint32,
}

// ============================================================================
// Load / store ops
// ============================================================================

Load_Op :: enum u8 {
	Load,
	Clear,
}

Store_Op :: enum u8 {
	Store,
}

// ============================================================================
// High-level types
// ============================================================================

Clear :: struct {
	r, g, b, a: f32,
}

View_Bounds :: struct {
	min_x, min_y: f32,
	max_x, max_y: f32,
}

// ============================================================================
// Device provider abstraction (Vulkan native)
// ============================================================================

Device_Provider :: struct {
	device:         proc() -> Device,
	queue:          proc() -> Queue,
	surface_format: proc() -> Texture_Format,
}

// ============================================================================
// GPU - the public facade over the render submission layer
// ============================================================================

GPU :: struct {
	r:         ^Renderer,
	cull:      ^Cull_Pipeline,
	cull_max:  int,
	cull_mesh: ^Mesh,
	retired:   [dynamic]^Retired_Cull,
	frame:     u64,
}

Retired_Cull :: struct {
	cull: ^Cull_Pipeline,
	frame: u64,
}

retire_after :: 3

create_gpu :: proc(dp: Device_Provider, allocator := context.allocator) -> ^GPU {
	r := new_renderer(dp)
	g := new(GPU)
	g.r = r
	g.cull_max = 0
	return g
}

begin :: proc(g: ^GPU, c: Clear) -> bool {
	g.frame += 1
	release_retired(g)
	if g.cull != nil {
		cull_begin_frame(g.cull)
	}
	return renderer_clear_and_begin_frame(g.r, c.r, c.g, c.b, c.a)
}

begin_load :: proc(g: ^GPU) -> bool {
	g.frame += 1
	release_retired(g)
	if g.cull != nil {
		cull_begin_frame(g.cull)
	}
	return renderer_begin_frame(g.r)
}

release_retired :: proc(g: ^GPU) {
	kept := make([dynamic]^Retired_Cull, 0, len(g.retired))
	for r in g.retired {
		if g.frame - r.frame >= retire_after {
			cull_release(r.cull)
			continue
		}
		k := kept
		append_elems(&k, r)
		kept = k
	}
	g.retired = kept
}

end :: proc(g: ^GPU) {
	renderer_end_frame(g.r)
}

// --- Camera ---

set_camera :: proc(g: ^GPU, view_proj: [16]f32, viewport_w, viewport_h: f32) {
	renderer_update_camera(g.r, view_proj, viewport_w, viewport_h)
}

// --- Instanced draws ---

sprites :: proc(g: ^GPU, capacity: int, allocator := context.allocator) -> ^Sprite_Batch {
	return new_sprite_batch(g.r.dev, g.r.queue, nil, capacity, allocator)
}

draw_sprites :: proc(g: ^GPU, batch: ^Sprite_Batch) {
	renderer_draw_instanced(g.r, batch.mesh, batch.buf)
}

draw_sprites_range :: proc(g: ^GPU, batch: ^Sprite_Batch, first, count: int) {
	renderer_draw_instanced_range(g.r, batch.mesh, batch.buf, first, count)
}

Culled :: struct {
	mesh: ^Mesh,
	cull: ^Cull_Pipeline,
	slot: int,
	ok:   bool,
}

cull_sprites :: proc(g: ^GPU, batch: ^Sprite_Batch, view_bounds: View_Bounds) -> Culled {
	return cull_sprites_range(g, batch, 0, batch.buf.count, view_bounds)
}

cull_sprites_range :: proc(g: ^GPU, batch: ^Sprite_Batch, first, count: int, view_bounds: View_Bounds) -> Culled {
	instances := batch.buf
	f := first
	c := count
	if f < 0 {
		f = 0
	}
	if f + c > instances.capacity {
		c = instances.capacity - f
	}
	if c <= 0 {
		return Culled{}
	}
	if renderer_pass_open(g.r) {
		logx.logger_error(g_log, "cull_sprites called after the render pass opened; call between Begin and first draw")
		return Culled{}
	}
	enc := renderer_command_encoder(g.r)
	if enc == nil {
		logx.logger_error(g_log, "cull_sprites called outside a frame; call Begin first")
		return Culled{}
	}

	instance_buffer_flush(Instance_Data, instances, g.r.queue)

	ensure_cull(g, c)
	if g.cull == nil {
		return Culled{}
	}
	slot, ok := cull_claim(g.cull, c)
	if !ok {
		logx.logger_debug(g_log, "no cull this draw; the range is drawn as it stands", "instances", c)
		return Culled{}
	}

	mesh := batch.mesh
	if mesh == nil {
		mesh = unit_quad(g)
	}

	cull_reset_indirect(g.cull, slot, mesh.index_count)
	cull_encode_dispatch(
		g.cull, enc, slot,
		instances.buffer, g.r.cam.buf,
		f, c,
		[2]f32{view_bounds.min_x, view_bounds.min_y},
		[2]f32{view_bounds.max_x, view_bounds.max_y},
	)
	return Culled{mesh = mesh, cull = g.cull, slot = slot, ok = true}
}

draw_sprites_culled :: proc(g: ^GPU, c: Culled) {
	if !c.ok || c.cull == nil {
		return
	}
	renderer_draw_instanced_indirect(g.r, c.mesh, c.cull, c.slot)
}

ensure_cull :: proc(g: ^GPU, count: int) {
	if g.cull != nil && cull_fits(g.cull, count) {
		return
	}
	want := count
	if g.cull != nil {
		want += g.cull.used
	}
	if want > max_cull_bytes / instance_data_size {
		return
	}
	if g.cull != nil {
		r := g.retired
		rc := new(Retired_Cull)
		rc.cull = g.cull
		rc.frame = g.frame
		append_elems(&r, rc)
		g.retired = r
	}
	max_n := max(want * 2, 1024)
	g.cull = new_cull_pipeline(g.r.dev, g.r.queue, max_n)
	if g.cull == nil {
		g.cull_max = 0
		return
	}
	cull_begin_frame(g.cull)
	g.cull_max = max_n
}

unit_quad :: proc(g: ^GPU) -> ^Mesh {
	if g.cull_mesh == nil {
		g.cull_mesh = new_unit_quad(g.r.dev, g.r.queue)
	}
	return g.cull_mesh
}

// --- Cells ---

subcells :: proc(g: ^GPU, capacity: int) -> ^Subcell_Buffer {
	return new_subcell_buffer(g.r.dev, capacity)
}

set_ramp :: proc(g: ^GPU, table: ^Ramp_Table) {
	subcell_pipeline_set_ramp(g.r.subcell_pipe, g.r.queue, table)
}

set_cell_size :: proc(g: ^GPU, w, h: f32) {
	subcell_pipeline_set_cell_size(g.r.subcell_pipe, g.r.queue, w, h)
}

draw_subcells :: proc(g: ^GPU, cells: ^Subcell_Buffer) {
	renderer_draw_subcells(g.r, cells)
}

draw_subcells_range :: proc(g: ^GPU, cells: ^Subcell_Buffer, first, count: int) {
	renderer_draw_subcells_range(g.r, cells, first, count)
}

// --- Strokes ---

draw_strokes :: proc(g: ^GPU, segments: ^Stroke_Buffer) {
	renderer_draw_strokes(g.r, segments)
}

// --- Custom pipelines ---

draw_vertices :: proc(g: ^GPU, pipe: Render_Pipeline, vertex_buffer: Buffer, vertex_count: u32) {
	renderer_draw_vertices(g.r, pipe, vertex_buffer, vertex_count)
}

draw_vertices_range :: proc(g: ^GPU, pipe: Render_Pipeline, vertex_buffer: Buffer, vertex_count, first_vertex: u32) {
	renderer_draw_vertices_range(g.r, pipe, vertex_buffer, vertex_count, first_vertex)
}

camera_layout :: proc(g: ^GPU) -> Bind_Group_Layout {
	return renderer_camera_layout(g.r)
}

// --- Accessors ---

device_proc :: proc(g: ^GPU) -> Device {
	return g.r.dev
}

queue_proc :: proc(g: ^GPU) -> Queue {
	return g.r.queue
}

surface_format_proc :: proc(g: ^GPU) -> Texture_Format {
	return g.r.format
}

stats_proc :: proc(g: ^GPU) -> Frame_Stats {
	return g.r.stats
}

release_proc :: proc(g: ^GPU) {
	for r in g.retired {
		cull_release(r.cull)
	}
	g.retired = nil
	if g.cull != nil {
		cull_release(g.cull)
		g.cull = nil
	}
	if g.cull_mesh != nil {
		mesh_release(g.cull_mesh)
		g.cull_mesh = nil
	}
	renderer_release(g.r)
}

// ============================================================================
// Helpers
// ============================================================================

screen_rect :: proc(r: View_Bounds, cam_x, cam_y, zoom, vp_w, vp_h, scale: f32) -> (x0, y0, x1, y1: int) {
	z := zoom
	s := scale
	if z <= 0 {
		z = 1
	}
	if s <= 0 {
		s = 1
	}
	fx0 := (r.min_x - cam_x) * z + vp_w / 2
	fx1 := (r.max_x - cam_x) * z + vp_w / 2
	fy0 := (r.min_y - cam_y) * z + vp_h / 2
	fy1 := (r.max_y - cam_y) * z + vp_h / 2

	x0 = cast(int) fx0
	y0 = cast(int) fy0
	x1 = cast(int) fx1
	y1 = cast(int) fy1
	si := cast(int) s

	return x0 * si, y0 * si, x1 * si + 1, y1 * si + 1
}

view_of :: proc(cam_x, cam_y, zoom, vp_w, vp_h: f32) -> View_Bounds {
	z := zoom
	if z <= 0 {
		z = 1
	}
	half_w := vp_w / (2 * z)
	half_h := vp_h / (2 * z)
	return View_Bounds{
		min_x = cam_x - half_w, max_x = cam_x + half_w,
		min_y = cam_y - half_h, max_y = cam_y + half_h,
	}
}

max2 :: proc(a, b: int) -> int {
	if a > b {
		return a
	}
	return b
}

clamp_int :: proc(v, lo, hi: int) -> int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

// ============================================================================
// GPU API declarations (implement via vendor:vulkan later)
// ============================================================================

Buffer_Descriptor :: struct {
	label:  string,
	size:   u64,
	usage:  Buffer_Usage,
}

Render_Pipeline_Descriptor :: struct {
	label:      string,
	layout:     Bind_Group_Layout,
	vertex:     Vertex_State,
	fragment:   ^Fragment_State,
	primitive:  Primitive_State,
}

Compute_Pipeline_Descriptor :: struct {
	label:        string,
	layout:       Pipeline_Layout,
	module:       Shader_Module,
	entry_point: string,
}

Vertex_State :: struct {
	module:      Shader_Module,
	entry_point: string,
	buffers:     [dynamic]Vertex_Buffer_Layout,
}

Fragment_State :: struct {
	module:      Shader_Module,
	entry_point: string,
	targets:     [dynamic]Color_Target_State,
}

Primitive_State :: struct {
	topology: Primitive_Topology,
}

Color_Target_State :: struct {
	format:    Texture_Format,
	blend:     Blend_State,
	write_mask: Color_Write_Mask,
}

Bind_Group_Layout_Entry :: struct {
	binding:    u32,
	visibility: u32,
	buffer:     Buffer_Binding_Layout,
}

Buffer_Binding_Layout :: struct {
	type: u32,
}

Bind_Group_Layout_Descriptor :: struct {
	label:   string,
	entries: [dynamic]Bind_Group_Layout_Entry,
}

Bind_Group_Entry :: struct {
	binding: u32,
	buffer:  Buffer,
	offset:  u64,
	size:    u64,
}

Bind_Group_Descriptor :: struct {
	label:  string,
	layout: Bind_Group_Layout,
	entries: [dynamic]Bind_Group_Entry,
}

Pipeline_Layout_Descriptor :: struct {
	label:                 string,
	bind_group_layouts: [dynamic]Bind_Group_Layout,
}

Shader_Module_Descriptor :: struct {
	label: string,
	wgsl:  string,
}

Render_Pass_Color_Attachment :: struct {
	view:       Texture_View,
	load_op:    Load_Op,
	store_op:   Store_Op,
	clear_value: Clear,
}

Render_Pass_Descriptor :: struct {
	color_attachments: [dynamic]Render_Pass_Color_Attachment,
}

Compute_Pass_Descriptor :: struct {
	label: string,
}

// --- Device operations ---

dev_create_buffer :: proc(dev: Device, desc: Buffer_Descriptor) -> (Buffer, string) {
	return nil, "unimplemented: dev_create_buffer"
}

dev_create_render_pipeline :: proc(dev: Device, desc: Render_Pipeline_Descriptor) -> (Render_Pipeline, string) {
	return nil, "unimplemented: dev_create_render_pipeline"
}

dev_create_compute_pipeline :: proc(dev: Device, desc: Compute_Pipeline_Descriptor) -> (Compute_Pipeline, string) {
	return nil, "unimplemented: dev_create_compute_pipeline"
}

dev_create_bind_group_layout :: proc(dev: Device, desc: Bind_Group_Layout_Descriptor) -> (Bind_Group_Layout, string) {
	return nil, "unimplemented: dev_create_bind_group_layout"
}

dev_create_bind_group :: proc(dev: Device, desc: Bind_Group_Descriptor) -> (Bind_Group, string) {
	return nil, "unimplemented: dev_create_bind_group"
}

dev_create_shader_module :: proc(dev: Device, desc: Shader_Module_Descriptor) -> (Shader_Module, string) {
	return nil, "unimplemented: dev_create_shader_module"
}

dev_create_pipeline_layout :: proc(dev: Device, desc: Pipeline_Layout_Descriptor) -> (Pipeline_Layout, string) {
	return nil, "unimplemented: dev_create_pipeline_layout"
}

buffer_release :: proc(buf: Buffer) {
	_ = buf
}

render_pipeline_release :: proc(pipe: Render_Pipeline) {
	_ = pipe
}

compute_pipeline_release :: proc(pipe: Compute_Pipeline) {
	_ = pipe
}

bind_group_release :: proc(bg: Bind_Group) {
	_ = bg
}

bind_group_layout_release :: proc(bgl: Bind_Group_Layout) {
	_ = bgl
}

shader_module_release :: proc(mod: Shader_Module) {
	_ = mod
}

// --- Queue operations ---

queue_write_buffer :: proc(queue: Queue, buffer: Buffer, offset: u64, data: []u8) -> string {
	_ = queue
	_ = buffer
	_ = offset
	_ = data
	return "unimplemented: queue_write_buffer"
}

// --- Command encoder ---

command_encoder_begin_render_pass :: proc(enc: Command_Encoder, desc: Render_Pass_Descriptor) -> (Render_Pass_Encoder, string) {
	return nil, "unimplemented: command_encoder_begin_render_pass"
}

command_encoder_begin_compute_pass :: proc(enc: Command_Encoder, desc: ^Compute_Pass_Descriptor) -> (Compute_Pass_Encoder, string) {
	return nil, "unimplemented: command_encoder_begin_compute_pass"
}

// --- Render pass encoder ---

render_pass_set_pipeline :: proc(pass: Render_Pass_Encoder, pipe: Render_Pipeline) {
	_ = pass
	_ = pipe
}

render_pass_set_bind_group :: proc(pass: Render_Pass_Encoder, index: u32, group: Bind_Group, offsets: [dynamic]u64) {
	_ = pass
	_ = index
	_ = group
	_ = offsets
}

render_pass_set_vertex_buffer :: proc(pass: Render_Pass_Encoder, slot: u32, buffer: Buffer, offset: u64) {
	_ = pass
	_ = slot
	_ = buffer
	_ = offset
}

render_pass_set_index_buffer :: proc(pass: Render_Pass_Encoder, buffer: Buffer, format: Index_Format, offset: u64) {
	_ = pass
	_ = buffer
	_ = format
	_ = offset
}

render_pass_draw_indexed :: proc(pass: Render_Pass_Encoder, index_count, instance_count, first_index, base_vertex, first_instance: u32) {
	_ = pass
}

render_pass_draw_indexed_indirect :: proc(pass: Render_Pass_Encoder, indirect_buffer: Buffer, indirect_offset: u64) {
	_ = pass
	_ = indirect_buffer
	_ = indirect_offset
}

render_pass_draw :: proc(pass: Render_Pass_Encoder, vertex_count, instance_count, first_vertex, first_instance: u32) {
	_ = pass
}

render_pass_end :: proc(pass: Render_Pass_Encoder) {
	_ = pass
}

// --- Compute pass encoder ---

compute_pass_set_pipeline :: proc(pass: Compute_Pass_Encoder, pipe: Compute_Pipeline) {
	_ = pass
	_ = pipe
}

compute_pass_set_bind_group :: proc(pass: Compute_Pass_Encoder, index: u32, group: Bind_Group, offsets: [dynamic]u64) {
	_ = pass
	_ = index
	_ = group
	_ = offsets
}

compute_pass_dispatch :: proc(pass: Compute_Pass_Encoder, x, y, z: u32) {
	_ = pass
}

compute_pass_end :: proc(pass: Compute_Pass_Encoder) {
	_ = pass
}
