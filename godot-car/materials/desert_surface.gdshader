shader_type spatial;
render_mode world_vertex_coords;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D height_tex : filter_linear_mipmap, repeat_enable;
uniform int surface_kind = 0; // 0: sand, 1: asphalt, 2: eroded rock, 3: worn paint
uniform vec3 paint_color : source_color = vec3(0.8);
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
    world_pos = VERTEX;
    world_normal = NORMAL;
}
void fragment() {
    vec3 n = normalize(world_normal);
    vec3 weights = pow(abs(n), vec3(4.0));
    weights /= max(dot(weights,vec3(1.0)),0.0001);
    float scale = surface_kind == 1 ? 0.42 : (surface_kind == 2 ? 0.2 : 0.7);
    vec3 col = texture(albedo_tex,world_pos.yz*scale).rgb*weights.x
             + texture(albedo_tex,world_pos.xz*scale).rgb*weights.y
             + texture(albedo_tex,world_pos.xy*scale).rgb*weights.z;
    float macro = texture(height_tex, world_pos.xz*0.007).r;
    col *= mix(0.88,1.1,macro);
    if (surface_kind == 1) {
        // Soft dusty edges and lightly polished wheel tracks.
        float edge_dust = smoothstep(3.35,4.25,abs(world_pos.x));
        col = mix(col,vec3(0.26,0.225,0.17),edge_dust*0.32);
        float tracks = exp(-pow((abs(world_pos.x)-2.05)/0.6,2.0));
        col *= 1.0-tracks*0.12;
    }
    if (surface_kind == 2) {
        float strata = sin(world_pos.y*1.3 + macro*3.0)*0.04;
        col *= 1.0+strata;
    }
    if (surface_kind == 3) {
        float wear = smoothstep(0.56,0.68,texture(height_tex,world_pos.xz*3.5).r);
        col = mix(paint_color,vec3(0.11),wear*0.55);
    }
    vec2 uv = world_pos.xz*scale;
    float hx = texture(height_tex,uv+vec2(0.001,0.0)).r - texture(height_tex,uv-vec2(0.001,0.0)).r;
    float hz = texture(height_tex,uv+vec2(0.0,0.001)).r - texture(height_tex,uv-vec2(0.0,0.001)).r;
    vec3 detail_n = normalize(n - vec3(hx,0.0,hz)*0.2*weights.y);
    NORMAL = normalize((VIEW_MATRIX * vec4(detail_n,0.0)).xyz);
    ALBEDO = col;
    ROUGHNESS = surface_kind == 1 ? 0.88 : 0.96;
}
