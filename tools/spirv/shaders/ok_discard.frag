#version 450
layout(location=0) in vec2 uv;
layout(location=0) out vec4 o;
void main() { if (uv.x < 0.5) discard; o = vec4(1.0); }
