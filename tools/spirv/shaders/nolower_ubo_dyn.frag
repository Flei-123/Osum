#version 450
layout(set=0, binding=1) uniform U { vec4 tint[4]; } u;
layout(location=0) in vec2 uv;
layout(location=0) out vec4 o;
void main() { o = u.tint[int(uv.x * 3.0)]; }
