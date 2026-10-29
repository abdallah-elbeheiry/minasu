package image

import "core:c"
import "core:mem"
import "core:strings"
import "aqwabor:logx"
import "aqwabor:window"
import SDL "vendor:sdl3"
import stbi "vendor:stb/image"

Texture :: struct {
	device: ^SDL.GPUDevice,
	handle: ^SDL.GPUTexture,
	w:      int,
	h:      int,
}

load_texture :: proc(win: window.Window, path: string, allocator := context.allocator) -> Texture {
	if win == nil {
		return {}
	}
	dev := window.GPUDevice(win)
	if dev == nil {
		return {}
	}

	cpath := strings.clone_to_cstring(path, allocator)
	defer delete(cpath, allocator)

	wi, hi, channels: c.int
	pixels := stbi.load(cpath, &wi, &hi, &channels, 4)
	if pixels == nil {
		logx.logger_error(nil, "image: failed to load", "path", path)
		return {}
	}
	defer stbi.image_free(pixels)

	tex_info := SDL.GPUTextureCreateInfo{
		type = .D2,
		format = .R8G8B8A8_UNORM,
		usage = {.SAMPLER},
		width = SDL.Uint32(wi),
		height = SDL.Uint32(hi),
		layer_count_or_depth = 1,
		num_levels = 1,
	}
	tex := SDL.CreateGPUTexture(dev, tex_info)
	if tex == nil {
		return {}
	}

	// upload
	buf_size := int(wi) * int(hi) * 4
	transfer := SDL.CreateGPUTransferBuffer(dev, SDL.GPUTransferBufferCreateInfo{
		usage = .UPLOAD,
		size = SDL.Uint32(buf_size),
	})
	if transfer == nil {
		SDL.ReleaseGPUTexture(dev, tex)
		return {}
	}
	mapped := SDL.MapGPUTransferBuffer(dev, transfer, false)
	if mapped == nil {
		SDL.ReleaseGPUTransferBuffer(dev, transfer)
		SDL.ReleaseGPUTexture(dev, tex)
		return {}
	}
	// copy pixels
	src := ([^]u8)(pixels)
	dst := ([^]u8)(mapped)
	for i in 0 ..< buf_size {
		dst[i] = src[i]
	}
	SDL.UnmapGPUTransferBuffer(dev, transfer)

	cmd := SDL.AcquireGPUCommandBuffer(dev)
	copy_pass := SDL.BeginGPUCopyPass(cmd)
	src_loc := SDL.GPUTextureTransferInfo{
		transfer_buffer = transfer,
		offset = 0,
		pixels_per_row = SDL.Uint32(wi),
		rows_per_layer = SDL.Uint32(hi),
	}
	dst_region := SDL.GPUTextureRegion{
		texture = tex,
		mip_level = 0,
		layer = 0,
		x = 0,
		y = 0,
		z = 0,
		w = SDL.Uint32(wi),
		h = SDL.Uint32(hi),
		d = 1,
	}
	SDL.UploadToGPUTexture(copy_pass, src_loc, dst_region, false)
	SDL.EndGPUCopyPass(copy_pass)
	_ = SDL.SubmitGPUCommandBuffer(cmd)
	SDL.ReleaseGPUTransferBuffer(dev, transfer)

	return Texture{device = dev, handle = tex, w = int(wi), h = int(hi)}
}

draw :: proc(win: window.Window, tex: Texture, scale: f32 = 1.0) {
	if win == nil || tex.handle == nil {
		return
	}
	cmd := window.CurrentCommandBuffer(win)
	swap := window.CurrentSwapchainTexture(win)
	if cmd == nil || swap == nil {
		return
	}
	sw, sh := window.SwapchainSize(win)
	if sw <= 0 || sh <= 0 {
		return
	}
	half := f32(128) * scale
	cx := f32(sw) / 2
	cy := f32(sh) / 2
	dst_w := cast(u32)(256 * scale)
	dst_h := cast(u32)(256 * scale)
	dst_x := cast(u32)(cx - half)
	dst_y := cast(u32)(cy - half)

	blit := SDL.GPUBlitInfo{
		source = SDL.GPUBlitRegion{
			texture = tex.handle,
			w = SDL.Uint32(tex.w),
			h = SDL.Uint32(tex.h),
		},
		destination = SDL.GPUBlitRegion{
			texture = swap,
			w = dst_w,
			h = dst_h,
			x = dst_x,
			y = dst_y,
		},
		load_op = .LOAD,
		filter = .LINEAR,
	}
	SDL.BlitGPUTexture(cmd, blit)
}

destroy :: proc(tex: Texture) {
	if tex.handle == nil {
		return
	}
	if tex.device != nil {
		SDL.ReleaseGPUTexture(tex.device, tex.handle)
	}
}