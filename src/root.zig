const std = @import("std");
const sdl3 = @import("sdl3");

const AppContext = @import("state.zig").AppContext;
const game = @import("game.zig");

export fn init(
    app_context: *?*AppContext,
) sdl3.AppResult {
    return game.init(app_context) catch return .failure;
}

export fn iterate(app_context: *AppContext) sdl3.AppResult {
    return game.iterate(app_context) catch return .failure;
}

export fn event(
    app_context: *AppContext,
    curr_event: *const sdl3.events.Event,
) sdl3.AppResult {
    return game.event(app_context, curr_event) catch return .failure;
}

export fn quit(
    app_context: *AppContext,
    result: sdl3.AppResult,
) void {
    return game.quit(app_context, result) catch return .failure;
}
