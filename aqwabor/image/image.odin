package image

import "core:mem"
import "core:c"
import "core:strings"
import "aqwabor:logx"
import SDL "vendor:sdl3"
import stbi "vendor:stb/image"

load_texture :: proc(renderer: ^SDL.Renderer, path: string, allocator := context.allocator) -> ^SDL.Texture {
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

	return SDL.CreateTextureFromSurface(renderer, surface)
}
