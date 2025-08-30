package main

import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/hlsl"
import "core:mem"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import sdl "vendor:sdl3"

EYE_HEIGHT :: 15
MOVE_SPEED :: 5
LOOK_SENSITIVITY :: 0.3
FOVY :: 70 * linalg.RAD_PER_DEG
PITCH_ANGLE :: -50 * linalg.RAD_PER_DEG
ROTATION_SPEED :: f32(90) * linalg.RAD_PER_DEG
INDICES_SIZE :: size_of(Mat4) * 1000
GRID_VERTICES_X :: u32(2)
GRID_VERTICES_Z :: u32(2)

create_model :: proc(mesh: Mesh, material: Material) -> Model {
	return {
		mesh,
		material,
		sdl.CreateGPUBuffer(g.gpu, {usage = {.GRAPHICS_STORAGE_READ}, size = INDICES_SIZE}),
		sdl.CreateGPUTransferBuffer(g.gpu, {usage = .UPLOAD, size = INDICES_SIZE}),
	}
}

game_init :: proc() {
	setup_pipeline()
	setup_light_shape_pipeline()
	setup_skybox_pipeline()
	setup_grid_pipeline()

	g.default_sampler = sdl.CreateGPUSampler(g.gpu, {min_filter = .LINEAR, mag_filter = .LINEAR})

	cmd_buf := sdl.AcquireGPUCommandBuffer(g.gpu)
	copy_pass := sdl.BeginGPUCopyPass(cmd_buf)

	g.light_shape_mesh = generate_box_mesh(copy_pass, 1, 1, 1)

	{
		num_vertices := GRID_VERTICES_X * GRID_VERTICES_Z
		num_indices := (GRID_VERTICES_X - 1) * (GRID_VERTICES_Z - 1) * 3 * 2
		vertex_buf := sdl.CreateGPUBuffer(
			g.gpu,
			{
				usage = {.VERTEX, .COMPUTE_STORAGE_WRITE},
				size = size_of(Vertex_Data) * num_vertices,
			},
		)
		index_buf := sdl.CreateGPUBuffer(
			g.gpu,
			{usage = {.INDEX, .COMPUTE_STORAGE_WRITE}, size = u32(size_of(u32) * num_indices)},
		)
		g.grid_mesh = {vertex_buf, index_buf, num_indices}
	}

	colormap := load_texture_file(copy_pass, "colormap.png")
	cobblestone := load_texture_file(copy_pass, "cobblestone_1.png")
	prototype_texture := load_texture_file(copy_pass, "texture_01.png")

	g.skybox_tex = load_cubemap_texture_files(
		copy_pass,
		{
			.POSITIVEX = "skybox/right.png",
			.NEGATIVEX = "skybox/left.png",
			.POSITIVEY = "skybox/top.png",
			.NEGATIVEY = "skybox/bottom.png",
			.POSITIVEZ = "skybox/front.png",
			.NEGATIVEZ = "skybox/back.png",
		},
	)
	g.skybox_tex_single = load_cubemap_texture_single(copy_pass, "skybox/cubemap.png")

	g.models = slice.clone(
		[]Model {
			create_model(
				load_obj_file(copy_pass, "tractor-police.obj"),
				{diffuse_texture = colormap, specular_color = 0, specular_shininess = 1},
			),
			create_model(
				load_obj_file(copy_pass, "sedan-sports.obj"),
				{diffuse_texture = colormap, specular_color = 1, specular_shininess = 160},
			),
			create_model(
				load_obj_file(copy_pass, "ambulance.obj"),
				{diffuse_texture = colormap, specular_color = {1, 0, 0}, specular_shininess = 80},
			),
			create_model(
				generate_plane_mesh(copy_pass, 10, 10),
				{diffuse_texture = cobblestone, specular_color = 0, specular_shininess = 1},
			),
			create_model(
				generate_box_mesh(copy_pass, 1, 1, 1),
				{
					diffuse_texture = prototype_texture,
					specular_color = 1,
					specular_shininess = 100,
				},
			),
			create_model(
				load_gltf_file(copy_pass, "monkey.glb"),
				{diffuse_texture = colormap, specular_color = 0, specular_shininess = 1},
			),
		},
	)

	sdl.EndGPUCopyPass(copy_pass)

	g.entities = slice.clone(
		[]Entity {
			{model_id = 0, position = {-7.14, 0, -2.97}, rotation = 1},
			{model_id = 5, position = {0, 2, 0}, rotation = 1},
			{
				model_id = 2,
				position = {-3, 0, 0},
				rotation = linalg.quaternion_from_euler_angle_y_f32(-15 * linalg.RAD_PER_DEG),
			},
			{
				model_id = 1,
				position = {3, 0, 0},
				rotation = linalg.quaternion_from_euler_angle_y_f32(15 * linalg.RAD_PER_DEG),
			},
			{model_id = 3, position = {0, 0, 0}},
			{model_id = 2, position = {10, 0, 0}},
			{model_id = 1, position = {11, 0, 0}},
		},
	)

	g.camera = {
		position = {0, EYE_HEIGHT, 5},
		target   = {0, EYE_HEIGHT, 0},
	}
	g.look = {
		pitch = PITCH_ANGLE,
	}

	g.light_position = {3, 3, 3}
	g.light_color = {1, 1, 1}
	g.light_intensity = 1
	g.ambient_light_color = 0.1

	ok := sdl.SubmitGPUCommandBuffer(cmd_buf);sdl_assert(ok)
}

game_update :: proc(delta_time: f32) {
	g.entities[0].rotation *= linalg.quaternion_from_euler_angle_y_f32(ROTATION_SPEED * delta_time)
	update_camera(delta_time)
}

game_instances :: proc(cmd_buf: ^sdl.GPUCommandBuffer) -> Model_Entities {
	model_entities: Model_Entities

	for &entity in g.entities {
		if (model_entities[entity.model_id] == nil) {
			model_entities[entity.model_id] = make([dynamic]Entity)
		}

		append(&model_entities[entity.model_id], entity)
	}

	copy_pass := sdl.BeginGPUCopyPass(cmd_buf)

	for model_id, &entities in model_entities {
		ssbo := make([]UBO_Vert_Local, len(entities))

		for entity, index in entities {
			model_mat := linalg.matrix4_from_trs_f32(entity.position, entity.rotation, 1)
			normal_mat := linalg.inverse_transpose(model_mat)

			ssbo[index] = UBO_Vert_Local {
				model_mat  = model_mat,
				normal_mat = normal_mat,
			}
		}

		transfer_buf := g.models[model_id].instance_transfer_buffer
		instance_buf := g.models[model_id].instance_buffer

		ssbo_bytes := slice.to_bytes(ssbo)
		transfer_mem := transmute([^]byte)sdl.MapGPUTransferBuffer(g.gpu, transfer_buf, true)
		mem.copy(transfer_mem, raw_data(ssbo_bytes), len(ssbo_bytes))
		sdl.UnmapGPUTransferBuffer(g.gpu, transfer_buf)

		sdl.UploadToGPUBuffer(
			copy_pass,
			{transfer_buffer = transfer_buf},
			{buffer = instance_buf, size = u32(len(ssbo_bytes))},
			true,
		)
	}

	sdl.EndGPUCopyPass(copy_pass)

	return model_entities
}

game_render :: proc(
	cmd_buf: ^sdl.GPUCommandBuffer,
	swapchain_tex: ^sdl.GPUTexture,
	model_entities: Model_Entities,
) {
	proj_mat := reverse_perspective(FOVY, f32(g.window_size.x) / f32(g.window_size.y), 0.1)
	view_mat := linalg.matrix4_look_at_f32(g.camera.position, g.camera.target, {0, 1, 0})
	inv_proj := linalg.inverse(proj_mat)
	inv_view := linalg.inverse(view_mat)

	ubo_vert_global := UBO_Vert_Global {
		view_projection_mat = proj_mat * view_mat,
		inv_view_mat        = inv_view,
		inv_projection_mat  = inv_proj,
	}
	sdl.PushGPUVertexUniformData(cmd_buf, 0, &ubo_vert_global, size_of(ubo_vert_global))

	ubo_frag_global := UBO_Frag_Global {
		light_intensity     = g.light_intensity,
		light_position      = g.light_position,
		light_color         = g.light_color,
		view_position       = g.camera.position,
		ambient_light_color = g.ambient_light_color,
	}
	sdl.PushGPUFragmentUniformData(cmd_buf, 0, &ubo_frag_global, size_of(ubo_frag_global))

	clear_color: sdl.FColor = 1
	clear_color.rgb = g.ambient_light_color
	color_target := sdl.GPUColorTargetInfo {
		texture     = swapchain_tex,
		load_op     = .CLEAR,
		clear_color = clear_color,
		store_op    = .STORE,
	}
	depth_target_info := sdl.GPUDepthStencilTargetInfo {
		texture     = g.depth_texture,
		load_op     = .CLEAR,
		clear_depth = 0,
		store_op    = .DONT_CARE,
	}
	render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, &depth_target_info)

	{
		skybox_tex := g.skybox_use_multi_image ? g.skybox_tex : g.skybox_tex_single
		sdl.BindGPUGraphicsPipeline(render_pass, g.skybox_pipeline)
		sdl.BindGPUFragmentSamplers(
			render_pass,
			0,
			&(sdl.GPUTextureSamplerBinding{texture = skybox_tex, sampler = g.default_sampler}),
			1,
		)
		sdl.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)
	}

	{
		sdl.BindGPUGraphicsPipeline(render_pass, g.grid_pipeline)
		sdl.PushGPUFragmentUniformData(cmd_buf, 0, &ubo_vert_global, size_of(ubo_vert_global))
		sdl.DrawGPUPrimitives(render_pass, 4, 1, 0, 0)
	}
	sdl.PushGPUFragmentUniformData(cmd_buf, 0, &ubo_frag_global, size_of(ubo_frag_global))

	{
		sdl.BindGPUGraphicsPipeline(render_pass, g.light_shape_pipeline)

		model_mat := linalg.matrix4_translate_f32(g.light_position)
		sdl.PushGPUVertexUniformData(cmd_buf, 1, &model_mat, size_of(model_mat))

		sdl.BindGPUVertexBuffers(
			render_pass,
			0,
			&(sdl.GPUBufferBinding{buffer = g.light_shape_mesh.vertex_buf}),
			1,
		)
		sdl.BindGPUIndexBuffer(render_pass, {buffer = g.light_shape_mesh.index_buf}, ._16BIT)
		sdl.DrawGPUIndexedPrimitives(render_pass, g.light_shape_mesh.num_indices, 1, 0, 0, 0)
	}

	sdl.BindGPUGraphicsPipeline(render_pass, g.entity_pipeline)

	for model_id in model_entities {
		model := g.models[model_id]
		material := model.material

		ubo_frag_local := UBO_Frag_Local {
			material_specular_color     = material.specular_color,
			material_specular_shininess = material.specular_shininess,
		}
		sdl.PushGPUFragmentUniformData(cmd_buf, 1, &ubo_frag_local, size_of(ubo_frag_local))

		sdl.BindGPUVertexBuffers(
			render_pass,
			0,
			&(sdl.GPUBufferBinding{buffer = model.mesh.vertex_buf}),
			1,
		)
		sdl.BindGPUIndexBuffer(render_pass, {buffer = model.mesh.index_buf}, ._16BIT)
		storage_buffers: []^sdl.GPUBuffer = {model.instance_buffer}
		sdl.BindGPUVertexStorageBuffers(render_pass, 0, raw_data(storage_buffers), 1)
		sdl.BindGPUFragmentSamplers(
			render_pass,
			0,
			&(sdl.GPUTextureSamplerBinding {
					texture = material.diffuse_texture,
					sampler = g.default_sampler,
				}),
			1,
		)

		sdl.DrawGPUIndexedPrimitives(
			render_pass,
			model.mesh.num_indices,
			u32(len(model_entities[model_id])),
			0,
			0,
			0,
		)
	}

	sdl.EndGPURenderPass(render_pass)
}

setup_pipeline :: proc() {
	vert_shader := load_shader(g.gpu, "shader.vert")
	frag_shader := load_shader(g.gpu, "shader.frag")

	vertex_attrs := []sdl.GPUVertexAttribute {
		{location = 0, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, pos))},
		{location = 1, format = .FLOAT4, offset = u32(offset_of(Vertex_Data, color))},
		{location = 2, format = .FLOAT2, offset = u32(offset_of(Vertex_Data, uv))},
		{location = 3, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, normal))},
	}

	g.entity_pipeline = sdl.CreateGPUGraphicsPipeline(
		g.gpu,
		{
			vertex_shader = vert_shader,
			fragment_shader = frag_shader,
			primitive_type = .TRIANGLELIST,
			vertex_input_state = {
				num_vertex_buffers = 1,
				vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription {
						slot = 0,
						pitch = size_of(Vertex_Data),
					}),
				num_vertex_attributes = u32(len(vertex_attrs)),
				vertex_attributes = raw_data(vertex_attrs),
			},
			depth_stencil_state = {
				enable_depth_test = true,
				enable_depth_write = true,
				compare_op = .GREATER,
			},
			rasterizer_state = {cull_mode = .BACK},
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = &(sdl.GPUColorTargetDescription {
						format = g.swapchain_texture_format,
					}),
				has_depth_stencil_target = true,
				depth_stencil_format = g.depth_texture_format,
			},
		},
	)

	sdl.ReleaseGPUShader(g.gpu, vert_shader)
	sdl.ReleaseGPUShader(g.gpu, frag_shader)
}

setup_skybox_pipeline :: proc() {
	vert_shader := load_shader(g.gpu, "skybox.vert")
	frag_shader := load_shader(g.gpu, "skybox.frag")

	g.skybox_pipeline = sdl.CreateGPUGraphicsPipeline(
		g.gpu,
		{
			vertex_shader = vert_shader,
			fragment_shader = frag_shader,
			primitive_type = .TRIANGLELIST,
			depth_stencil_state = {enable_depth_test = true, compare_op = .GREATER},
			rasterizer_state = {cull_mode = .BACK},
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = &(sdl.GPUColorTargetDescription {
						format = g.swapchain_texture_format,
					}),
				has_depth_stencil_target = true,
				depth_stencil_format = g.depth_texture_format,
			},
		},
	)

	sdl.ReleaseGPUShader(g.gpu, vert_shader)
	sdl.ReleaseGPUShader(g.gpu, frag_shader)
}

setup_light_shape_pipeline :: proc() {
	vert_shader := load_shader(g.gpu, "lightshape.vert")
	frag_shader := load_shader(g.gpu, "lightshape.frag")

	vertex_attrs := []sdl.GPUVertexAttribute {
		{location = 0, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, pos))},
	}

	g.light_shape_pipeline = sdl.CreateGPUGraphicsPipeline(
		g.gpu,
		{
			vertex_shader = vert_shader,
			fragment_shader = frag_shader,
			primitive_type = .TRIANGLELIST,
			vertex_input_state = {
				num_vertex_buffers = 1,
				vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription {
						slot = 0,
						pitch = size_of(Vertex_Data),
					}),
				num_vertex_attributes = u32(len(vertex_attrs)),
				vertex_attributes = raw_data(vertex_attrs),
			},
			depth_stencil_state = {
				enable_depth_test = true,
				enable_depth_write = true,
				compare_op = .GREATER,
			},
			rasterizer_state = {cull_mode = .BACK},
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = &(sdl.GPUColorTargetDescription {
						format = g.swapchain_texture_format,
					}),
				has_depth_stencil_target = true,
				depth_stencil_format = g.depth_texture_format,
			},
		},
	)

	sdl.ReleaseGPUShader(g.gpu, vert_shader)
	sdl.ReleaseGPUShader(g.gpu, frag_shader)
}

setup_grid_pipeline :: proc() {
	vert_shader := load_shader(g.gpu, "grid.vert")
	frag_shader := load_shader(g.gpu, "grid.frag")

	g.grid_pipeline = sdl.CreateGPUGraphicsPipeline(
		g.gpu,
		{
			vertex_shader = vert_shader,
			fragment_shader = frag_shader,
			primitive_type = .TRIANGLESTRIP,
			depth_stencil_state = {
				enable_depth_test = true,
				enable_depth_write = true,
				compare_op = .GREATER,
			},
			rasterizer_state = {fill_mode = .FILL},
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = &(sdl.GPUColorTargetDescription {
						format = g.swapchain_texture_format,
						blend_state = {
							enable_blend = true,
							enable_color_write_mask = true,
							color_write_mask = {.R, .G, .B, .A},
							src_color_blendfactor = .SRC_ALPHA,
							dst_color_blendfactor = .ZERO,
							color_blend_op = .ADD,
							src_alpha_blendfactor = .ONE,
							dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
							alpha_blend_op = .ADD,
						},
					}),
				has_depth_stencil_target = true,
				depth_stencil_format = g.depth_texture_format,
			},
		},
	)
	g.grid_generation_pipeline = load_comp_pipeline(g.gpu, "grid.comp")

	sdl.ReleaseGPUShader(g.gpu, vert_shader)
	sdl.ReleaseGPUShader(g.gpu, frag_shader)
}


update_camera :: proc(dt: f32) {
	move_input: Vec2
	zoom_input: f32

	if g.key_down[.W] || g.key_down[.UP] do move_input.y = -1
	else if g.key_down[.S] || g.key_down[.DOWN] do move_input.y = 1
	if g.key_down[.A] || g.key_down[.LEFT] do move_input.x = 1
	else if g.key_down[.D] || g.key_down[.RIGHT] do move_input.x = -1

	if g.key_down[.E] do zoom_input = -1
	else if g.key_down[.R] do zoom_input = 1

	look_input := g.mouse_motion * LOOK_SENSITIVITY * f32(u8(g.mouse_down))
	g.look.yaw = math.wrap(g.look.yaw - look_input.x, 360)
	g.look.pitch = math.clamp(g.look.pitch - look_input.y, -89, 89)

	look_mat := linalg.matrix3_from_yaw_pitch_roll_f32(
		linalg.to_radians(g.look.yaw),
		linalg.to_radians(g.look.pitch),
		0,
	)
	raw_move := look_mat * Vec3{-move_input.x, 0, move_input.y}

	forward := look_mat * Vec3{0, 0, -1}
	move_dir := linalg.normalize0(Vec3{raw_move.x, 0, raw_move.z})
	zoom_dir := linalg.normalize0(forward * zoom_input)

	motion := (move_dir + zoom_dir) * MOVE_SPEED * dt

	g.camera.position += motion
	g.camera.target = g.camera.position + forward
}
