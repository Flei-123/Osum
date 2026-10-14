#version 450
layout(location=0) in vec2 uv;
layout(location=1) in vec4 col;
layout(location=0) out vec4 o;
void main() {
    vec4 c = col;
    if (uv.x > 0.5) { c.r = 1.0 - c.r; if (uv.y > 0.5) c.g = 0.0; } else { c.b = c.b * 0.5; }
    float k = (uv.y < 0.3) ? 0.2 : 0.9;
    bool b = uv.x > 0.2 && uv.y < 0.8;
    if (b) c.a = k;
    o = c;
}
