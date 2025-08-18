const std = @import("std");
const sdl3 = @import("sdl3");

const GameContext = @import("state.zig").GameContext;
const AppContext = @import("state.zig").AppContext;
const TextureContext = @import("state.zig").TextureContext;

pub fn create_texture_buffer(allocator: std.mem.Allocator, app_context: AppContext) !TextureContext {
    const device = app_context.device;

    const image_surface = try sdl3.image.loadFile(
        try app_context.pathToZ(allocator, "assets/sprites/conveyor.png"),
    );
    defer image_surface.deinit();

    const texture = try device.createTexture(.{
        .format = .r8g8b8a8_unorm,
        .width = @intCast(image_surface.getWidth()),
        .height = @intCast(image_surface.getHeight()),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .usage = .{ .sampler = true },
        .props = .{ .name = "sprite atlas" },
    });
    // device.releaseTexture(texture);

    const transfer_buffer = try device.createTransferBuffer(.{
        .usage = .upload,
        .size = @intCast(image_surface.getWidth() * image_surface.getHeight() * 4),
    });
    const atlas_pixels = image_surface.getPixels() orelse return error.InvalidData;
    @memcpy(
        try device.mapTransferBuffer(transfer_buffer, false),
        atlas_pixels,
    );
    device.unmapTransferBuffer(transfer_buffer);

    return .{
        .texture = texture,
        .transfer_buffer = transfer_buffer,
        .width = @intCast(image_surface.getWidth()),
        .height = @intCast(image_surface.getHeight()),
    };
}

pub fn upload_texture_release(
    app_context: AppContext,
    texture_context: TextureContext,
    copy_pass: sdl3.gpu.CopyPass,
) !void {
    copy_pass.uploadToTexture(.{
        .transfer_buffer = texture_context.transfer_buffer,
        .offset = 0,
    }, .{
        .texture = texture_context.texture,
        .width = texture_context.width,
        .height = texture_context.height,
        .depth = 1,
    }, false);

    app_context.device.releaseTransferBuffer(texture_context.transfer_buffer);
}

pub fn quit_pipeline(
    game_context: *GameContext,
) !void {
    const app_context = game_context.app_context;
    const texture_context = game_context.texture_context;

    app_context.device.releaseTexture(texture_context.texture);
}
