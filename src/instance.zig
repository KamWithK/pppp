const std = @import("std");
const sdl3 = @import("sdl3");
const zm = @import("zmath");

const GameContext = @import("state.zig").GameContext;
const AppContext = @import("state.zig").AppContext;
const InstanceContext = @import("state.zig").InstanceContext;
const CameraData = @import("state.zig").CameraData;
const Vertex = @import("state.zig").Vertex;
const MeshInfo = @import("state.zig").MeshInfo;

pub const InstanceData = []const zm.Mat;

const SCREEN_WIDTH = @import("game.zig").SCREEN_WIDTH;
const SCREEN_HEIGHT = @import("game.zig").SCREEN_HEIGHT;
const SHADER_FORMATS = @import("game.zig").SHADER_FORMATS;

pub fn init_pipeline(allocator: std.mem.Allocator, app_context: AppContext) !InstanceContext {
    const device = app_context.device;

    const shader_bin = try sdl3.io_stream.loadFile(
        try app_context.pathToZ(allocator, "assets/shaders/instanced_render.spv"),
    );

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

    return .{
        .pipeline = pipeline,
        .depth_texture = depth_texture,
        .sampler = sampler,
    };
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

pub fn map_transfer_buffers(game_context: *GameContext, instances: std.StringArrayHashMap(InstanceData)) !void {
    const device = game_context.app_context.device;

    var iterator = instances.iterator();

    while (iterator.next()) |instance_entry| {
        const key = instance_entry.key_ptr.*;
        const instance = instance_entry.value_ptr.*;

        const mesh = game_context.mesh_context.get(key) orelse continue;

        const transfer_buffer_mapped = try device.mapTransferBuffer(
            mesh.instance_transfer_buffer,
            true,
        );
        @memcpy(transfer_buffer_mapped, std.mem.sliceAsBytes(instance));
        device.unmapTransferBuffer(mesh.instance_transfer_buffer);
    }
}

pub fn copy_buffers(
    game_context: *GameContext,
    instances: std.StringArrayHashMap(InstanceData),
    copy_pass: sdl3.gpu.CopyPass,
) !void {
    var iterator = instances.iterator();

    while (iterator.next()) |instance_entry| {
        const key = instance_entry.key_ptr.*;
        const instance = instance_entry.value_ptr;

        const mesh = game_context.mesh_context.get(key) orelse continue;

        copy_pass.uploadToBuffer(.{
            .transfer_buffer = mesh.instance_transfer_buffer,
            .offset = 0,
        }, .{
            .buffer = mesh.instance_buffer,
            .offset = 0,
            .size = @intCast(@sizeOf(zm.Mat) * instance.len),
        }, true);
    }
}

pub fn iterate_pipeline(
    game_context: GameContext,
    instances: std.StringArrayHashMap(InstanceData),
    camera_data: CameraData,
    command_buffer: sdl3.gpu.CommandBuffer,
    render_pass: sdl3.gpu.RenderPass,
) !void {
    render_pass.bindGraphicsPipeline(game_context.instance_context.pipeline);

    var iterator = instances.iterator();

    while (iterator.next()) |instance_entry| {
        const key = instance_entry.key_ptr.*;
        const instance = instance_entry.value_ptr;
        const mesh = game_context.mesh_context.get(key) orelse continue;

        render_pass.bindVertexBuffers(0, &.{.{
            .buffer = mesh.vertex_buffer,
            .offset = 0,
        }});
        render_pass.bindIndexBuffer(
            .{
                .buffer = mesh.index_buffer,
                .offset = 0,
            },
            .indices_16bit,
        );
        render_pass.bindVertexStorageBuffers(
            0,
            &.{mesh.instance_buffer},
        );
        render_pass.bindFragmentSamplers(
            0,
            &.{.{
                .texture = game_context.texture_context.texture,
                .sampler = game_context.instance_context.sampler,
            }},
        );

        command_buffer.pushVertexUniformData(0, std.mem.asBytes(&camera_data));

        render_pass.drawIndexedPrimitives(
            mesh.index_count,
            @intCast(instance.len),
            0,
            0,
            0,
        );
    }
}

pub fn quit_pipeline(
    game_context: *GameContext,
) !void {
    const app_context = game_context.app_context;
    const instance_context = game_context.instance_context;

    app_context.device.releaseGraphicsPipeline(instance_context.pipeline);
    app_context.device.releaseSampler(instance_context.sampler);
    app_context.device.releaseTexture(instance_context.depth_texture);
}
