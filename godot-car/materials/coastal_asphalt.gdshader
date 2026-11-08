shader_type spatial;
render_mode world_vertex_coords;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float coast_cutoff = -495.0;
varying float position_x;
void vertex(){position_x=VERTEX.x;}
void fragment(){
    // Stop the asphalt at the landward promenade edge: the two surfaces
    // otherwise overlap at exactly the same height along the whole coastal strip.
    if(position_x < coast_cutoff) discard;
    ALBEDO=texture(asphalt_tex,UV).rgb;
    ROUGHNESS=.9;
}
