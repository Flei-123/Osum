#version 450
layout(location=0) in vec2 uv;
layout(location=0) out vec4 o;
void main() {
    int n = int(uv.x * 8.0);
    float s = 0.0;
    for (int i = 0; i < n; i++) { s += 1.0; if (i == 5) break; }
    float t = 0.0;
    int j = 0;
    while (j < 3) { j++; if (j == 2) continue; t += 0.25; }
    float w = 0.0;
    int k = 0;
    do { w += 0.125; k++; } while (k < int(uv.y * 4.0) + 1);
    o = vec4(s / 8.0, t, w, 1.0);
}
