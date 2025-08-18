const std = @import("std");
const sdl3 = @import("sdl3");
const zm = @import("zmath");

const GameContext = @import("state.zig").GameContext;
const AppContext = @import("state.zig").AppContext;
const GridContext = @import("state.zig").GridContext;
const CameraData = @import("state.zig").CameraData;

const CameraDataWithInverse = struct {
    camera_data: CameraData,
    inverse_camera_data: CameraData,
};

const SCREEN_WIDTH = @import("game.zig").SCREEN_WIDTH;
const SCREEN_HEIGHT = @import("game.zig").SCREEN_HEIGHT;
const SHADER_FORMATS = @import("game.zig").SHADER_FORMATS;

pub fn init_pipeline(allocator: std.mem.Allocator, app_context: AppContext) !GridContext {
    const device = app_context.device;

    const shader_bin = try sdl3.io_stream.loadFile(
        try app_context.pathToZ(allocator, "assets/shaders/grid.spv"),
    );

    const vert_shader = try device.createShader(.{
        .code = shader_bin,
        .format = SHADER_FORMATS,
        .stage = .vertex,
        .entry_point = "vertexmain",
        .num_samplers = 0,
        .num_uniform_buffers = 1,
        .num_storage_buffers = 0,
        .num_storage_textures = 0,
    });
    defer device.releaseShader(vert_shader);

    const frag_shader = try device.createShader(.{
        .code = shader_bin,
        .format = SHADER_FORMATS,
        .stage = .fragment,
        .entry_point = "fragmentmain",
        .num_samplers = 0,
        .num_uniform_buffers = 0,
        .num_storage_buffers = 0,
        .num_storage_textures = 0,
    });
    defer device.releaseShader(frag_shader);

    const pipeline = try device.createGraphicsPipeline(.{
        .target_info = .{
            .color_target_descriptions = &.{
                .{
                    .format = device.getSwapchainTextureFormat(app_context.window),
                    .blend_state = .{
                        .enable_blend = true,
                        .enable_color_write_mask = true,
                        .source_color = .src_alpha,
                        .destination_color = .zero,
                        .color_blend = .add,
                        .source_alpha = .one,
                        .destination_alpha = .one_minus_src_alpha,
                        .alpha_blend = .add,
                        .color_write_mask = .{
                            .red = true,
                            .green = true,
                            .blue = true,
                            .alpha = true,
                        },
                    },
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
            .vertex_attributes = &.{},
        },
        .primitive_type = .triangle_strip,
        .rasterizer_state = .{ .fill_mode = .fill },
        .vertex_shader = vert_shader,
        .fragment_shader = frag_shader,
    });
    errdefer device.releaseGraphicsPipeline(pipeline);

    return .{
        .pipeline = pipeline,
    };
}

pub fn iterate_pipeline(
    grid_context: GridContext,
    camera_data: CameraData,
    command_buffer: sdl3.gpu.CommandBuffer,
    render_pass: sdl3.gpu.RenderPass,
) !void {
    render_pass.bindGraphicsPipeline(grid_context.pipeline);

    const camera_data_with_inverse = CameraDataWithInverse{
        .camera_data = camera_data,
        .inverse_camera_data = .{
            .projection = zm.inverse(camera_data.projection),
            .view = zm.inverse(camera_data.view),
        },
    };

    command_buffer.pushVertexUniformData(0, std.mem.asBytes(&camera_data_with_inverse));

    render_pass.drawPrimitives(
        4,
        1,
        0,
        0,
    );
}

pub fn quit_pipeline(
    game_context: *GameContext,
) !void {
    const app_context = game_context.app_context;
    const grid_context = game_context.grid_context;

    app_context.device.releaseGraphicsPipeline(grid_context.pipeline);
}
