const sdl3 = @import("sdl3");

pub const AppContext = struct {
    window: sdl3.video.Window,
    render: sdl3.render.Renderer,
};
