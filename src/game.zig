const std = @import("std");
const sdl3 = @import("sdl3");
const zm = @import("zmath");
const zmesh = @import("zmesh");
const assets = @import("assets");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

const GameContext = @import("state.zig").GameContext;
const CameraData = @import("state.zig").CameraData;
const Instance = @import("instance.zig");

pub const SCREEN_WIDTH = 1920;
pub const SCREEN_HEIGHT = 1080;
pub const SHADER_FORMATS = sdl3.gpu.ShaderFormatFlags{ .spirv = true };
const WINDOW_FLAGS = sdl3.video.Window.Flags{ .resizable = true, .borderless = true };
const DEBUG_MODE = true;
const MOVEMENT_SPEED = 0.005;
const KEYBOARD_MOVEMENT_UNIT = 1;

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
    game_context: *?*GameContext,
) !sdl3.AppResult {
    try sdl3.init(.{
        .gamepad = true,
    });

    const window = sdl3.video.Window.init("Pixel Perfect Painted Pipeline", SCREEN_WIDTH, SCREEN_HEIGHT, WINDOW_FLAGS) catch return .failure;
    errdefer window.deinit();

    const device = sdl3.gpu.Device.init(SHADER_FORMATS, DEBUG_MODE, null) catch return .failure;
    errdefer device.deinit();

    device.claimWindow(window) catch return .failure;

    const context = allocator.create(GameContext) catch return .failure;
    context.app_context = .{
        .device = device,
        .window = window,
        .previous_time = sdl3.timer.getMillisecondsSinceInit(),
        .camera = .{ 0, 3, 10, 0 },
    };
    context.instance_context = try Instance.init_pipeline(allocator, context.app_context);
    context.input_context = .{};
    game_context.* = context;

    return .run;
}

pub fn iterate(game_context: *GameContext) !sdl3.AppResult {
    const current_time = sdl3.timer.getMillisecondsSinceInit();

    const app_context = &game_context.app_context;
    const input_context = &game_context.input_context;

    const delta_time: f32 = @floatFromInt(current_time - app_context.previous_time);
    app_context.previous_time = current_time;

    const delta_scale = MOVEMENT_SPEED * delta_time;
    const raw_vector = zm.Vec{
        input_context.movement_x,
        0,
        input_context.movement_y,
        0,
    };
    const direction_vector = if (input_context.movement_x != 0 or input_context.movement_y != 0) zm.normalize3(raw_vector) else raw_vector;
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

    const test_instances: []const zm.Mat = &.{
        zm.identity(),
        zm.translation(3, 4, 5),
    };

    const camera_data = CameraData{
        .view = zm.lookAtLh(app_context.camera, cam_target, cam_up),
        .projection = zm.perspectiveFovLh(
            std.math.degreesToRadians(45),
            @as(f32, @floatFromInt(SCREEN_WIDTH)) / @as(f32, @floatFromInt(SCREEN_HEIGHT)),
            0.1,
            100,
        ),
    };

    try Instance.map_transfer_buffer(game_context, test_instances);

    const command_buffer = app_context.device.acquireCommandBuffer() catch return .failure;

    const copy_pass = command_buffer.beginCopyPass();
    try Instance.copy_buffers(game_context.instance_context, test_instances, copy_pass);
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
            Instance.depth_stencil(game_context.instance_context),
        );
        defer render_pass.end();

        try Instance.iterate_pipeline(
            game_context.instance_context,
            test_instances,
            camera_data,
            command_buffer,
            render_pass,
        );
    }

    command_buffer.submit() catch return .failure;

    return .run;
}

pub fn event(
    game_context: *GameContext,
    curr_event: *const sdl3.events.Event,
) !sdl3.AppResult {
    var app_context = &game_context.app_context;
    var input_context = &game_context.input_context;

    switch (curr_event.*) {
        .quit => return .success,
        .terminating => return .success,
        .key_down => {
            const key = curr_event.key_down.key orelse return .run;
            switch (key) {
                .up => input_context.movement_y = -KEYBOARD_MOVEMENT_UNIT,
                .left => input_context.movement_x = -KEYBOARD_MOVEMENT_UNIT,
                .down => input_context.movement_y = KEYBOARD_MOVEMENT_UNIT,
                .right => input_context.movement_x = KEYBOARD_MOVEMENT_UNIT,
                .w => input_context.movement_y = -KEYBOARD_MOVEMENT_UNIT,
                .a => input_context.movement_x = -KEYBOARD_MOVEMENT_UNIT,
                .s => input_context.movement_y = KEYBOARD_MOVEMENT_UNIT,
                .d => input_context.movement_x = KEYBOARD_MOVEMENT_UNIT,
                else => {},
            }
        },
        .key_up => {
            const key = curr_event.key_up.key orelse return .run;
            switch (key) {
                .up => input_context.movement_y = 0,
                .left => input_context.movement_x = 0,
                .down => input_context.movement_y = 0,
                .right => input_context.movement_x = 0,
                .w => input_context.movement_y = 0,
                .a => input_context.movement_x = 0,
                .s => input_context.movement_y = 0,
                .d => input_context.movement_x = 0,
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
                .left_x => input_context.movement_x = normalize_axis(axis_motion.value, 0.1),
                .left_y => input_context.movement_y = normalize_axis(axis_motion.value, 0.1),
                else => {},
            }
        },
        else => {},
    }

    return .run;
}

pub fn quit(
    game_context: *GameContext,
    result: sdl3.AppResult,
) !void {
    _ = result;
    const app_context = &game_context.app_context;

    if (app_context.gamepad) |gamepad| gamepad.deinit();
    try Instance.quit_pipeline(game_context);

    app_context.device.releaseWindow(app_context.window);
    app_context.window.deinit();
    app_context.device.deinit();

    arena.deinit();
}
