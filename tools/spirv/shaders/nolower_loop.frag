#version 450
layout(location=0) in vec2 uv;
layout(location=0) out vec4 o;
void main() { float s = 0.0; for (int i = 0; i < 4; i++) s += uv.x * float(i); o = vec4(s); }
