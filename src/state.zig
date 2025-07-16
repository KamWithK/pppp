const sdl3 = @import("sdl3");

pub const AppContext = struct {
    device: sdl3.gpu.Device,
    window: sdl3.video.Window,
    pipeline: sdl3.gpu.GraphicsPipeline,
    atlas_texture: sdl3.gpu.Texture,
    instance_buffer: sdl3.gpu.Buffer,
    instance_transfer_buffer: sdl3.gpu.TransferBuffer,
    sampler: sdl3.gpu.Sampler,
};
