#version 450
layout(set = 0, binding = 0) uniform U { vec4 tint; } u;
layout(push_constant) uniform P { vec4 k; } p;
layout(location = 1) in vec4 vcol;
layout(location = 0) out vec4 o;
void main() {
    o = vcol * u.tint * p.k;
}
