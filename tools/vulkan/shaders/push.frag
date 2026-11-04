#version 450
layout(location = 1) in vec4 vcol;
layout(push_constant) uniform P { vec4 tint; } p;
layout(location = 0) out vec4 o;
void main() {
    o = vcol * p.tint;
}
