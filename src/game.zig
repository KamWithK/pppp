const std = @import("std");
const sdl3 = @import("sdl3");
const assets = @import("assets");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

const AppContext = @import("state.zig").AppContext;

const SpriteInstance = struct {
    position: [3]f32,
    rotation: f32,
    size: [2]f32,
    padding: [2]f32,
    uv: [2]f32,
    tex: [2]f32,
    rgba: [4]f32,
};
const test_instances = [_]SpriteInstance{
    .{
        .position = .{ 0, 0, 0 },
        .rotation = 0,
        .size = .{ 32, 32 },
        .padding = .{ 0, 0 },
        .uv = .{ 0, 0 },
        .tex = .{ 1, 0.5 },
        .rgba = .{ 1, 1, 1, 1 },
    },
    .{
        .position = .{ 32, 32, 0 },
        .rotation = 0,
        .size = .{ 32, 32 },
        .padding = .{ 0, 0 },
        .uv = .{ 0, 0.5 },
        .tex = .{ 1, 0.5 },
        .rgba = .{ 1, 1, 1, 1 },
    },
};

const sprite_instance_size = @sizeOf(SpriteInstance);
const sprite_data_size = @sizeOf(@TypeOf(test_instances));

const SCREEN_WIDTH = 1920;
const SCREEN_HEIGHT = 1080;
const DEBUG_MODE = true;
const SHADER_FORMATS = sdl3.gpu.ShaderFormatFlags{ .spirv = true };
const WINDOW_FLAGS = sdl3.video.Window.Flags{ .resizable = true, .borderless = true };

const PROJECTION_MATRIX = [4][4]f32{
    .{ 2.0 / @as(f32, SCREEN_WIDTH), 0, 0, 0 },
    .{ 0, -2.0 / @as(f32, SCREEN_HEIGHT), 0, 0 },
    .{ 0, 0, 1, 0 },
    .{ -1, 1, 0, 1 },
};

pub fn init(
    app_context: *?*AppContext,
) !sdl3.AppResult {
    const image_shader_bin = assets.get.file("/shaders/image.spv");
    const image_asset = assets.get.file("/sprites/conveyor.png");

    try sdl3.init(.{
        .gamepad = true,
    });

    const window = sdl3.video.Window.init("Pixel Perfect Painted Pipeline", SCREEN_WIDTH, SCREEN_HEIGHT, WINDOW_FLAGS) catch return .failure;
    errdefer window.deinit();

    const device = sdl3.gpu.Device.init(SHADER_FORMATS, DEBUG_MODE, null) catch return .failure;
    errdefer device.deinit();

    device.claimWindow(window) catch return .failure;

    const vert_shader = device.createShader(.{
        .code = image_shader_bin,
        .format = SHADER_FORMATS,
        .stage = .vertex,
        .entry_point = "vertexmain",
        .num_samplers = 0,
        .num_uniform_buffers = 1,
        .num_storage_buffers = 1,
        .num_storage_textures = 0,
    }) catch return .failure;
    defer device.releaseShader(vert_shader);

    const frag_shader = device.createShader(.{
        .code = image_shader_bin,
        .format = SHADER_FORMATS,
        .stage = .fragment,
        .entry_point = "fragmentmain",
        .num_samplers = 1,
        .num_uniform_buffers = 0,
        .num_storage_buffers = 0,
        .num_storage_textures = 0,
    }) catch return .failure;
    defer device.releaseShader(frag_shader);

    const image_stream = sdl3.io_stream.Stream.initFromConstMem(image_asset) catch return .failure;
    const image_surface = sdl3.image.loadIo(image_stream, true) catch return .failure;
    defer image_surface.deinit();

    const pipeline_create_info = sdl3.gpu.GraphicsPipelineCreateInfo{
        .target_info = .{
            .color_target_descriptions = &.{
                .{
                    .format = device.getSwapchainTextureFormat(window),
                },
            },
        },
        .vertex_shader = vert_shader,
        .fragment_shader = frag_shader,
    };

    const pipeline = device.createGraphicsPipeline(pipeline_create_info) catch return .failure;
    errdefer device.releaseGraphicsPipeline(pipeline);

    const sampler = device.createSampler(.{
        .min_filter = .nearest,
        .mag_filter = .nearest,
        .mipmap_mode = .nearest,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
    }) catch return .failure;

    const atlas_texture = device.createTexture(.{
        .format = .r8g8b8a8_unorm,
        .width = @intCast(image_surface.getWidth()),
        .height = @intCast(image_surface.getHeight()),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .usage = .{ .sampler = true },
        .props = .{ .name = "sprite atlas" },
    }) catch return .failure;
    errdefer device.releaseTexture(atlas_texture);

    const atlas_transfer_buffer = device.createTransferBuffer(.{
        .usage = .upload,
        .size = @intCast(image_surface.getWidth() * image_surface.getHeight() * 4),
    }) catch return .failure;
    defer device.releaseTransferBuffer(atlas_transfer_buffer);
    const atlas_pixels = image_surface.getPixels() orelse return .failure;
    @memcpy(
        device.mapTransferBuffer(atlas_transfer_buffer, false) catch return .failure,
        atlas_pixels,
    );
    device.unmapTransferBuffer(atlas_transfer_buffer);

    const instance_buffer = device.createBuffer(.{
        .usage = .{ .graphics_storage_read = true },
        .size = sprite_data_size,
    }) catch return .failure;
    const instance_transfer_buffer = device.createTransferBuffer(.{
        .usage = .upload,
        .size = sprite_data_size,
    }) catch return .failure;

    const command_buffer = device.acquireCommandBuffer() catch return .failure;
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
            .transfer_buffer = instance_transfer_buffer,
            .offset = 0,
        },
        .{
            .buffer = instance_buffer,
            .offset = 0,
            .size = sprite_data_size,
        },
        true,
    );
    copy_pass.end();
    command_buffer.submit() catch return .failure;

    const context = allocator.create(AppContext) catch return .failure;
    context.* = .{
        .device = device,
        .window = window,
        .pipeline = pipeline,
        .instance_buffer = instance_buffer,
        .instance_transfer_buffer = instance_transfer_buffer,
        .atlas_texture = atlas_texture,
        .sampler = sampler,
    };
    app_context.* = context;

    return .run;
}

pub fn iterate(app_context: *AppContext) !sdl3.AppResult {
    const instance_transfer_buffer_mapped = @as(
        *@TypeOf(test_instances),
        @alignCast(@ptrCast(
            app_context.device.mapTransferBuffer(
                app_context.instance_transfer_buffer,
                true,
            ) catch return .failure,
        )),
    );
    instance_transfer_buffer_mapped.* = test_instances;
    app_context.device.unmapTransferBuffer(app_context.instance_transfer_buffer);

    const command_buffer = app_context.device.acquireCommandBuffer() catch return .failure;

    const copy_pass = command_buffer.beginCopyPass();
    copy_pass.uploadToBuffer(
        .{
            .transfer_buffer = app_context.instance_transfer_buffer,
            .offset = 0,
        },
        .{
            .buffer = app_context.instance_buffer,
            .offset = 0,
            .size = sprite_data_size,
        },
        true,
    );
    copy_pass.end();

    const swapchain_texture = command_buffer.waitAndAcquireSwapchainTexture(app_context.window) catch return .failure;

    if (swapchain_texture.texture) |texture| {
        const render_pass = command_buffer.beginRenderPass(
            &.{sdl3.gpu.ColorTargetInfo{
                .texture = texture,
                .clear_color = .{ .r = 0.5, .g = 0, .b = 0.5, .a = 1 },
                .load = .clear,
                .store = .store,
            }},
            null,
        );
        defer render_pass.end();

        render_pass.bindGraphicsPipeline(app_context.pipeline);

        render_pass.bindVertexStorageBuffers(
            0,
            &.{app_context.instance_buffer},
        );
        render_pass.bindFragmentSamplers(
            0,
            &.{.{
                .texture = app_context.atlas_texture,
                .sampler = app_context.sampler,
            }},
        );
        command_buffer.pushVertexUniformData(0, std.mem.sliceAsBytes(&PROJECTION_MATRIX));

        render_pass.drawPrimitives(6 * test_instances.len, 1, 0, 0);
    }

    command_buffer.submit() catch return .failure;

    return .run;
}

pub fn event(
    app_context: *AppContext,
    curr_event: *const sdl3.events.Event,
) !sdl3.AppResult {
    switch (curr_event.*) {
        .quit => return .success,
        .terminating => return .success,
        .key_down => {},
        .gamepad_added => {
            app_context.gamepad = try sdl3.gamepad.Gamepad.init(curr_event.gamepad_added.id);
        },
        .gamepad_removed => {
            if (app_context.gamepad) |gamepad| gamepad.deinit();
            app_context.gamepad = null;
        },
        .gamepad_axis_motion => {},
        else => {},
    }

    return .run;
}

pub fn quit(
    app_context: *AppContext,
    result: sdl3.AppResult,
) !void {
    _ = result;
    app_context.device.releaseWindow(app_context.window);
    app_context.device.releaseBuffer(app_context.instance_buffer);
    app_context.device.releaseTransferBuffer(app_context.instance_transfer_buffer);
    app_context.device.releaseGraphicsPipeline(app_context.pipeline);
    app_context.device.releaseSampler(app_context.sampler);
    app_context.device.releaseTexture(app_context.atlas_texture);
    app_context.window.deinit();
    app_context.device.deinit();
    if (app_context.gamepad) |gamepad| gamepad.deinit();
    arena.deinit();
}
