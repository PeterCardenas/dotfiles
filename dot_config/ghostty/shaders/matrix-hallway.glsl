// #iChannel0 "file:///Users/asherwin/.config/ghostty/myshaders/screen2.png"

// based on the following Shader Toy entry
//
// [SH17A] Matrix rain. Created by Reinder Nijhoff 2017
// Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License.
// @reindernijhoff
//
// https://www.shadertoy.com/view/ldjBW1
//

#define SPEED_MULTIPLIER 1.
#define GREEN_ALPHA .02

#define BLACK_BLEND_THRESHOLD .4

#define R fract(1e2 * sin(p.x * 8. + p.y))

void mainImage(out vec4 fragColor, vec2 fragCoord) {
    vec3 v = vec3(fragCoord, 1) / iResolution - .5;
    // Further reduce scaling to reach deeper into center
    vec3 s = .25 / abs(v);
    s.z = min(s.y, s.x);
    vec3 i = ceil(8e2 * s.z * (s.y < s.x ? v.xzz : v.zyz)) * .1;
    vec3 j = fract(i);
    i -= j;
    vec3 p = vec3(9, int(iTime * SPEED_MULTIPLIER * (9. + 8. * sin(i).x)), 0) + i;
    vec3 col = fragColor.rgb;
    float intensity = R / s.z;
    // Mix gray with a slight blue tint (0.8, 0.85, 1.0 creates a subtle blue-gray)
    col = vec3(0.8 * intensity, 0.85 * intensity, 1.0 * intensity);
    p *= j;
    col *= (R > .5 && j.x < .6 && j.y < .8) ? GREEN_ALPHA : 0.;

    // Sample the terminal screen texture including alpha channel
    vec2 uv = fragCoord.xy / iResolution.xy;
    vec4 terminalColor = texture(iChannel0, uv);

    // Add the matrix effect on top of the terminal color
    vec3 blendedColor = terminalColor.rgb + col * 0.8;

    // Preserve the original color where there's terminal content
    float isContent = step(BLACK_BLEND_THRESHOLD, length(terminalColor.rgb));
    blendedColor = mix(terminalColor.rgb, blendedColor, 1.0 - isContent);

    fragColor = vec4(blendedColor, terminalColor.a);
}
