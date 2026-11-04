#version 450
layout(location=0) in vec2 uv;
layout(location=1) in vec4 col;
layout(location=0) out vec4 o;
void main() {
    vec4 c = col;
    float t = uv.x * 3.0 + uv.y;
    if (c.r > 0.9) {
        t = sin(t) * cos(t + 0.5) + 0.1;
        t = sin(t) * cos(t + 1.5) + 0.2;
        t = sin(t) * cos(t + 2.5) + 0.3;
        t = sin(t) * cos(t + 3.5) + 0.4;
        t = sin(t) * cos(t + 4.5) + 0.5;
        t = sin(t) * cos(t + 5.5) + 0.6;
        t = sin(t) * cos(t + 6.5) + 0.7;
        t = sin(t) * cos(t + 7.5) + 0.8;
        t = sin(t) * cos(t + 8.5) + 0.9;
        t = sin(t) * cos(t + 9.5) + 0.1;
        t = sin(t) * cos(t + 10.5) + 0.2;
        t = sin(t) * cos(t + 11.5) + 0.3;
        t = sin(t) * cos(t + 12.5) + 0.4;
        t = sin(t) * cos(t + 13.5) + 0.5;
        t = sin(t) * cos(t + 14.5) + 0.6;
        t = sin(t) * cos(t + 15.5) + 0.7;
        t = sin(t) * cos(t + 16.5) + 0.8;
        t = sin(t) * cos(t + 17.5) + 0.9;
        t = sin(t) * cos(t + 18.5) + 0.1;
        t = sin(t) * cos(t + 19.5) + 0.2;
        t = sin(t) * cos(t + 20.5) + 0.3;
        t = sin(t) * cos(t + 21.5) + 0.4;
        t = sin(t) * cos(t + 22.5) + 0.5;
        t = sin(t) * cos(t + 23.5) + 0.6;
        c.g = t;
    }
    if (uv.x > 0.5) { c.b = sin(uv.y * 3.0) * 0.5 + 0.5; }
    o = c;
}
