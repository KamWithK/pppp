const std = @import("std");
const sdl3 = @import("sdl3");

const AppContext = @import("state.zig").AppContext;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

const SCREEN_WIDTH = 1920;
const SCREEN_HEIGHT = 1080;

pub fn init(
    app_context: *?*AppContext,
) !sdl3.AppResult {
    const window = try sdl3.video.Window.init("Pixel Perfect Painted Pipeline", SCREEN_WIDTH, SCREEN_HEIGHT, .{});
    const render = try sdl3.render.Renderer.init(window, null);
    const context = try allocator.create(AppContext);
    context.* = .{
        .window = window,
        .render = render,
    };
    app_context.* = context;

    return .run;
}

pub fn iterate(app_context: *AppContext) !sdl3.AppResult {
    const surface = try app_context.window.getSurface();

    try surface.fillRect(null, surface.mapRgb(128, 30, 255));
    try app_context.window.updateSurface();

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
    app_context.window.deinit();
    arena.deinit();
}
