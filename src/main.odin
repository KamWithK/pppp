package main

import "base:runtime"
import "core:c"
import "core:log"
import "core:math/linalg"
import sdl "vendor:sdl3"

sdl_log :: proc "c" (
	userdata: rawptr,
	category: sdl.LogCategory,
	priority: sdl.LogPriority,
	message: cstring,
) {
	context = (transmute(^runtime.Context)userdata)^

	level: log.Level
	switch priority {
	case .INVALID, .TRACE, .VERBOSE, .DEBUG:
		level = .Debug
	case .INFO:
		level = .Info
	case .WARN:
		level = .Warning
	case .ERROR:
		level = .Error
	case .CRITICAL:
		level = .Fatal
	}

	log.logf(level, "SDL {} [{}]: {}", category, message)
}

window_init :: proc() {
	ok := sdl.Init({.VIDEO});sdl_assert(ok)

	g.window = sdl.CreateWindow("pppp", 1920, 1080, {});sdl_assert(g.window != nil)

	g.gpu = sdl.CreateGPUDevice(SHADER_FORMATS, true, nil);sdl_assert(g.gpu != nil)

	ok = sdl.ClaimWindowForGPUDevice(g.gpu, g.window);sdl_assert(ok)

	ok = sdl.SetGPUSwapchainParameters(g.gpu, g.window, .SDR_LINEAR, .VSYNC);sdl_assert(ok)

	g.swapchain_texture_format = sdl.GetGPUSwapchainTextureFormat(g.gpu, g.window)

	ok = sdl.GetWindowSize(g.window, &g.window_size.x, &g.window_size.y);sdl_assert(ok)

	g.depth_texture_format = .D16_UNORM
	try_depth_format :: proc(format: sdl.GPUTextureFormat) {
		if sdl.GPUTextureSupportsFormat(g.gpu, format, .D2, {.DEPTH_STENCIL_TARGET}) {
			g.depth_texture_format = format
		}
	}
	try_depth_format(.D32_FLOAT)
	try_depth_format(.D24_UNORM)

	g.depth_texture = sdl.CreateGPUTexture(
		g.gpu,
		{
			format = g.depth_texture_format,
			usage = {.DEPTH_STENCIL_TARGET},
			width = u32(g.window_size.x),
			height = u32(g.window_size.y),
			layer_count_or_depth = 1,
			num_levels = 1,
		},
	)

	g.last_ticks = sdl.GetTicks()

}

app_init: sdl.AppInit_func : proc "c" (
	appstate: ^rawptr,
	argc: c.int,
	argv: [^]cstring,
) -> sdl.AppResult {
	context = g.sdl_context

	window_init()
	game_init()

	return sdl.AppResult.CONTINUE
}


app_iterate: sdl.AppIterate_func : proc "c" (appstate: rawptr) -> sdl.AppResult {
	context = g.sdl_context

	free_all(g.sdl_context.temp_allocator)

	g.new_ticks = sdl.GetTicks()
	delta_time := f32(g.new_ticks - g.last_ticks) / 1000
	g.last_ticks = g.new_ticks

	game_update(delta_time)

	cmd_buf := sdl.AcquireGPUCommandBuffer(g.gpu)

	model_entities := game_instances(cmd_buf)

	swapchain_tex: ^sdl.GPUTexture
	ok := sdl.WaitAndAcquireGPUSwapchainTexture(
		cmd_buf,
		g.window,
		&swapchain_tex,
		nil,
		nil,
	);sdl_assert(ok)

	if swapchain_tex != nil {
		game_render(cmd_buf, swapchain_tex, model_entities)
	}

	ok = sdl.SubmitGPUCommandBuffer(cmd_buf);sdl_assert(ok)

	return sdl.AppResult.CONTINUE
}

app_event: sdl.AppEvent_func : proc "c" (appstate: rawptr, event: ^sdl.Event) -> sdl.AppResult {
	#partial switch event.type {
	case .QUIT:
		return sdl.AppResult.SUCCESS
	case .KEY_DOWN:
		g.key_down[event.key.scancode] = true
	case .KEY_UP:
		g.key_down[event.key.scancode] = false
	case .MOUSE_MOTION:
		g.mouse_motion = {event.motion.xrel, event.motion.yrel}
	case .MOUSE_BUTTON_DOWN:
		g.mouse_down = true
	case .MOUSE_BUTTON_UP:
		g.mouse_down = false
	}

	return sdl.AppResult.CONTINUE
}

app_quit: sdl.AppQuit_func : proc "c" (appstate: rawptr, result: sdl.AppResult) {
}

main :: proc() {
	context.logger = log.create_console_logger()
	context.logger.options -= {.Short_File_Path, .Line, .Procedure}
	defer log.destroy_console_logger(context.logger)

	g.sdl_context = context

	sdl.SetLogPriorities(.VERBOSE)
	sdl.SetLogOutputFunction(sdl_log, &g.sdl_context)

	argc := cast(i32)len(runtime.args__)
	argv := raw_data(runtime.args__)
	sdl.EnterAppMainCallbacks(argc, argv, app_init, app_iterate, app_event, app_quit)
}
