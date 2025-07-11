const sdl3 = @import("sdl3");

pub const AppContext = struct {
    device: sdl3.gpu.Device,
    window: sdl3.video.Window,
    pipeline: sdl3.gpu.GraphicsPipeline,
    vertex_buffer: sdl3.gpu.Buffer,
    index_buffer: sdl3.gpu.Buffer,
    sampler: sdl3.gpu.Sampler,
    image_texture: sdl3.gpu.Texture,
};
