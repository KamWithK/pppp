struct SpriteData {
  float3 position;
  float rotation;
  float2 scale;
  float2 padding;
  float tex_u, tex_v, tex_w, tex_h;
  float4 Color;
};

struct VertexOutput {
  float2 texcoord : TEXCOORD0;
  float4 color : TEXCOORD1;
  float4 position : SV_Position;
};

[[vk::binding(0, 0)]]
StructuredBuffer<SpriteData> DataBuffer;

[[vk::binding(0, 1)]]
cbuffer UniformBlock { float4x4 ViewProjectionMatrix; };

static const uint triangleIndices[6] = { 0, 1, 2, 3, 2, 1 };
static const float2 vertexPos[4] = {
  { 0.0f, 0.0f }, { 1.0f, 0.0f }, { 0.0f, 1.0f }, { 1.0f, 1.0f }
};

[shader("vertex")]
VertexOutput vertexmain(uint id: SV_VulkanVertexID) {
  uint spriteIndex = id / 6;
  uint vert = triangleIndices[id % 6];
  SpriteData sprite = DataBuffer[spriteIndex];

  float2 texcoord[4] = { { sprite.tex_u, sprite.tex_v },
                         { sprite.tex_u + sprite.tex_w, sprite.tex_v },
                         { sprite.tex_u, sprite.tex_v + sprite.tex_h },
                         { sprite.tex_u + sprite.tex_w,
                           sprite.tex_v + sprite.tex_h } };

  float c = cos(sprite.rotation);
  float s = sin(sprite.rotation);

  float2 coord = vertexPos[vert];
  coord *= sprite.scale;
  float2x2 rotation = { c, s, -s, c };
  coord = mul(coord, rotation);

  float3 coordWithDepth = float3(coord + sprite.position.xy, sprite.position.z);

  VertexOutput output;

  output.position = mul(ViewProjectionMatrix, float4(coordWithDepth, 1.0f));
  output.texcoord = texcoord[vert];
  output.color = sprite.Color;

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
