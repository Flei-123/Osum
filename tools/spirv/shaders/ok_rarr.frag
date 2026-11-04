#version 450
layout(location=0) in vec2 uv;
layout(location=0) out vec4 o;
void main() {
    float a[6];
    for (int i = 0; i < 6; i++) a[i] = float(i) * 0.1 + uv.x;
    int k = int(uv.y * 6.0);
    float s = a[k];
    if (uv.x > 0.5) a[k] = 0.0;
    a[2] = a[2] + 0.25;
    o = vec4(s, a[k], 0.25, 1.0);
}
