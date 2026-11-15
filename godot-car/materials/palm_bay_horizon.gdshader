shader_type spatial;
render_mode world_vertex_coords;
uniform vec4 base_color : source_color = vec4(.055,.32,.19,1.0);
uniform vec3 haze_color : source_color = vec3(.96,.56,.41);
uniform bool sea_surface = false;
varying vec3 world_pos;
void vertex(){world_pos=VERTEX;}
void fragment(){
    vec2 offset=world_pos.xz-CAMERA_POSITION_WORLD.xz;
    float distance_to_eye=length(offset);
    float haze=smoothstep(550.0,2100.0,distance_to_eye);
    vec3 color=base_color.rgb;
    if(sea_surface){
        vec2 sun_axis=normalize(vec2(-.904,-.329));
        float alignment=max(0.0,dot(normalize(offset+vec2(.001)),sun_axis));
        float reflection=pow(alignment,48.0)*smoothstep(45.0,400.0,distance_to_eye)*(1.0-haze)*.38;
        color=mix(color,vec3(.94,.44,.19),reflection);
        ALBEDO=vec3(0.0);
        EMISSION=mix(color,haze_color,haze);
    }else{
        ALBEDO=color*(1.0-haze);
        EMISSION=haze_color*haze;
    }
    ROUGHNESS=.96;
    SPECULAR=0.0;
}
