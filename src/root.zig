const std = @import("std");
const sdl3 = @import("sdl3");

const GameContext = @import("state.zig").GameContext;
const game = @import("game.zig");

// Logging from: https://github.com/Gota7/zig-sdl3/blob/master/gpu_examples/src/main.zig.

fn sdlErr(
    err: ?[]const u8,
) void {
    if (err) |val| {
        std.debug.print("******* [Error! {s}] *******\n", .{val});
    } else {
        std.debug.print("******* [Unknown Error!] *******\n", .{});
    }
}

fn sdlLog(
    user_data: ?*void,
    category: ?sdl3.log.Category,
    priority: ?sdl3.log.Priority,
    message: [:0]const u8,
) void {
    _ = user_data;
    const category_str: ?[]const u8 = if (category) |val| switch (val) {
        .application => "Application",
        .errors => "Errors",
        .assert => "Assert",
        .system => "System",
        .audio => "Audio",
        .video => "Video",
        .render => "Render",
        .input => "Input",
        .testing => "Testing",
        .gpu => "Gpu",
        else => null,
    } else null;
    const priority_str: [:0]const u8 = if (priority) |val| switch (val) {
        .trace => "Trace",
        .verbose => "Verbose",
        .debug => "Debug",
        .info => "Info",
        .warn => "Warn",
        .err => "Error",
        .critical => "Critical",
    } else "Unknown";
    if (category_str) |val| {
        std.debug.print("[{s}:{s}] {s}\n", .{ val, priority_str, message });
    } else if (category) |val| {
        std.debug.print("[Custom_{d}:{s}] {s}\n", .{ @intFromEnum(val), priority_str, message });
    } else {
        std.debug.print("Unknown:{s}] {s}\n", .{ priority_str, message });
    }
}

export fn init(
    game_context: *?*GameContext,
) sdl3.AppResult {
    sdl3.errors.error_callback = &sdlErr;
    sdl3.log.setAllPriorities(.info);
    sdl3.log.setLogOutputFunction(void, sdlLog, null);

    return game.init(game_context) catch return .failure;
}

export fn iterate(game_context: *GameContext) sdl3.AppResult {
    return game.iterate(game_context) catch return .failure;
}

export fn event(
    game_context: *GameContext,
    curr_event: *const sdl3.events.Event,
) sdl3.AppResult {
    return game.event(game_context, curr_event) catch return .failure;
}

export fn quit(
    game_context: *GameContext,
    result: sdl3.AppResult,
) void {
    return game.quit(game_context, result) catch return .failure;
}
