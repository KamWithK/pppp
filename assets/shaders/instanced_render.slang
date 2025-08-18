struct VertexInput {
  float4 Position;
  float2 TexCoord : TEXCOORD0;
  uint InstanceID : SV_VulkanInstanceID;
};

struct VertexOutput {
  float2 TexCoord : TEXCOORD0;
  float4 Position : SV_Position;
};

[[vk::binding(0, 1)]]
cbuffer CameraData {
  float4x4 view;
  float4x4 projection;
}

[[vk::binding(0, 0)]]
StructuredBuffer<float4x4> modelMatrices;

[shader("vertex")]
VertexOutput vertexmain(VertexInput input) {
  float4x4 model = modelMatrices[input.InstanceID];

  VertexOutput output;
  output.TexCoord = input.TexCoord;
  output.Position = mul(projection, mul(view, mul(model, input.Position)));

  return output;
}

struct FragmentOutput {
  [vk_location(0)]
  float4 FragColor : SV_Target;
};

struct FragmentInput {
  float2 TexCoord : TEXCOORD0;
};

[[vk::binding(0, 2)]]
Sampler2D Sampler;

[shader("fragment")]
float4 fragmentmain(FragmentInput input) {
  return Sampler.Sample(input.TexCoord);
}

