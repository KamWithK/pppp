struct VertexOutput {
  float4 Position : SV_Position;
  float3 NearPoint : TEXCOORD0;
  float3 FarPoint : TEXCOORD1;
  float4x4 View;
  float4x4 Projection;
};

[[vk::binding(0, 1)]]
cbuffer CameraData {
  float4x4 view;
  float4x4 projection;
  float4x4 view_inv;
  float4x4 projection_inv;
}

float3 UnprojectPoint(float3 point, float4x4 view_inv,
                      float4x4 projection_inv) {
  float4 unprojectPoint =
      mul(view_inv, mul(projection_inv, float4(point, 1.0)));
  return unprojectPoint.xyz / unprojectPoint.w;
}

static const float2 positions[4] = { float2(-1, -1), float2(1, -1),
                                     float2(-1, 1), float2(1, 1) };

[shader("vertex")]
VertexOutput vertexmain(uint id: SV_VulkanVertexID) {
  float4 pos = float4(positions[id], 0.0, 1.0);

  VertexOutput output;

  output.Position = pos;
  output.NearPoint =
      UnprojectPoint(float3(pos.xy, 0.0), view_inv, projection_inv);
  output.FarPoint =
      UnprojectPoint(float3(pos.xy, 1.0), view_inv, projection_inv);
  output.View = view;
  output.Projection = projection;

  return output;
}

struct FragmentOutput {
  [vk_location(0)]
  float4 FragColor : SV_Target;
  float Depth : SV_Depth;
};

static const int numCells = 10;
static const float thickness = 0.1;
static const float scroll = 0.0;

bool on_grid(float2 pos, float thickness) {
  return pos.y < thickness || pos.y > 1.0 - thickness || pos.x < thickness ||
         pos.x > 1.0 - thickness;
}

float4 grid(float3 fragPos3D, float scale) {
  float2 coord = fragPos3D.xz * scale;

  float2 derivative = fwidth(coord);

  float2 grid = abs(frac(coord - 0.5) - 0.5) / derivative;
  float line = min(grid.x, grid.y);

  float minimumz = min(derivative.y, 1.0);
  float minimumx = min(derivative.x, 1.0);

  float4 color = float4(0.2, 0.2, 0.2, 1.0 - min(line, 1.0));

  // z axis (x = 0 line)
  if (fragPos3D.x > -0.1 * minimumx && fragPos3D.x < 0.1 * minimumx)
    color.z = 1.0;

  // x axis (z = 0 line)
  if (fragPos3D.z > -0.1 * minimumz && fragPos3D.z < 0.1 * minimumz)
    color.x = 1.0;

  return color;
}

float computeDepth(float4x4 view, float4x4 projection, float3 pos) {
  float4 clip_space_pos = mul(projection, mul(view, float4(pos.xyz, 1)));
  return (clip_space_pos.z / clip_space_pos.w);
}

[shader("fragment")]
FragmentOutput fragmentmain(VertexOutput input) {
  FragmentOutput output;

  float t = -input.NearPoint.y / (input.FarPoint.y - input.NearPoint.y);
  float3 fragPos3D = input.NearPoint + t * (input.FarPoint - input.NearPoint);
  output.FragColor = grid(fragPos3D, 10) * float(t > 0);
  output.Depth = computeDepth(input.View, input.Projection, fragPos3D);

  return output;
}

