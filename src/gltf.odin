package main

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:path/filepath"
import "core:strings"
import "vendor:cgltf"

Gltf_Mesh_Data :: struct {
	data:        cgltf.mesh,
	translation: Vec3,
	rotation:    linalg.Quaternionf32,
}

load_gltf_model :: proc(path: string) -> ([]Vertex_Data, []u16) {
	options: cgltf.options
	cpath := strings.clone_to_cstring(path, context.temp_allocator)

	data, parse_result := cgltf.parse_file(options, cpath)
	defer cgltf.free(data)

	if parse_result != .success {
		log.errorf("Error parsing gltf: {} - {}", path, parse_result)
	}

	load_buffers_result := cgltf.load_buffers(options, data, cpath)
	if load_buffers_result != .success {
		log.errorf("Error loading buffers from gltf: {} - {}", path, load_buffers_result)
	}

	assert(len(data.nodes) == 1)
	return extract_gltf_mesh(data.nodes[0])
}

@(private)
extract_gltf_mesh :: proc(node: cgltf.node) -> ([]Vertex_Data, []u16) {
	// TRANSMUTE: node.rotation is [4]f32 and it isn't possible to cast it to quaternion128 (quat32) afaik.
	// Raw_Quaternion128 is struct of 4 f32, which has the same layout with [4]f32, which makes this transmute
	// valid.
	mesh := node.mesh
	translation := node.translation
	rotation :=
		transmute(linalg.Quaternionf32)node.rotation *
		linalg.quaternion_from_euler_angle_y_f32(180 * linalg.RAD_PER_DEG)

	assert(len(mesh.primitives) == 1)

	primitive := mesh.primitives[0]

	attr_position: cgltf.attribute
	attr_normal: cgltf.attribute
	attr_texcoord: cgltf.attribute

	for attribute in primitive.attributes {
		#partial switch attribute.type {
		case .position:
			attr_position = attribute
		case .normal:
			attr_normal = attribute
		case .texcoord:
			attr_texcoord = attribute
		case:
			log.errorf("Unkown gltf attribute: {}", attribute)
		}
	}

	assert(attr_position.data.count == attr_normal.data.count)
	assert(attr_position.data.count == attr_texcoord.data.count)

	if attr_position.data == nil || primitive.indices == nil do return {}, {}
	vertices := make([]Vertex_Data, attr_position.data.count)
	indices := make([]u16, primitive.indices.count)

	mesh_mat := linalg.matrix4_from_quaternion_f32(rotation)
	mesh_mat *= linalg.matrix4_rotate_f32(math.to_radians_f32(180), {0, 1, 0})
	mesh_mat *= linalg.matrix4_translate_f32(translation)

	for i in 0 ..< attr_position.data.count {
		vertex: Vertex_Data
		ok: b32
		ok = cgltf.accessor_read_float(attr_position.data, i, &vertex.pos[0], 3)
		if !ok do log.errorf("Error reading gltf position")
		ok = cgltf.accessor_read_float(attr_normal.data, i, &vertex.normal[0], 3)
		if !ok do log.errorf("Error reading gltf normal")
		ok = cgltf.accessor_read_float(attr_texcoord.data, i, &vertex.uv[0], 2)
		if !ok do log.errorf("Error reading gltf texcoord")

		position := Vec4{vertex.pos.x, vertex.pos.y, vertex.pos.z, 1}
		vertex.pos = (mesh_mat * position).xyz
		vertices[i] = vertex
	}

	for i in 0 ..< primitive.indices.count {
		indices[i] = u16(cgltf.accessor_read_index(primitive.indices, i))
	}

	return vertices, indices
}
