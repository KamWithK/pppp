cbuffer Local : register(b0, space2) {
  float min_x;
  float max_x;
  float min_z;
  float max_z;
  uint vertices_x;
  uint vertices_z;
};

struct Vertex {
  float3 Position;
  float4 Color;
  float2 Texcoord;
  float3 Normal;
};

RWStructuredBuffer<Vertex> VertexBuffer : register(u0, space1);
RWStructuredBuffer<uint> IndexBuffer : register(u1, space1);

[numthreads(32, 1, 32)]
void main(uint3 GlobalInvocationID: SV_DispatchThreadID) {
  uint currentX = GlobalInvocationID.x;
  uint currentZ = GlobalInvocationID.z;

  if (currentX >= vertices_x || currentZ >= vertices_z) {
    return;
  }

  int vertexOffset = currentZ * vertices_x + currentX;

  float worldXSpan = max_x - min_x;
  float worldZSpan = max_z - min_z;

  float cellWidth = worldXSpan / (float)(vertices_x - 1);
  float cellDepth = worldZSpan / (float)(vertices_z - 1);

  float3 cellPoint =
      float3(min_x + currentX * cellWidth, 0, min_z + currentZ * cellDepth);

  float u = currentX / (float)(vertices_x - 1);
  float v = currentZ / (float)(vertices_z - 1);

  VertexBuffer[vertexOffset].Position = cellPoint;
  VertexBuffer[vertexOffset].Color = float4(0, 0, 1, 1);
  VertexBuffer[vertexOffset].Texcoord = float2(u, v);
  VertexBuffer[vertexOffset].Normal = float3(0, 1, 0);

  if (currentX >= (vertices_x - 1) || currentZ >= (vertices_z - 1)) {
    return;
  }

  int topLeftVertex = vertexOffset;
  int topRightVertex = topLeftVertex + 1;
  int bottomLeftVertex = topLeftVertex + vertices_x;
  int bottomRightVertex = bottomLeftVertex + 1;

  int quadIndex = 6 * (currentZ * (vertices_x - 1) + currentX);

  IndexBuffer[quadIndex] = bottomLeftVertex;
  IndexBuffer[quadIndex + 1] = topLeftVertex;
  IndexBuffer[quadIndex + 2] = bottomRightVertex;
  IndexBuffer[quadIndex + 3] = bottomRightVertex;
  IndexBuffer[quadIndex + 4] = topLeftVertex;
  IndexBuffer[quadIndex + 5] = topRightVertex;
}

