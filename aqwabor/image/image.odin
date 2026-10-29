package image

import "core:mem"
import "core:c"
import "core:strings"
import "aqwabor:logx"
import "aqwabor:window"
import SDL "vendor:sdl3"
import stbi "vendor:stb/image"

Texture :: distinct rawptr

load_texture :: proc(win: window.Window, path: string, allocator := context.allocator) -> Texture {
	renderer := (^SDL.Renderer)(window.Renderer(win))
	if renderer == nil {
		return nil
	}

	cpath := strings.clone_to_cstring(path, allocator)
	defer delete(cpath, allocator)

	w, h, channels: c.int
	pixels := stbi.load(cpath, &w, &h, &channels, 4)
	if pixels == nil {
		logx.logger_error(nil, "image: failed to load", "path", path)
		return nil
	}
	defer stbi.image_free(pixels)

	surface := SDL.CreateSurfaceFrom(w, h, .RGBA32, pixels, w*4)
	if surface == nil {
		return nil
	}
	defer SDL.DestroySurface(surface)

	tex := SDL.CreateTextureFromSurface(renderer, surface)
	return Texture(tex)
}

draw :: proc(win: window.Window, tex: Texture, scale: f32 = 1.0) {
	renderer := (^SDL.Renderer)(window.Renderer(win))
	if renderer == nil || tex == nil {
		return
	}
	ww, wh := window.Size(win)
	cx := f32(ww) / 2
	cy := f32(wh) / 2
	half := 128 * scale
	dst := SDL.FRect{x = cx - half, y = cy - half, w = 256 * scale, h = 256 * scale}
	SDL.RenderTexture(renderer, (^SDL.Texture)(tex), nil, &dst)
}

destroy :: proc(tex: Texture) {
	if tex == nil {
		return
	}
	SDL.DestroyTexture((^SDL.Texture)(tex))
}
