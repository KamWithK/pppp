package main

import "base:runtime"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/hlsl"
import sdl "vendor:sdl3"

CONTENT_DIR :: "content"

Vec4 :: [4]f32
Vec3 :: [3]f32
Vec2 :: [2]f32
Mat3 :: matrix[3, 3]f32
Mat4 :: matrix[4, 4]f32
Quat :: quaternion128

ndcCorners: [4]Vec2 : {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}}
WHITE :: sdl.FColor{1, 1, 1, 1}

sdl_assert :: proc(ok: bool) {
	if !ok do log.panicf("SDL Error: {}", sdl.GetError())
}

unproject :: proc(point: Vec3, inv_view: Mat4, inv_projection: Mat4) -> Vec3 {
	unproject_point := inv_view * inv_projection * Vec4{point.x, point.y, point.z, 1}
	return unproject_point.xyz / unproject_point.w
}

intersect_plane :: proc(
	ray_origin: Vec3,
	ray_direction: Vec3,
	plane_position: Vec3,
	plane_normal: Vec3,
) -> Vec3 {
	t :=
		hlsl.dot(plane_position - ray_origin, plane_normal) *
		hlsl.rcp(hlsl.dot(plane_normal, ray_direction))
	return t * ray_direction + ray_origin
}

reverse_perspective := proc(fovy, aspect, near: f32) -> (m: Mat4) {
	tan_half_fovy := math.tan(0.5 * fovy)
	m[0, 0] = 1 / (aspect * tan_half_fovy)
	m[1, 1] = 1 / (tan_half_fovy)
	m[3, 2] = +1

	m[2, 3] = near

	m[2] = -m[2]

	return
}

Globals :: struct {
	sdl_context:              runtime.Context,
	gpu:                      ^sdl.GPUDevice,
	window:                   ^sdl.Window,
	window_size:              [2]i32,
	depth_texture:            ^sdl.GPUTexture,
	depth_texture_format:     sdl.GPUTextureFormat,
	swapchain_texture_format: sdl.GPUTextureFormat,
	new_ticks:                u64,
	last_ticks:               u64,
	key_down:                 #sparse[sdl.Scancode]bool,
	mouse_motion:             Vec2,
	mouse_down:               bool,
	using game:               Game_State,
}

g: Globals
