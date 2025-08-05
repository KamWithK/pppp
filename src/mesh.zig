const std = @import("std");
const sdl3 = @import("sdl3");
const zm = @import("zmath");
const zmesh = @import("zmesh");

const GameContext = @import("state.zig").GameContext;
const AppContext = @import("state.zig").AppContext;
const MeshContext = @import("state.zig").MeshContext;
const MeshInfo = @import("state.zig").MeshInfo;
const Vertex = @import("state.zig").Vertex;

const MeshTransferBuffers = struct {};

const MAX_INSTANCES = 1000;
const INSTACE_BUFFER_SIZE = MAX_INSTANCES * @sizeOf(zm.Mat);

pub fn create_meshes_buffers(allocator: std.mem.Allocator, device: sdl3.gpu.Device) !MeshContext {
    zmesh.init(allocator);

    var mesh_context = MeshContext.init(allocator);

    const cylinder = try create_mesh_buffers(
        allocator,
        device,
        zmesh.Shape.initCylinder(10, 10),
    );
    try mesh_context.put("cylinder", cylinder);

    const cone = try create_mesh_buffers(
        allocator,
        device,
        zmesh.Shape.initCone(10, 10),
    );
    try mesh_context.put("cone", cone);

    zmesh.deinit();

    return mesh_context;
}

fn create_mesh_buffers(
    allocator: std.mem.Allocator,
    device: sdl3.gpu.Device,
    mesh: zmesh.Shape,
) !MeshInfo {
    const mesh_texcoords = mesh.texcoords orelse return error.InvalidData;
    const vertex_data = try allocator.alloc(Vertex, mesh.positions.len);
    const index_data = mesh.indices;
    for (mesh.positions, mesh_texcoords, 0..) |positions, texcoords, i| {
        vertex_data[i] = Vertex{
            .positions = positions,
            .texcoords = texcoords,
        };
    }

    const vertex_data_size: u32 = @intCast(@sizeOf(Vertex) * vertex_data.len);
    const index_data_size: u32 = @intCast(@sizeOf(u32) * index_data.len);

    const instance_buffer = try device.createBuffer(.{
        .usage = .{ .graphics_storage_read = true },
        .size = INSTACE_BUFFER_SIZE,
    });
    const instance_transfer_buffer = try device.createTransferBuffer(.{
        .usage = .upload,
        .size = INSTACE_BUFFER_SIZE,
    });

    const vertex_buffer = try device.createBuffer(.{
        .usage = .{ .vertex = true },
        .size = vertex_data_size,
    });
    const index_buffer = try device.createBuffer(.{
        .usage = .{ .index = true },
        .size = index_data_size,
    });
    const vertex_index_transfer_buffer = try device.createTransferBuffer(.{
        .usage = .upload,
        .size = vertex_data_size + index_data_size,
    });

    const vertex_index_transfer_buffer_mapped = try device.mapTransferBuffer(vertex_index_transfer_buffer, false);
    @memcpy(vertex_index_transfer_buffer_mapped, std.mem.sliceAsBytes(vertex_data));
    @memcpy(vertex_index_transfer_buffer_mapped + vertex_data_size, std.mem.sliceAsBytes(index_data));
    device.unmapTransferBuffer(vertex_index_transfer_buffer);

    return .{
        .instance_buffer = instance_buffer,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,

        .instance_transfer_buffer = instance_transfer_buffer,
        .vertex_index_transfer_buffer = vertex_index_transfer_buffer,

        .vertex_data_size = vertex_data_size,
        .index_data_size = index_data_size,
        .index_count = @intCast(mesh.indices.len),
    };
}

pub fn copy_vertex_index_buffers(
    device: sdl3.gpu.Device,
    copy_pass: sdl3.gpu.CopyPass,
    mesh_context: MeshContext,
) !void {
    var mesh_iterator = mesh_context.iterator();

    while (mesh_iterator.next()) |mesh_entry| {
        const mesh = mesh_entry.value_ptr;

        copy_pass.uploadToBuffer(
            .{
                .transfer_buffer = mesh.vertex_index_transfer_buffer,
                .offset = 0,
            },
            .{
                .buffer = mesh.vertex_buffer,
                .offset = 0,
                .size = mesh.vertex_data_size,
            },
            false,
        );
        copy_pass.uploadToBuffer(
            .{
                .transfer_buffer = mesh.vertex_index_transfer_buffer,
                .offset = mesh.vertex_data_size,
            },
            .{
                .buffer = mesh.index_buffer,
                .offset = 0,
                .size = mesh.index_data_size,
            },
            false,
        );

        device.releaseTransferBuffer(mesh.vertex_index_transfer_buffer);
    }
}

pub fn quit_pipeline(
    game_context: *GameContext,
) !void {
    const app_context = game_context.app_context;
    const mesh_context = game_context.mesh_context;

    var mesh_iterator = mesh_context.iterator();
    while (mesh_iterator.next()) |mesh_entry| {
        const mesh = mesh_entry.value_ptr;

        app_context.device.releaseBuffer(mesh.vertex_buffer);
        app_context.device.releaseBuffer(mesh.index_buffer);
        app_context.device.releaseBuffer(mesh.instance_buffer);

        app_context.device.releaseTransferBuffer(mesh.instance_transfer_buffer);
    }
}
