struct Input {
  float4 position : SV_Position;
  float3 nearPoint : TEXCOORD0;
  float3 farPoint : TEXCOORD1;
};

struct Output {
  float4 FragColor : SV_Target0;
  float Depth : SV_Depth;
};

cbuffer Local : register(b0, space3) {
  float4x4 viewProjectionMat;
  float4x4 invViewMat;
  float4x4 invProjectionMat;
};

inline float3 UnprojectPoint(float3 ndcPoint) {
  float4 unprojectPoint =
      mul(invViewMat, mul(invProjectionMat, float4(ndcPoint, 1)));
  return unprojectPoint.xyz / unprojectPoint.w;
}

float4 Grid(float3 fragPos3D, float scale) {
  float2 coord = fragPos3D.xz * scale;
  float2 derivative = fwidth(coord);

  float2 grid = abs(frac(coord - 0.5) - 0.5) / derivative;

  float minimumz = min(derivative.y, 1);
  float minimumx = min(derivative.x, 1);

  if (min(grid.x, grid.y) < 1) {
    discard;
  }
  return float4(0.1, 0, 0.1, 1);
}

float ComputeDepth(float3 pos) {
  float4 clip_space_pos = mul(viewProjectionMat, float4(pos, 1));
  return clip_space_pos.z / clip_space_pos.w;
}

Output main(Input input) {
  Output output;

  float3 direction = input.farPoint - input.nearPoint;
  float t = -input.nearPoint.y / direction.y;
  float3 position = input.nearPoint + t * direction;

  if (t < 0) {
    discard;
  }

  output.FragColor = Grid(position, 1);
  output.Depth = ComputeDepth(position);

  return output;
}

