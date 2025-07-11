struct VertexInput {
  float3 position : ATTR0;
  float2 texcoord : ATTR1;
};
struct VertexOutput {
  float2 texcoord : TEXCOORD0;
  float4 position : SV_Position;
};

[shader("vertex")]
VertexOutput vertexmain(VertexInput input) {
  VertexOutput output;
  output.texcoord = input.texcoord;
  output.position = float4(input.position, 1.0f);

  return output;
}

struct PSOutput {
  [vk_location(0)]
  float4 frag_color : SV_Target;
};

[[vk::binding(0, 2)]]
Sampler2D Sampler;

[shader("fragment")]
PSOutput fragmentmain(VertexOutput input) {
  PSOutput output;
  output.frag_color = Sampler.Sample(input.texcoord);

  return output;
}
