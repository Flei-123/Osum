#version 450
layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec4 a_col;
layout(std140, set = 0, binding = 0) uniform U {
    vec4 clipr;
    vec4 box;
    vec4 c1;
    vec4 grad;
    vec2 size;
} u;
layout(location = 0) out vec2 v_uv;
layout(location = 1) out vec4 v_col;
void main() {
    gl_Position = vec4(a_pos.x / u.size.x * 2.0 - 1.0, 1.0 - a_pos.y / u.size.y * 2.0, 0.0, 1.0);
    v_uv = a_pos;
    v_col = a_col;
}
