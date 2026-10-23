#version 450
layout(std140, set = 0, binding = 0) uniform U {
    vec4 clipr;
    vec4 box;
    vec4 c1;
    vec4 grad;
    vec2 size;
} u;
layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec4 v_c0;
layout(location = 0) out vec4 o;

float ovl(float a0, float a1, float b0, float b1) { return max(0.0, min(a1, b1) - max(a0, b0)); }

vec4 blendf(vec4 c, float f) {
    float a = c.a / 255.0 * min(f, 1.0);
    if (a <= 0.0) discard;
    return vec4(c.rgb / 255.0, a);
}

void main() {
    vec2 i = floor(vec2(gl_FragCoord.x, gl_FragCoord.y));
    float clipf = ovl(i.x, i.x + 1.0, u.clipr.x, u.clipr.z) * ovl(i.y, i.y + 1.0, u.clipr.y, u.clipr.w);
    if (clipf <= 0.0) discard;
    float f = ovl(i.x, i.x + 1.0, u.box.x, u.box.z) * ovl(i.y, i.y + 1.0, u.box.y, u.box.w);
    if (f <= 0.0) discard;
    vec4 c = v_c0;
    if (u.grad.z > 0.5) {
        float tt = clamp((i.y - u.grad.x) / max(u.grad.y - u.grad.x, 0.0001), 0.0, 1.0);
        c = vec4(floor(v_c0.rgb + (u.c1.rgb - v_c0.rgb) * tt + 0.5), 255.0);
    }
    o = blendf(c, f * clipf);
}
