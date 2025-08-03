const sdl3 = @import("sdl3");
const zmesh = @import("zmesh");
const zm = @import("zmath");

pub const GameContext = struct {
    app_context: AppContext,
    instance_context: InstanceContext,
    input_context: InputContext,
};

pub const InstanceContext = struct {
    pipeline: sdl3.gpu.GraphicsPipeline,
    atlas_texture: sdl3.gpu.Texture,
    depth_texture: sdl3.gpu.Texture,
    mesh: zmesh.Shape,
    vertex_buffer: sdl3.gpu.Buffer,
    index_buffer: sdl3.gpu.Buffer,
    vertex_index_transfer_buffer: sdl3.gpu.TransferBuffer,
    instance_buffer: sdl3.gpu.Buffer,
    instance_transfer_buffer: sdl3.gpu.TransferBuffer,
    sampler: sdl3.gpu.Sampler,
};

pub const AppContext = struct {
    device: sdl3.gpu.Device,
    window: sdl3.video.Window,
    gamepad: ?sdl3.gamepad.Gamepad = null,
    camera: zm.Vec = .{ 0, 0, 0, 0 },
    previous_time: u64,
};

pub const InputContext = struct {
    movement_x: f32 = 0,
    movement_y: f32 = 0,
};

pub const CameraData = struct {
    view: zm.Mat,
    projection: zm.Mat,
};
