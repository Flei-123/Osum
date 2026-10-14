#version 450
layout(location=0) in vec2 uv;
layout(location=1) in vec4 col;
layout(location=0) out vec4 o;
void main() {
    vec3 a = vec3(uv, col.r);
    float d = dot(a, col.rgb) + length(a) + distance(a, col.rgb);
    vec3 n = normalize(a + 0.1);
    float s = sin(uv.x * 3.0) * cos(uv.y * 2.0) + pow(col.g, 2.0) + sqrt(abs(uv.x)) + inversesqrt(col.b + 1.0);
    float t = floor(d) + fract(d) + ceil(s) + smoothstep(0.0, 1.0, uv.x) + step(0.5, uv.y) + mix(0.2, 0.8, col.a);
    int k = int(uv.x * 7.0) * 3 - 2;
    o = vec4(clamp(n * 0.5 + 0.5, 0.0, 1.0), clamp(t * 0.01 + float(k) * 0.01, 0.0, 1.0)) + vec4(min(s, 1.0), max(d, 0.0), exp2(uv.x), log2(uv.y + 1.0)) * 0.1;
}
