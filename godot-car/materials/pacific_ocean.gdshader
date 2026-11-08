shader_type spatial;
render_mode world_vertex_coords;
uniform vec4 harbor_lights[16];
uniform int harbor_light_count = 0;
uniform float harbor_night = 0.0;
varying vec3 position_world;
void vertex() {
    position_world = VERTEX;
    VERTEX.y += sin(VERTEX.x*.08+VERTEX.z*.025+TIME*.5)*.055;
}
void fragment() {
    float x=position_world.x;
    float z=position_world.z;
    float slope_x=cos(x*.23+z*.07+TIME*.7)*.045 + cos(x*.9-z*.3+TIME)*.025;
    float slope_z=cos(x*.23+z*.07+TIME*.7)*.025 - cos(x*.9-z*.3+TIME)*.035;
    vec3 normal_world=normalize(vec3(-slope_x,1.0,-slope_z));
    NORMAL=normalize((VIEW_MATRIX*vec4(normal_world,0.0)).xyz);
    float coast_distance=max(0.0,-x-538.0);
    vec3 water=mix(vec3(.025,.22,.24),vec3(.012,.065,.12),smoothstep(0.0,500.0,coast_distance));
    float fresnel=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),4.0);
    water=mix(water,vec3(.20,.36,.46),fresnel*.45);
    float foam_wave=sin(coast_distance*.55+sin(z*.065)*1.3-TIME*.75)*.5+.5;
    float foam=smoothstep(.77,.96,foam_wave)*(1.0-smoothstep(0.0,18.0,coast_distance));
    ALBEDO=mix(water,vec3(.65,.76,.73),foam*.65);
    ROUGHNESS=mix(.23,.6,foam);
    METALLIC=.15;
    SPECULAR=.35;
    vec3 reflections=vec3(0.0);
    if(harbor_night>.5){
        for(int i=0;i<16;i++){
            if(i>=harbor_light_count)break;
            vec2 origin=harbor_lights[i].xy;
            vec2 direction=normalize(CAMERA_POSITION_WORLD.xz-origin);
            vec2 relative=position_world.xz-origin;
            float along=dot(relative,direction);
            float across=abs(dot(relative,vec2(-direction.y,direction.x)));
            float width=harbor_lights[i].z*(1.0+max(along,0.0)*.008);
            if(along> -3.0 && along<180.0 && across<width*2.5){
                float shimmer=.35+.65*pow(.5+.5*sin(x*.7+z*.51+TIME*.8),3.0);
                float strength=exp(-across*across/(width*width))*exp(-max(along,0.0)/55.0)*smoothstep(-3.0,1.0,along);
                reflections+=vec3(.38,.20,.065)*strength*shimmer*harbor_lights[i].w;
            }
        }
    }
    EMISSION=reflections*harbor_night;
}
