package main

import sdl "vendor:sdl3"

UBO_Vert_Global :: struct #packed {
	view_projection_mat: Mat4,
	inv_view_mat:        Mat4,
	inv_projection_mat:  Mat4,
}

UBO_Vert_Local :: struct #packed {
	model_mat:  Mat4,
	normal_mat: Mat4,
}

UBO_Grid_Local :: struct #packed {
	min_x:      f32,
	max_x:      f32,
	min_z:      f32,
	max_z:      f32,
	vertices_x: u32,
	vertices_z: u32,
}

UBO_Frag_Global :: struct #packed {
	light_position:      Vec3,
	_:                   f32,
	light_color:         Vec3,
	light_intensity:     f32,
	view_position:       Vec3,
	_:                   f32,
	ambient_light_color: Vec3,
}

UBO_Frag_Local :: struct #packed {
	material_specular_color:     Vec3,
	material_specular_shininess: f32,
}

UBO_Camera_Local :: struct #packed {
	position: Vec3,
}

UBO_Wave_Local :: struct #packed {
	time: f32,
}

Vertex_Data :: struct #align (32) {
	pos:    Vec3,
	color:  sdl.FColor,
	uv:     Vec2,
	normal: Vec3,
}

Mesh :: struct {
	vertex_buf:  ^sdl.GPUBuffer,
	index_buf:   ^sdl.GPUBuffer,
	num_indices: u32,
}

Model :: struct {
	mesh:                     Mesh,
	material:                 Material,
	instance_buffer:          ^sdl.GPUBuffer,
	instance_transfer_buffer: ^sdl.GPUTransferBuffer,
}

Material :: struct {
	diffuse_texture:    ^sdl.GPUTexture,
	specular_color:     Vec3,
	specular_shininess: f32,
}

Model_Id :: distinct int

Entity :: struct {
	model_id: Model_Id,
	position: Vec3,
	rotation: Quat,
}

Model_Entities :: map[Model_Id][dynamic]Entity

Game_State :: struct {
	entity_pipeline:          ^sdl.GPUGraphicsPipeline,
	light_shape_pipeline:     ^sdl.GPUGraphicsPipeline,
	light_shape_mesh:         Mesh,
	grid_mesh:                Mesh,
	default_sampler:          ^sdl.GPUSampler,
	camera:                   struct {
		position: Vec3,
		target:   Vec3,
	},
	look:                     struct {
		yaw:   f32,
		pitch: f32,
	},
	models:                   []Model,
	entities:                 []Entity,
	light_position:           Vec3,
	light_color:              Vec3,
	light_intensity:          f32,
	ambient_light_color:      Vec3,
	skybox_tex:               ^sdl.GPUTexture,
	skybox_tex_single:        ^sdl.GPUTexture,
	skybox_pipeline:          ^sdl.GPUGraphicsPipeline,
	grid_generation_pipeline: ^sdl.GPUComputePipeline,
	grid_pipeline:            ^sdl.GPUGraphicsPipeline,
	skybox_use_multi_image:   bool,
}
