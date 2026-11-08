shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
uniform sampler2D reflection_north : source_color, filter_linear_mipmap;
uniform sampler2D reflection_south : source_color, filter_linear_mipmap;
uniform float reflection_exposure = 1.0;
uniform float reflection_amount : hint_range(0.0,1.0) = 1.0;
varying vec3 world_position;
varying vec3 world_normal;
void vertex(){world_position=VERTEX;world_normal=NORMAL;}
vec2 reflection_uv(vec3 d){
    vec3 a=abs(d);
    vec2 uv;float face;
    if(a.x>=max(a.y,a.z)){
        face=d.x>0.0?0.0:1.0;
        uv=vec2(d.x>0.0?d.z:-d.z,-d.y)/a.x;
    }else if(a.y>=a.z){
        face=d.y>0.0?2.0:3.0;
        uv=vec2(-d.x,d.y>0.0?d.z:-d.z)/a.y;
    }else{
        face=d.z>0.0?4.0:5.0;
        uv=vec2(d.z>0.0?-d.x:d.x,-d.y)/a.z;
    }
    uv=clamp(uv*.5+.5,vec2(.006),vec2(.994));
    return (uv+vec2(mod(face,3.0),floor(face/3.0)))/vec2(3.0,2.0);
}
void fragment(){
    vec3 n=normalize(world_normal);
    if(!FRONT_FACING)n=-n;
    vec3 eye=normalize(CAMERA_POSITION_WORLD-world_position);
    vec2 uv=reflection_uv(reflect(-eye,n));
    vec3 north=textureLod(reflection_north,uv,.5).rgb;
    vec3 south=textureLod(reflection_south,uv,.5).rgb;
    vec3 reflected=mix(north,south,smoothstep(-160.0,160.0,world_position.z));
    float fresnel=(.25+.60*pow(1.0-clamp(dot(n,eye),0.0,1.0),5.0))*reflection_amount;
    ALBEDO=vec3(.008,.014,.018)*(1.0-fresnel);
    EMISSION=reflected*fresnel*vec3(.88,.95,1.0)*reflection_exposure;
    ROUGHNESS=.14;
    SPECULAR=0.0;
    NORMAL=normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
}
void light(){
    float facing=max(dot(NORMAL,LIGHT),0.0);
    DIFFUSE_LIGHT+=facing*LIGHT_COLOR*ATTENUATION/PI;
    float glint=pow(max(dot(NORMAL,normalize(LIGHT+VIEW)),0.0),96.0);
    SPECULAR_LIGHT+=LIGHT_COLOR*ATTENUATION*facing*glint*.08;
}
