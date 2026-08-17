#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float widthPx;
    float heightPx;
    float minH;
    float maxH;
    float barCount;
    float barGap;
    vec4 bandsA;
    vec2 bandsB;
    vec4 fillColor;
} ubuf;

float getBandLevel(int idx) {
    if (idx <= 0) return ubuf.bandsA.x;
    if (idx == 1) return ubuf.bandsA.y;
    if (idx == 2) return ubuf.bandsA.z;
    if (idx == 3) return ubuf.bandsA.w;
    if (idx == 4) return ubuf.bandsB.x;
    return ubuf.bandsB.y;
}

float getInterpolatedLevel(float fi, float count) {
    if (count <= 1.0) return ubuf.bandsA.x;
    float t = (fi / (count - 1.0)) * 5.0;
    int idx = int(floor(t));
    if (idx >= 5) return ubuf.bandsB.y;
    if (idx < 0) return ubuf.bandsA.x;
    float f = fract(t);
    float sf = f * f * (3.0 - 2.0 * f);
    float l1 = getBandLevel(idx);
    float l2 = getBandLevel(idx + 1);
    return mix(l1, l2, sf);
}

float sdRoundBar(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 px = vec2(qt_TexCoord0.x * ubuf.widthPx, qt_TexCoord0.y * ubuf.heightPx);
    float count = clamp(ubuf.barCount, 2.0, 32.0);
    float gap = max(0.5, ubuf.barGap);

    float availW = ubuf.widthPx - (count - 1.0) * gap;
    float barW = max(1.0, availW / count);
    float slot = barW + gap;
    float totalW = count * barW + (count - 1.0) * gap;
    float x0 = (ubuf.widthPx - totalW) * 0.5;

    float fi = floor((px.x - x0) / slot);

    if (fi < 0.0 || fi >= count) {
        fragColor = vec4(0.0);
        return;
    }

    float lvl = getInterpolatedLevel(fi, count);
    float h = ubuf.minH + clamp(lvl, 0.0, 1.0) * (ubuf.maxH - ubuf.minH);

    float lx = px.x - x0 - fi * slot;
    vec2 p = vec2(lx - barW * 0.5, px.y - ubuf.heightPx * 0.5);
    float radius = min(barW * 0.5, 1.5);
    float d = sdRoundBar(p, vec2(barW * 0.5, h * 0.5), radius);
    float mask = 1.0 - smoothstep(-0.6, 0.6, d);

    float a = ubuf.fillColor.a * mask * ubuf.qt_Opacity;
    fragColor = vec4(ubuf.fillColor.rgb * a, a);
}
