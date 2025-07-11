const std = @import("std");
const DynLib = std.DynLib;
const allocator = std.heap.smp_allocator;

const sdl3 = @import("sdl3");

const AppState = @import("state.zig").AppState;

const SCREEN_WIDTH = 640;
const SCREEN_HEIGHT = 480;

var last_mod_time: i128 = 0;
var game_dyn_lib: ?DynLib = null;

var game_init: ?*const fn (app_state: *?*AppState) callconv(.C) sdl3.AppResult = null;
var game_iterate: ?*const fn (app_state: *AppState) callconv(.C) sdl3.AppResult = null;
var game_event: ?*const fn (app_state: *AppState, curr_event: *const sdl3.events.Event) callconv(.C) sdl3.AppResult = null;
var game_quit: ?*const fn (app_state: *AppState, result: sdl3.AppResult) callconv(.C) void = null;

pub fn main() u8 {
    sdl3.main_funcs.setMainReady();
    var args = [_:null]?[*:0]u8{
        @constCast("Hello SDL3"),
    };

    loadGameLibrary() catch |err| {
        std.debug.print("Failed to load game.so: {}\n", .{err});
    };

    return sdl3.main_funcs.enterAppMainCallbacks(&args, AppState, init, iterate, event, quit);
}

fn maybeHotReload() !void {
    const file = try std.fs.cwd().openFile("zig-out/lib/libpppp.so", .{});
    const stat = try file.stat();
    const new_time = stat.mtime;

    file.close();

    if (new_time == last_mod_time) return;

    std.debug.print("Detected change, reloading\n", .{});
    last_mod_time = new_time;

    if (game_dyn_lib) |*lib| {
        lib.close();
        game_dyn_lib = null;
        game_init = null;
        game_iterate = null;
        game_event = null;
        game_quit = null;
    }

    loadGameLibrary() catch |err| {
        std.debug.print("Reload failed: {}\n", .{err});
    };
}

fn loadGameLibrary() !void {
    if (game_dyn_lib != null) return error.AlreadyLoaded;
    var dyn_lib = std.DynLib.open("zig-out/lib/libpppp.so") catch {
        return error.OpenFail;
    };
    game_dyn_lib = dyn_lib;
    game_init = dyn_lib.lookup(@TypeOf(game_init), "init") orelse return error.LookupFail;
    game_iterate = dyn_lib.lookup(@TypeOf(game_iterate), "iterate") orelse return error.LookupFail;
    game_event = dyn_lib.lookup(@TypeOf(game_event), "event") orelse return error.LookupFail;
    game_quit = dyn_lib.lookup(@TypeOf(game_quit), "quit") orelse return error.LookupFail;
    std.debug.print("Loaded game with hot reload\n", .{});
}

fn init(
    app_state: *?*AppState,
    args: [][*:0]u8,
) !sdl3.AppResult {
    _ = args;

    return (game_init orelse return .failure)(app_state);
}

fn iterate(
    app_state: ?*AppState,
) !sdl3.AppResult {
    maybeHotReload() catch |err| {
        std.debug.print("Hot reload failed: {}\n", .{err});
    };

    const state = app_state orelse {
        std.debug.print("iterate: app_state is null\n", .{});
        return .failure;
    };

    return (game_iterate orelse return .failure)(state);
}

fn event(
    app_state: ?*AppState,
    curr_event: sdl3.events.Event,
) !sdl3.AppResult {
    const state = app_state orelse {
        std.debug.print("iterate: app_state is null\n", .{});
        return .failure;
    };
    return (game_event orelse return .failure)(state, &curr_event);
}

fn quit(
    app_state: ?*AppState,
    result: sdl3.AppResult,
) void {
    if (app_state) |state| {
        (game_quit orelse return)(state, result);
    }

    if (game_dyn_lib) |*lib| {
        lib.close();
        game_dyn_lib = null;
    }
}
