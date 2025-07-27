const std = @import("std");
const sdl3 = @import("sdl3");
const assets = @import("assets");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

const ATLAS_WIDTH = 1024;
const ATLAS_HEIGHT = 1024;
const ATLAS_CHANNELS = 4;
const PREALLOC_SPRITES = 32;
const INPUT_PATH = "assets/sprites";
const OUTPUT_ATLAS_PATH = "assets/atlas.png";
const OUTPUT_INFO_PATH = "assets/sprites.json";

const IMAGE_FORMAT = sdl3.pixels.Format.packed_abgr_8_8_8_8;

pub const SpriteInfo = struct {
    uv: [2]f32,
    tex: [2]f32,
};

const SpriteData = struct {
    name: []const u8,
    data: []u8,
    width: usize,
    height: usize,
};

fn compareSpriteSize(context: void, a: SpriteData, b: SpriteData) bool {
    _ = context;

    return a.height > b.height or (a.height == b.height and a.width > b.width);
}

fn copySpriteToAtlas(sprite: SpriteData, x: usize, y: usize, atlas: []u8) void {
    for (0..sprite.height) |sprite_row| {
        const sprite_start_index = sprite_row * sprite.width * ATLAS_CHANNELS;
        const sprite_end_index = sprite_start_index + sprite.width * ATLAS_CHANNELS;

        const atlas_row = y + sprite_row;
        const atlas_start_index = (atlas_row * ATLAS_WIDTH + x) * ATLAS_CHANNELS;
        const atlas_end_index = atlas_start_index + sprite.width * ATLAS_CHANNELS;

        @memcpy(atlas[atlas_start_index..atlas_end_index], sprite.data[sprite_start_index..sprite_end_index]);
    }
}

pub fn main() !void {
    const allocator = arena.allocator();
    defer arena.deinit();

    var sprite_data = try std.ArrayList(SpriteData).initCapacity(allocator, PREALLOC_SPRITES);

    var dir = try std.fs.cwd().openDir(INPUT_PATH, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        if (!std.mem.endsWith(u8, entry.basename, ".png")) continue;

        const sprite_name = entry.basename[0 .. entry.basename.len - 4];
        const full_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ INPUT_PATH, entry.path });

        const image_stream = try sdl3.io_stream.Stream.initFromFile(full_path, .read_binary);
        const image_surface = try sdl3.image.loadIo(image_stream, true);
        const image_formatted_surface = try image_surface.convertFormat(IMAGE_FORMAT);
        defer image_surface.deinit();

        try sprite_data.append(.{
            .name = sprite_name,
            .data = image_formatted_surface.getPixels() orelse continue,
            .width = image_surface.getWidth(),
            .height = image_surface.getHeight(),
        });
    }

    var sprite_info = std.json.ArrayHashMap(SpriteInfo){};
    try sprite_info.map.ensureTotalCapacity(allocator, @intCast(sprite_data.items.len));

    std.mem.sort(SpriteData, sprite_data.items, {}, compareSpriteSize);

    const atlas_data = try allocator.alloc(u8, ATLAS_WIDTH * ATLAS_HEIGHT * ATLAS_CHANNELS);
    @memset(atlas_data, 0);

    var current_x: usize = 0;
    var current_y: usize = 0;
    var row_height: usize = 0;

    for (sprite_data.items) |value| {
        if (value.width > ATLAS_WIDTH or value.height > ATLAS_HEIGHT) {
            std.log.warn("Sprite {s} ({}x{}), bigger than atlas", .{ value.name, value.width, value.height });
        } else if (current_y + value.height > ATLAS_HEIGHT) {
            std.log.warn("Couldn't fit {s} ({}x{}), doesn't fit in atlas", .{ value.name, value.width, value.height });
        } else if (current_x + value.width > ATLAS_WIDTH) {
            current_x = 0;
            current_y += row_height;
            row_height = 0;
        } else {
            copySpriteToAtlas(value, current_x, current_y, atlas_data);
            try sprite_info.map.put(allocator, value.name, .{
                .uv = .{
                    @as(f32, @floatFromInt(current_x)) / @as(f32, @floatFromInt(ATLAS_WIDTH)),
                    @as(f32, @floatFromInt(current_y)) / @as(f32, @floatFromInt(ATLAS_HEIGHT)),
                },
                .tex = .{
                    (@as(f32, @floatFromInt(current_x)) + @as(f32, @floatFromInt(value.width))) / @as(f32, @floatFromInt(ATLAS_WIDTH)),
                    (@as(f32, @floatFromInt(current_y)) + @as(f32, @floatFromInt(value.height))) / @as(f32, @floatFromInt(ATLAS_HEIGHT)),
                },
            });

            current_x += value.width;
            row_height = if (row_height == 0) value.height else row_height;
        }
    }

    const atlas_surface = try sdl3.surface.Surface.initFrom(ATLAS_WIDTH, ATLAS_HEIGHT, IMAGE_FORMAT, atlas_data);
    try sdl3.image.savePng(atlas_surface, OUTPUT_ATLAS_PATH);

    const sprite_info_file = try std.fs.cwd().createFile(OUTPUT_INFO_PATH, .{});
    defer sprite_info_file.close();
    try std.json.stringify(sprite_info, .{}, sprite_info_file.writer());
}
