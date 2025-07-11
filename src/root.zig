const std = @import("std");
const sdl3 = @import("sdl3");

const AppState = @import("state.zig").AppState;
const game = @import("game.zig");

export fn init(
    app_state: *?*AppState,
) sdl3.AppResult {
    return game.init(app_state) catch return .failure;
}

export fn iterate(app_state: *AppState) sdl3.AppResult {
    return game.iterate(app_state) catch return .failure;
}

export fn event(
    app_state: *AppState,
    curr_event: *const sdl3.events.Event,
) sdl3.AppResult {
    return game.event(app_state, curr_event) catch return .failure;
}

export fn quit(
    app_state: *AppState,
    result: sdl3.AppResult,
) void {
    return game.quit(app_state, result) catch return .failure;
}
