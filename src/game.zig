const std = @import("std");
const sdl3 = @import("sdl3");

const AppState = @import("state.zig").AppState;

const allocator = std.heap.smp_allocator;

const SCREEN_WIDTH = 1920;
const SCREEN_HEIGHT = 1080;

pub fn init(
    app_state: *?*AppState,
) !sdl3.AppResult {
    const window = try sdl3.video.Window.init("Pixel Perfect Painted Pipeline", SCREEN_WIDTH, SCREEN_HEIGHT, .{});
    const render = try sdl3.render.Renderer.init(window, null);
    const state = try allocator.create(AppState);
    state.* = .{
        .window = window,
        .render = render,
    };
    app_state.* = state;

    return .run;
}

pub fn iterate(app_state: *AppState) !sdl3.AppResult {
    const surface = try app_state.window.getSurface();

    try surface.fillRect(null, surface.mapRgb(128, 30, 255));
    try app_state.window.updateSurface();

    return .run;
}

pub fn event(
    app_state: *AppState,
    curr_event: *const sdl3.events.Event,
) !sdl3.AppResult {
    _ = app_state;

    return switch (curr_event.*) {
        .quit => .success,
        .terminating => .success,
        else => .run,
    };
}

pub fn quit(
    app_state: *AppState,
    result: sdl3.AppResult,
) !void {
    _ = result;
    allocator.destroy(app_state);
    app_state.window.deinit();
}
