#version 450
layout(location=0) in vec2 uv;
layout(location=0) out vec4 o;
void main() {
    o = vec4(0.1, 0.2, 0.3, 1.0);
    if (uv.x < 0.5) return;
    o = vec4(uv, 0.7, 1.0);
}
