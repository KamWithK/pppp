const std = @import("std");
const sdl3 = @import("sdl3");
const zm = @import("zmath");
const zmesh = @import("zmesh");
const assets = @import("assets");

const GameContext = @import("state.zig").GameContext;
const AppContext = @import("state.zig").AppContext;
const InstanceContext = @import("state.zig").InstanceContext;
const CameraData = @import("state.zig").CameraData;

const Vertex = struct {
    positions: [3]f32,
    texcoords: [2]f32,
};

const SCREEN_WIDTH = @import("game.zig").SCREEN_WIDTH;
const SCREEN_HEIGHT = @import("game.zig").SCREEN_HEIGHT;
const SHADER_FORMATS = @import("game.zig").SHADER_FORMATS;

const MAX_INSTANCES = 1000;
const INSTACE_BUFFER_SIZE = MAX_INSTANCES * @sizeOf(zm.Mat);

pub fn init_pipeline(allocator: std.mem.Allocator, app_context: AppContext) !InstanceContext {
    const device = app_context.device;

    const shader_bin = assets.shaders.@"instanced_render.spv";
    const image_asset = assets.sprites.@"conveyor.png";

    zmesh.init(allocator);

    const vert_shader = try device.createShader(.{
        .code = shader_bin,
        .format = SHADER_FORMATS,
        .stage = .vertex,
        .entry_point = "vertexmain",
        .num_samplers = 0,
        .num_uniform_buffers = 1,
        .num_storage_buffers = 1,
        .num_storage_textures = 0,
    });
    defer device.releaseShader(vert_shader);

    const frag_shader = try device.createShader(.{
        .code = shader_bin,
        .format = SHADER_FORMATS,
        .stage = .fragment,
        .entry_point = "fragmentmain",
        .num_samplers = 1,
        .num_uniform_buffers = 0,
        .num_storage_buffers = 0,
        .num_storage_textures = 0,
    });
    defer device.releaseShader(frag_shader);

    const image_stream = try sdl3.io_stream.Stream.initFromConstMem(image_asset);
    const image_surface = try sdl3.image.loadIo(image_stream, true);
    defer image_surface.deinit();

    const mesh = zmesh.Shape.initPlane(1, 1);
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

    const pipeline = try device.createGraphicsPipeline(.{
        .target_info = .{
            .color_target_descriptions = &.{
                .{
                    .format = device.getSwapchainTextureFormat(app_context.window),
                },
            },
            .depth_stencil_format = .depth16_unorm,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .enable_stencil_test = false,
            .compare = .less,
            .write_mask = 0xFF,
        },
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &.{.{
                .slot = 0,
                .pitch = @sizeOf(Vertex),
                .input_rate = .vertex,
                .instance_step_rate = 0,
            }},
            .vertex_attributes = &.{
                .{
                    .location = 0,
                    .buffer_slot = 0,
                    .format = .f32x3,
                    .offset = 0,
                },
                .{
                    .location = 1,
                    .buffer_slot = 0,
                    .format = .f32x2,
                    .offset = @offsetOf(Vertex, "texcoords"),
                },
            },
        },
        .primitive_type = .triangle_list,
        .rasterizer_state = .{ .fill_mode = .fill },
        .vertex_shader = vert_shader,
        .fragment_shader = frag_shader,
    });
    errdefer device.releaseGraphicsPipeline(pipeline);

    const sampler = try device.createSampler(.{
        .min_filter = .linear,
        .mag_filter = .linear,
        .mipmap_mode = .linear,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
        .address_mode_w = .repeat,
    });

    const atlas_texture = try device.createTexture(.{
        .format = .r8g8b8a8_unorm,
        .width = @intCast(image_surface.getWidth()),
        .height = @intCast(image_surface.getHeight()),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .usage = .{ .sampler = true },
        .props = .{ .name = "sprite atlas" },
    });
    errdefer device.releaseTexture(atlas_texture);

    const depth_texture = try device.createTexture(.{
        .texture_type = .two_dimensional,
        .format = .depth16_unorm,
        .width = SCREEN_WIDTH,
        .height = SCREEN_HEIGHT,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = .no_multisampling,
        .usage = .{ .sampler = true, .depth_stencil_target = true },
        .props = .{ .name = "sprite atlas" },
    });
    errdefer device.releaseTexture(depth_texture);

    const atlas_transfer_buffer = try device.createTransferBuffer(.{
        .usage = .upload,
        .size = @intCast(image_surface.getWidth() * image_surface.getHeight() * 4),
    });
    defer device.releaseTransferBuffer(atlas_transfer_buffer);
    const atlas_pixels = image_surface.getPixels() orelse return error.InvalidData;
    @memcpy(
        try device.mapTransferBuffer(atlas_transfer_buffer, false),
        atlas_pixels,
    );
    device.unmapTransferBuffer(atlas_transfer_buffer);

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

    const command_buffer = try device.acquireCommandBuffer();
    const copy_pass = command_buffer.beginCopyPass();
    copy_pass.uploadToTexture(.{
        .transfer_buffer = atlas_transfer_buffer,
        .offset = 0,
    }, .{
        .texture = atlas_texture,
        .width = @intCast(image_surface.getWidth()),
        .height = @intCast(image_surface.getHeight()),
        .depth = 1,
    }, false);
    copy_pass.uploadToBuffer(
        .{
            .transfer_buffer = vertex_index_transfer_buffer,
            .offset = 0,
        },
        .{
            .buffer = vertex_buffer,
            .offset = 0,
            .size = vertex_data_size,
        },
        false,
    );
    copy_pass.uploadToBuffer(
        .{
            .transfer_buffer = vertex_index_transfer_buffer,
            .offset = vertex_data_size,
        },
        .{
            .buffer = index_buffer,
            .offset = 0,
            .size = index_data_size,
        },
        false,
    );
    copy_pass.end();
    try command_buffer.submit();

    return .{
        .pipeline = pipeline,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .vertex_index_transfer_buffer = vertex_index_transfer_buffer,
        .instance_buffer = instance_buffer,
        .instance_transfer_buffer = instance_transfer_buffer,
        .atlas_texture = atlas_texture,
        .depth_texture = depth_texture,
        .mesh = mesh,
        .sampler = sampler,
    };
}

pub fn map_transfer_buffer(game_context: *GameContext, instances: []const zm.Mat) !void {
    const app_context = game_context.app_context;
    const instance_context = game_context.instance_context;

    const instance_transfer_buffer_mapped = try app_context.device.mapTransferBuffer(
        instance_context.instance_transfer_buffer,
        true,
    );
    @memcpy(instance_transfer_buffer_mapped, std.mem.sliceAsBytes(instances));
    app_context.device.unmapTransferBuffer(instance_context.instance_transfer_buffer);
}

pub fn copy_buffers(instance_context: InstanceContext, instances: []const zm.Mat, copy_pass: sdl3.gpu.CopyPass) !void {
    copy_pass.uploadToBuffer(
        .{
            .transfer_buffer = instance_context.instance_transfer_buffer,
            .offset = 0,
        },
        .{
            .buffer = instance_context.instance_buffer,
            .offset = 0,
            .size = @intCast(@sizeOf(zm.Mat) * instances.len),
        },
        true,
    );
}

pub fn depth_stencil(instance_context: InstanceContext) sdl3.gpu.DepthStencilTargetInfo {
    return .{
        .texture = instance_context.depth_texture,
        .clear_depth = 1,
        .load = .clear,
        .store = .store,
        .stencil_load = .clear,
        .stencil_store = .store,
        .cycle = true,
        .clear_stencil = 0,
    };
}

pub fn iterate_pipeline(
    instance_context: InstanceContext,
    instances: []const zm.Mat,
    camera_data: CameraData,
    command_buffer: sdl3.gpu.CommandBuffer,
    render_pass: sdl3.gpu.RenderPass,
) !void {
    render_pass.bindGraphicsPipeline(instance_context.pipeline);

    render_pass.bindVertexBuffers(0, &.{.{
        .buffer = instance_context.vertex_buffer,
        .offset = 0,
    }});
    render_pass.bindIndexBuffer(
        .{
            .buffer = instance_context.index_buffer,
            .offset = 0,
        },
        .indices_16bit,
    );
    render_pass.bindVertexStorageBuffers(
        0,
        &.{instance_context.instance_buffer},
    );
    render_pass.bindFragmentSamplers(
        0,
        &.{.{
            .texture = instance_context.atlas_texture,
            .sampler = instance_context.sampler,
        }},
    );

    command_buffer.pushVertexUniformData(0, std.mem.asBytes(&camera_data));

    render_pass.drawIndexedPrimitives(
        @intCast(instance_context.mesh.indices.len),
        @intCast(instances.len),
        0,
        0,
        0,
    );
}

pub fn quit_pipeline(
    game_context: *GameContext,
) !void {
    const app_context = game_context.app_context;
    const instance_context = game_context.instance_context;

    app_context.device.releaseBuffer(instance_context.vertex_buffer);
    app_context.device.releaseBuffer(instance_context.index_buffer);
    app_context.device.releaseTransferBuffer(instance_context.vertex_index_transfer_buffer);
    app_context.device.releaseBuffer(instance_context.instance_buffer);
    app_context.device.releaseTransferBuffer(instance_context.instance_transfer_buffer);
    app_context.device.releaseGraphicsPipeline(instance_context.pipeline);
    app_context.device.releaseSampler(instance_context.sampler);
    app_context.device.releaseTexture(instance_context.atlas_texture);
    app_context.device.releaseTexture(instance_context.depth_texture);

    // zmesh.deinit();
}
