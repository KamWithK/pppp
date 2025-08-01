const std = @import("std");
const sdl3 = @import("sdl3");
const zm = @import("zmath");
const zmesh = @import("zmesh");
const assets = @import("assets");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

const AppContext = @import("state.zig").AppContext;

const Vertex = struct {
    positions: [3]f32,
    texcoords: [2]f32,
};
const CameraData = struct {
    view: zm.Mat,
    projection: zm.Mat,
};

const MAX_INSTANCES = 1000;
const INSTACE_BUFFER_SIZE = MAX_INSTANCES * @sizeOf(zm.Mat);

const SCREEN_WIDTH = 1920;
const SCREEN_HEIGHT = 1080;
const MOVEMENT_SPEED = 0.005;
const KEYBOARD_MOVEMENT_UNIT = 1;
const DEBUG_MODE = true;
const SHADER_FORMATS = sdl3.gpu.ShaderFormatFlags{ .spirv = true };
const WINDOW_FLAGS = sdl3.video.Window.Flags{ .resizable = true, .borderless = true };

fn normalize_axis(raw: i16, deadzone: f32) f32 {
    const max: f32 = std.math.maxInt(i16);
    const min: f32 = std.math.minInt(i16);
    const value: f32 = @floatFromInt(raw);

    const norm = if (value >= 0.0)
        value / max
    else
        value / -min;

    return if (@abs(norm) > deadzone) norm else 0.0;
}

pub fn init(
    app_context: *?*AppContext,
) !sdl3.AppResult {
    const shader_bin = assets.shaders.@"instanced_render.spv";
    const image_asset = assets.get.file("/sprites/conveyor.png");

    try sdl3.init(.{
        .gamepad = true,
    });
    zmesh.init(allocator);

    const window = sdl3.video.Window.init("Pixel Perfect Painted Pipeline", SCREEN_WIDTH, SCREEN_HEIGHT, WINDOW_FLAGS) catch return .failure;
    errdefer window.deinit();

    const device = sdl3.gpu.Device.init(SHADER_FORMATS, DEBUG_MODE, null) catch return .failure;
    errdefer device.deinit();

    device.claimWindow(window) catch return .failure;

    const vert_shader = device.createShader(.{
        .code = shader_bin,
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
        .code = shader_bin,
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

    const mesh = zmesh.Shape.initPlane(1, 1);
    const mesh_texcoords = mesh.texcoords orelse return .failure;
    const vertex_data = allocator.alloc(Vertex, mesh.positions.len) catch return .failure;
    const index_data = mesh.indices;
    for (mesh.positions, mesh_texcoords, 0..) |positions, texcoords, i| {
        vertex_data[i] = Vertex{
            .positions = positions,
            .texcoords = texcoords,
        };
    }

    const vertex_data_size: u32 = @intCast(@sizeOf(Vertex) * vertex_data.len);
    const index_data_size: u32 = @intCast(@sizeOf(u32) * index_data.len);

    const pipeline_create_info = sdl3.gpu.GraphicsPipelineCreateInfo{
        .target_info = .{
            .color_target_descriptions = &.{
                .{
                    .format = device.getSwapchainTextureFormat(window),
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
    };

    const pipeline = device.createGraphicsPipeline(pipeline_create_info) catch return .failure;
    errdefer device.releaseGraphicsPipeline(pipeline);

    const sampler = device.createSampler(.{
        .min_filter = .linear,
        .mag_filter = .linear,
        .mipmap_mode = .linear,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
        .address_mode_w = .repeat,
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

    const depth_texture = device.createTexture(.{
        .texture_type = .two_dimensional,
        .format = .depth16_unorm,
        .width = SCREEN_WIDTH,
        .height = SCREEN_HEIGHT,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = .no_multisampling,
        .usage = .{ .sampler = true, .depth_stencil_target = true },
        .props = .{ .name = "sprite atlas" },
    }) catch return .failure;
    errdefer device.releaseTexture(depth_texture);

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
        .size = INSTACE_BUFFER_SIZE,
    }) catch return .failure;
    const instance_transfer_buffer = device.createTransferBuffer(.{
        .usage = .upload,
        .size = INSTACE_BUFFER_SIZE,
    }) catch return .failure;

    const vertex_buffer = device.createBuffer(.{
        .usage = .{ .vertex = true },
        .size = vertex_data_size,
    }) catch return .failure;
    const index_buffer = device.createBuffer(.{
        .usage = .{ .index = true },
        .size = index_data_size,
    }) catch return .failure;
    const vertex_index_transfer_buffer = device.createTransferBuffer(.{
        .usage = .upload,
        .size = vertex_data_size + index_data_size,
    }) catch return .failure;

    const vertex_index_transfer_buffer_mapped = try device.mapTransferBuffer(vertex_index_transfer_buffer, false);
    @memcpy(vertex_index_transfer_buffer_mapped, std.mem.sliceAsBytes(vertex_data));
    @memcpy(vertex_index_transfer_buffer_mapped + vertex_data_size, std.mem.sliceAsBytes(index_data));
    device.unmapTransferBuffer(vertex_index_transfer_buffer);

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
    command_buffer.submit() catch return .failure;

    const context = allocator.create(AppContext) catch return .failure;
    context.* = .{
        .device = device,
        .window = window,
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
        .previous_time = sdl3.timer.getMillisecondsSinceInit(),
        .camera = .{ 0, 3, 10, 0 },
    };
    app_context.* = context;

    return .run;
}

pub fn iterate(app_context: *AppContext) !sdl3.AppResult {
    const current_time = sdl3.timer.getMillisecondsSinceInit();
    const delta_time: f32 = @floatFromInt(current_time - app_context.previous_time);
    app_context.previous_time = current_time;

    const delta_scale = MOVEMENT_SPEED * delta_time;
    const raw_vector = zm.Vec{
        app_context.input.movement_x,
        0,
        app_context.input.movement_y,
        0,
    };
    const direction_vector = if (app_context.input.movement_x != 0 or app_context.input.movement_y != 0) zm.normalize3(raw_vector) else raw_vector;
    const movement_vector = direction_vector * zm.f32x4s(delta_scale);
    app_context.camera += movement_vector;
    app_context.camera[1] = 10.0;

    const cam_angle = std.math.degreesToRadians(45);
    const cam_up = zm.Vec{ 0, 1, 0, 0 };
    const cam_target = app_context.camera + zm.Vec{
        0,
        -std.math.sin(cam_angle),
        -std.math.cos(cam_angle),
        0,
    };

    const test_instances: [2]zm.Mat = .{
        zm.identity(),
        zm.translation(3, 4, 5),
    };

    const transforms = CameraData{
        .view = zm.lookAtLh(app_context.camera, cam_target, cam_up),
        .projection = zm.perspectiveFovLh(
            std.math.degreesToRadians(45),
            @as(f32, @floatFromInt(SCREEN_WIDTH)) / @as(f32, @floatFromInt(SCREEN_HEIGHT)),
            0.1,
            100,
        ),
    };

    const instance_transfer_buffer_mapped = app_context.device.mapTransferBuffer(
        app_context.instance_transfer_buffer,
        true,
    ) catch return .failure;
    @memcpy(instance_transfer_buffer_mapped, std.mem.sliceAsBytes(&test_instances));
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
            .size = @sizeOf(@TypeOf(test_instances)),
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
            .{
                .texture = app_context.depth_texture,
                .clear_depth = 1,
                .load = .clear,
                .store = .store,
                .stencil_load = .clear,
                .stencil_store = .store,
                .cycle = true,
                .clear_stencil = 0,
            },
        );
        defer render_pass.end();

        render_pass.bindGraphicsPipeline(app_context.pipeline);

        render_pass.bindVertexBuffers(0, &.{.{
            .buffer = app_context.vertex_buffer,
            .offset = 0,
        }});
        render_pass.bindIndexBuffer(
            .{
                .buffer = app_context.index_buffer,
                .offset = 0,
            },
            .indices_16bit,
        );
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

        command_buffer.pushVertexUniformData(0, std.mem.asBytes(&transforms));

        render_pass.drawIndexedPrimitives(
            @intCast(app_context.mesh.indices.len),
            test_instances.len,
            0,
            0,
            0,
        );
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
        .key_down => {
            const key = curr_event.key_down.key orelse return .run;
            switch (key) {
                .up => app_context.input.movement_y = -KEYBOARD_MOVEMENT_UNIT,
                .left => app_context.input.movement_x = -KEYBOARD_MOVEMENT_UNIT,
                .down => app_context.input.movement_y = KEYBOARD_MOVEMENT_UNIT,
                .right => app_context.input.movement_x = KEYBOARD_MOVEMENT_UNIT,
                .w => app_context.input.movement_y = -KEYBOARD_MOVEMENT_UNIT,
                .a => app_context.input.movement_x = -KEYBOARD_MOVEMENT_UNIT,
                .s => app_context.input.movement_y = KEYBOARD_MOVEMENT_UNIT,
                .d => app_context.input.movement_x = KEYBOARD_MOVEMENT_UNIT,
                else => {},
            }
        },
        .key_up => {
            const key = curr_event.key_up.key orelse return .run;
            switch (key) {
                .up => app_context.input.movement_y = 0,
                .left => app_context.input.movement_x = 0,
                .down => app_context.input.movement_y = 0,
                .right => app_context.input.movement_x = 0,
                .w => app_context.input.movement_y = 0,
                .a => app_context.input.movement_x = 0,
                .s => app_context.input.movement_y = 0,
                .d => app_context.input.movement_x = 0,
                else => {},
            }
        },
        .gamepad_added => {
            app_context.gamepad = try sdl3.gamepad.Gamepad.init(curr_event.gamepad_added.id);
        },
        .gamepad_removed => {
            if (app_context.gamepad) |gamepad| gamepad.deinit();
            app_context.gamepad = null;
        },
        .gamepad_axis_motion => {
            const axis_motion = curr_event.gamepad_axis_motion;

            switch (axis_motion.axis) {
                .left_x => app_context.input.movement_x = normalize_axis(axis_motion.value, 0.1),
                .left_y => app_context.input.movement_y = normalize_axis(axis_motion.value, 0.1),
                else => {},
            }
        },
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
    app_context.device.releaseBuffer(app_context.vertex_buffer);
    app_context.device.releaseBuffer(app_context.index_buffer);
    app_context.device.releaseTransferBuffer(app_context.vertex_index_transfer_buffer);
    app_context.device.releaseBuffer(app_context.instance_buffer);
    app_context.device.releaseTransferBuffer(app_context.instance_transfer_buffer);
    app_context.device.releaseGraphicsPipeline(app_context.pipeline);
    app_context.device.releaseSampler(app_context.sampler);
    app_context.device.releaseTexture(app_context.atlas_texture);
    app_context.device.releaseTexture(app_context.depth_texture);
    app_context.window.deinit();
    app_context.device.deinit();
    if (app_context.gamepad) |gamepad| gamepad.deinit();
    // zmesh.deinit();
    arena.deinit();
}
