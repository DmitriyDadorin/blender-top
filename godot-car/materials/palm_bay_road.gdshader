shader_type spatial;
render_mode world_vertex_coords;
uniform vec4 base_color : source_color = vec4(.075,.12,.19,1.0);
uniform vec3 edge_color : source_color = vec3(.96,.89,.74);
uniform vec3 center_color : source_color = vec3(.98,.75,.36);
varying vec3 world_pos;
void vertex(){world_pos=VERTEX;}
float band(float distance_to_center,float half_width){
    float aa=max(fwidth(distance_to_center),.003);
    return 1.0-smoothstep(half_width-aa,half_width+aa,distance_to_center);
}
void fragment(){
    vec2 grid=abs(mod(world_pos.xz+80.0,160.0)-80.0);
    // All paint belongs to the road's one surface. No floating stripe meshes.
    float vertical=1.0-step(7.01,grid.x);
    float horizontal=1.0-step(7.01,grid.y);
    float edge_v=band(abs(grid.x-6.55),.07)*smoothstep(8.0,9.0,grid.y)*vertical;
    float edge_h=band(abs(grid.y-6.55),.07)*smoothstep(8.0,9.0,grid.x)*horizontal;
    float dash_v=band(abs(mod(world_pos.z+6.0,12.0)-6.0),2.5);
    float dash_h=band(abs(mod(world_pos.x+6.0,12.0)-6.0),2.5);
    float mid_v=band(grid.x,.075)*dash_v*smoothstep(16.0,17.0,grid.y)*vertical;
    float mid_h=band(grid.y,.075)*dash_h*smoothstep(16.0,17.0,grid.x)*horizontal;
    float zebra_v=band(abs(grid.y-11.0),1.45)*band(abs(mod(world_pos.x+.8,1.6)-.8),.39)*(1.0-smoothstep(5.8,6.0,grid.x))*vertical;
    float zebra_h=band(abs(grid.x-11.0),1.45)*band(abs(mod(world_pos.z+.8,1.6)-.8),.39)*(1.0-smoothstep(5.8,6.0,grid.y))*horizontal;
    float white=clamp(max(max(edge_v,edge_h),max(zebra_v,zebra_h)),0.0,1.0);
    ALBEDO=mix(base_color.rgb,edge_color,white);
    ALBEDO=mix(ALBEDO,center_color,clamp(max(mid_v,mid_h),0.0,1.0));
    ROUGHNESS=.96;
    SPECULAR=.05;
}
