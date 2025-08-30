#include "common.hlsl"

struct Output {
  float4 position : SV_Position;
  float3 nearPoint : TEXCOORD0;
  float3 farPoint : TEXCOORD1;
};

static const float2 ndcCorners[4] = { float2(-1, -1), float2(1, -1),
                                      float2(-1, 1), float2(1, 1) };

inline float3 UnprojectPoint(float3 ndcPoint) {
  float4 unprojectPoint =
      mul(invViewMat, mul(invProjectionMat, float4(ndcPoint, 1)));
  return unprojectPoint.xyz / unprojectPoint.w;
}

Output main(uint id: SV_VertexID) {
  Output output;

  output.position = float4(ndcCorners[id], 0, 1);
  output.nearPoint = UnprojectPoint(float3(output.position.xy, 1));
  output.farPoint = UnprojectPoint(float3(output.position.xy, 0.00001));

  return output;
}
