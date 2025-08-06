const std = @import("std");
const sdl3 = @import("sdl3");
const zmesh = @import("zmesh");
const zm = @import("zmath");

pub const GameContext = struct {
    app_context: AppContext,
    texture_context: TextureContext,
    mesh_context: MeshContext,
    instance_context: InstanceContext,
    input_context: InputContext,
    grid_context: GridContext,
};

pub const TextureContext = struct {
    texture: sdl3.gpu.Texture,
    transfer_buffer: sdl3.gpu.TransferBuffer,
    width: u32,
    height: u32,
};

pub const MeshContext = std.StringArrayHashMap(MeshInfo);

pub const InstanceContext = struct {
    pipeline: sdl3.gpu.GraphicsPipeline,
    depth_texture: sdl3.gpu.Texture,
    sampler: sdl3.gpu.Sampler,
};

pub const GridContext = struct {
    pipeline: sdl3.gpu.GraphicsPipeline,
};

pub const AppContext = struct {
    exe_path: []const u8,
    device: sdl3.gpu.Device,
    window: sdl3.video.Window,
    gamepad: ?sdl3.gamepad.Gamepad = null,
    camera: zm.Vec = .{ 0, 0, 0, 0 },
    previous_time: u64,

    pub fn pathToZ(self: *const AppContext, allocator: std.mem.Allocator, path: []const u8) ![:0]const u8 {
        const joined_path = try std.fs.path.join(allocator, &.{ self.exe_path, path });

        return allocator.dupeZ(u8, joined_path);
    }
};

pub const InputContext = struct {
    movement_x: f32 = 0,
    movement_y: f32 = 0,
};

pub const CameraData = struct {
    view: zm.Mat,
    projection: zm.Mat,
};

pub const Vertex = struct {
    positions: [3]f32,
    texcoords: [2]f32,
};

pub const MeshInfo = struct {
    vertex_buffer: sdl3.gpu.Buffer,
    index_buffer: sdl3.gpu.Buffer,
    instance_buffer: sdl3.gpu.Buffer,

    vertex_index_transfer_buffer: sdl3.gpu.TransferBuffer,
    instance_transfer_buffer: sdl3.gpu.TransferBuffer,

    vertex_data_size: u32,
    index_data_size: u32,
    index_count: u32,
};
