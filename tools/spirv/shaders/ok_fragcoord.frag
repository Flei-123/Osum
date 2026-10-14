#version 450
layout(location=0) out vec4 o;
void main() { o = vec4(gl_FragCoord.xy / 320.0, 0.0, 1.0); }
