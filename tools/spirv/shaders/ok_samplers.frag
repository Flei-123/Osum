#version 450
layout(binding=0) uniform sampler2D ta;
layout(binding=1) uniform sampler2D tb;
layout(binding=2) uniform sampler2D tc;
layout(location=0) in vec2 uv;
layout(location=0) out vec4 o;
void main() { o = vec4(texture(ta, uv).r, texture(tb, uv).g, texture(tc, uv).b, 1.0); }
