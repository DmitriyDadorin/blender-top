shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
uniform vec4 leaf_color : source_color = vec4(.15,.28,.07,1.0);
void vertex(){
    float breeze=sin(TIME*1.15+VERTEX.x*.83+VERTEX.z*.67)*.028;
    float flutter=sin(TIME*2.1+VERTEX.z*3.7)*.009;
    VERTEX.x+=breeze+flutter;
    VERTEX.z+=breeze*.4;
}
void fragment(){
    ALBEDO=leaf_color.rgb;
    ROUGHNESS=.84;
    SPECULAR=.18;
    if(!FRONT_FACING)NORMAL=-NORMAL;
}
void light(){
    float facing=dot(NORMAL,LIGHT);
    // Thin leaves transmit some back light; no alpha blending or flat crown shell.
    float diffuse=max(facing,0.0)+max(-facing,0.0)*.22;
    DIFFUSE_LIGHT+=diffuse*LIGHT_COLOR*ATTENUATION/PI;
}
