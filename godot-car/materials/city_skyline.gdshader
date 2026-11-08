shader_type spatial;
render_mode world_vertex_coords;
uniform float night_factor = 0.0;
varying vec3 position_world;
varying vec3 normal_world;
void vertex() {
    position_world = VERTEX;
    normal_world = NORMAL;
}
// Integrate a periodic rectangle over a pixel footprint instead of sampling
// a sharp fract() grid. Subpixel windows converge to their average coverage.
float pulse_integral(float x,float begin,float end) {
    return floor(x)*(end-begin)+clamp(fract(x)-begin,0.0,end-begin);
}
float filtered_pulse(float x,float width,float begin,float end) {
    float w=max(width,0.0001);
    return clamp((pulse_integral(x+w*.5,begin,end)-pulse_integral(x-w*.5,begin,end))/w,0.0,1.0);
}
void fragment() {
    vec3 n=normalize(normal_world);
    float frontage=abs(n.x)>.5 ? position_world.z : position_world.x;
    vec2 coord=vec2(frontage/3.7,position_world.y/3.8);
    vec2 footprint=max(fwidth(coord),vec2(0.0001));
    float window=filtered_pulse(coord.x,footprint.x,.17,.78)*filtered_pulse(coord.y,footprint.y,.20,.76);
    float average_coverage=(.78-.17)*(.76-.20);
    float unresolved=smoothstep(.35,.9,max(footprint.x,footprint.y));
    window=mix(window,average_coverage,unresolved);
    window*=1.0-step(.5,abs(n.y));
    ALBEDO=mix(COLOR.rgb,vec3(.075,.125,.16),window*.65);
    float random=fract(sin(dot(floor(coord),vec2(12.9898,78.233)))*43758.5453);
    float lit=mix(step(.55,random),.45,unresolved);
    EMISSION=window*lit*night_factor*vec3(.30,.17,.07);
    float glass=window*(1.0-unresolved);
    METALLIC=0.0;
    ROUGHNESS=mix(.85,.36,glass);
    SPECULAR=mix(.18,.40,glass);
    CLEARCOAT=.10*glass;
    CLEARCOAT_ROUGHNESS=.4;
}
