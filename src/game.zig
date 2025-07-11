const std = @import("std");
const sdl3 = @import("sdl3");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

const AppContext = @import("state.zig").AppContext;

const PositionTextureVertex = struct {
    x: f32,
    y: f32,
    z: f32,
    u: f32,
    v: f32,
};

const SCREEN_WIDTH = 1920;
const SCREEN_HEIGHT = 1080;
const DEBUG_MODE = true;
const SHADER_FORMATS = sdl3.gpu.ShaderFormatFlags{ .spirv = true };
const WINDOW_FLAGS = sdl3.video.Window.Flags{ .resizable = true, .borderless = true };

const image_shader_bin = @embedFile("shaders/image.spv");
const image_asset = @embedFile("sprites/conveyor.png");

var pipeline: ?sdl3.gpu.GraphicsPipeline = null;

pub fn init(
    app_context: *?*AppContext,
) !sdl3.AppResult {
    const window = try sdl3.video.Window.init("Pixel Perfect Painted Pipeline", SCREEN_WIDTH, SCREEN_HEIGHT, WINDOW_FLAGS);
    errdefer window.deinit();

    const device = try sdl3.gpu.Device.init(SHADER_FORMATS, DEBUG_MODE, null);
    errdefer device.deinit();

    try device.claimWindow(window);

    const vert_shader = try device.createShader(.{
        .code = image_shader_bin,
        .format = SHADER_FORMATS,
        .stage = .vertex,
        .entry_point = "vertexmain",
        .num_samplers = 0,
        .num_uniform_buffers = 0,
        .num_storage_buffers = 0,
        .num_storage_textures = 0,
    });
    defer device.releaseShader(vert_shader);

    const frag_shader = try device.createShader(.{
        .code = image_shader_bin,
        .format = SHADER_FORMATS,
        .stage = .fragment,
        .entry_point = "fragmentmain",
        .num_samplers = 1,
        .num_uniform_buffers = 0,
        .num_storage_buffers = 0,
        .num_storage_textures = 0,
    });
    defer device.releaseShader(frag_shader);

    const image_stream = sdl3.io_stream.Stream.initFromConstMem(image_asset) catch return .failure;
    const image_surface = sdl3.image.loadIo(image_stream, true) catch return .failure;
    errdefer image_surface.deinit();

    const pipeline_create_info = sdl3.gpu.GraphicsPipelineCreateInfo{
        .target_info = .{
            .color_target_descriptions = &.{
                .{
                    .format = device.getSwapchainTextureFormat(window),
                },
            },
        },
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &.{.{
                .slot = 0,
                .input_rate = .vertex,
                .instance_step_rate = 0,
                .pitch = @sizeOf(PositionTextureVertex),
            }},
            .vertex_attributes = &.{
                .{
                    .buffer_slot = 0,
                    .format = .f32x3,
                    .location = 0,
                    .offset = 0,
                },
                .{
                    .buffer_slot = 0,
                    .format = .f32x2,
                    .location = 1,
                    .offset = @sizeOf(f32) * 3,
                },
            },
        },
        .vertex_shader = vert_shader,
        .fragment_shader = frag_shader,
    };

    pipeline = try device.createGraphicsPipeline(pipeline_create_info);
    errdefer device.releaseGraphicsPipeline(pipeline.?);

    if (pipeline == null) return .failure;

    const sampler = device.createSampler(.{
        .min_filter = .nearest,
        .mag_filter = .nearest,
        .mipmap_mode = .nearest,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
    }) catch return .failure;

    const vertex_data = [_]PositionTextureVertex{
        .{ .x = -1, .y = 1, .z = 0, .u = 0, .v = 0 },
        .{ .x = 1, .y = 1, .z = 0, .u = 1, .v = 0 },
        .{ .x = 1, .y = -1, .z = 0, .u = 1, .v = 1 },
        .{ .x = -1, .y = -1, .z = 0, .u = 0, .v = 1 },
    };
    const index_data = [_]u16{ 0, 1, 2, 0, 2, 3 };

    const vertex_data_size: u32 = @intCast(@sizeOf(@TypeOf(vertex_data)));
    const index_data_size: u32 = @intCast(@sizeOf(@TypeOf(index_data)));

    const vertex_buffer = device.createBuffer(.{
        .usage = .{ .vertex = true },
        .size = vertex_data_size,
        .props = .{
            .name = "image vertex buffer",
        },
    }) catch return .failure;
    errdefer device.releaseBuffer(vertex_buffer);
    const index_buffer = device.createBuffer(.{
        .usage = .{ .index = true },
        .size = index_data_size,
        .props = .{
            .name = "image index buffer",
        },
    }) catch return .failure;
    errdefer device.releaseBuffer(index_buffer);

    const image_texture = device.createTexture(.{
        .format = .r8g8b8a8_unorm,
        .width = @intCast(image_surface.getWidth()),
        .height = @intCast(image_surface.getHeight()),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .usage = .{ .sampler = true },
        .props = .{ .name = "lettuce texture" },
    }) catch return .failure;
    errdefer device.releaseTexture(image_texture);

    const transfer_buffer = try device.createTransferBuffer(.{
        .usage = .upload,
        .size = vertex_data_size + index_data_size,
    });
    defer device.releaseTransferBuffer(transfer_buffer);
    const transfer_buffer_mapped = @as(
        *@TypeOf(vertex_data),
        @alignCast(@ptrCast(try device.mapTransferBuffer(transfer_buffer, false))),
    );
    transfer_buffer_mapped.* = vertex_data;
    @as(*@TypeOf(index_data), @ptrFromInt(@intFromPtr(transfer_buffer_mapped) + vertex_data_size)).* = index_data;
    device.unmapTransferBuffer(transfer_buffer);

    const texture_buffer = try device.createTransferBuffer(.{
        .usage = .upload,
        .size = @intCast(image_surface.getWidth() * image_surface.getHeight() * 4),
    });
    defer device.releaseTransferBuffer(texture_buffer);
    const texture_transfer_buffer_mapped = try device.mapTransferBuffer(texture_buffer, false);
    @memcpy(texture_transfer_buffer_mapped, image_surface.getPixels().?);
    device.unmapTransferBuffer(texture_buffer);

    const upload_cmd_buf = device.acquireCommandBuffer() catch return .failure;
    const copy_pass = upload_cmd_buf.beginCopyPass();
    copy_pass.uploadToBuffer(.{
        .transfer_buffer = transfer_buffer,
        .offset = 0,
    }, .{
        .buffer = vertex_buffer,
        .offset = 0,
        .size = vertex_data_size,
    }, false);
    copy_pass.uploadToBuffer(.{
        .transfer_buffer = transfer_buffer,
        .offset = vertex_data_size,
    }, .{
        .buffer = index_buffer,
        .offset = 0,
        .size = index_data_size,
    }, false);
    copy_pass.uploadToTexture(.{
        .transfer_buffer = texture_buffer,
        .offset = 0,
    }, .{
        .texture = image_texture,
        .width = @intCast(image_surface.getWidth()),
        .height = @intCast(image_surface.getHeight()),
        .depth = 1,
    }, false);
    copy_pass.end();
    upload_cmd_buf.submit() catch return .failure;

    const context = allocator.create(AppContext) catch return .failure;
    context.* = .{
        .device = device,
        .window = window,
        .pipeline = pipeline.?,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .image_texture = image_texture,
        .sampler = sampler,
    };
    app_context.* = context;

    return .run;
}

pub fn iterate(app_context: *AppContext) !sdl3.AppResult {
    const command_buffer = try app_context.device.acquireCommandBuffer();
    const swapchain_texture = try command_buffer.waitAndAcquireSwapchainTexture(app_context.window);

    if (swapchain_texture.texture) |texture| {
        const render_pass = command_buffer.beginRenderPass(&.{sdl3.gpu.ColorTargetInfo{
            .texture = texture,
            .clear_color = .{ .r = 0.5, .g = 0, .b = 0.5, .a = 1 },
            .load = .clear,
            .store = .store,
        }}, null);
        defer render_pass.end();

        render_pass.bindGraphicsPipeline(app_context.pipeline);

        render_pass.bindVertexBuffers(0, &.{.{
            .buffer = app_context.vertex_buffer,
            .offset = 0,
        }});
        render_pass.bindIndexBuffer(.{
            .buffer = app_context.index_buffer,
            .offset = 0,
        }, .indices_16bit);
        render_pass.bindFragmentSamplers(
            0,
            &.{.{
                .texture = app_context.image_texture,
                .sampler = app_context.sampler,
            }},
        );

        render_pass.drawIndexedPrimitives(6, 1, 0, 0, 0);
    }

    try command_buffer.submit();

    return .run;
}

pub fn event(
    app_context: *AppContext,
    curr_event: *const sdl3.events.Event,
) !sdl3.AppResult {
    _ = app_context;

    return switch (curr_event.*) {
        .quit => .success,
        .terminating => .success,
        else => .run,
    };
}

pub fn quit(
    app_context: *AppContext,
    result: sdl3.AppResult,
) !void {
    _ = result;
    app_context.device.releaseWindow(app_context.window);
    app_context.window.deinit();
    app_context.device.deinit();
    arena.deinit();
}
