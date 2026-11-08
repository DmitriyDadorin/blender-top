shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
uniform sampler2D facade_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D window_mask : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D window_data : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D reflection_north : source_color, filter_linear_mipmap;
uniform sampler2D reflection_south : source_color, filter_linear_mipmap;
uniform float night_factor = 0.0;
uniform float reflection_exposure = 1.0;
uniform float reflection_amount : hint_range(0.0,1.0) = 1.0;
uniform float glass_roughness : hint_range(.12,.6) = .17;
uniform float glass_specular : hint_range(0.0,1.0) = .55;
uniform float room_depth : hint_range(.5,4.0) = 1.9;
varying vec3 normal_world;
varying vec3 position_world;
varying float pane_coverage;
void vertex(){normal_world=NORMAL;position_world=VERTEX;}
vec3 interior_color(vec2 pane,vec3 eye){
    // Trace into a room behind the glass. The wall stays one opaque surface,
    // while the visible ceiling / floor / back wall changes with the viewpoint.
    vec3 origin=vec3((pane*2.0-1.0)*vec2(1.0,1.05),0.0);
    vec3 ray=normalize(vec3(-eye.xy,-max(eye.z,.05)));
    vec2 dir=ray.xy;
    dir.x=abs(dir.x)<.00001 ? .00001 : dir.x;
    dir.y=abs(dir.y)<.00001 ? .00001 : dir.y;
    vec2 side=step(vec2(0.0),dir)*2.0-1.0;
    vec2 side_t=(side*vec2(1.6,1.35)-origin.xy)/dir;
    float back_t=-room_depth/ray.z;
    float t=min(back_t,min(side_t.x,side_t.y));
    vec3 hit=origin+ray*t;
    vec3 room=vec3(.065,.083,.093);
    if(side_t.y<min(back_t,side_t.x)){
        room=dir.y>0.0 ? vec3(.13,.145,.15) : vec3(.025,.035,.045);
    }else if(side_t.x<back_t){
        room=vec3(.075,.09,.10);
    }else{
        // Broad interior shapes, not fine textures that could shimmer at distance.
        float furniture=(1.0-smoothstep(.65,.78,abs(hit.x-.2)))*(1.0-smoothstep(-.55,-.43,hit.y));
        room=mix(room,vec3(.025,.034,.04),furniture*.6);
    }
    return room;
}
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
    float glass=texture(window_mask,UV).r;
    vec3 data=texture(window_data,UV).rgb;
    vec3 wall=texture(facade_albedo,UV).rgb;
    vec2 footprint=fwidth(UV*4.0);
    float resolved=1.0-smoothstep(.10,.45,max(footprint.x,footprint.y));
    vec2 pane=clamp(data.gb/max(data.r,.0001),vec2(.015),vec2(.985));
    pane=mix(vec2(.5),pane,resolved);
    vec3 n=normalize(normal_world);
    if(!FRONT_FACING)n=-n;
    // This axis follows the baked UV orientation on each vertical wall.
    vec3 horizontal=abs(n.x)>.5 ? vec3(0,0,1) : vec3(1,0,0);
    vec3 eye_world=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
    vec3 eye=vec3(dot(eye_world,horizontal),eye_world.y,abs(dot(eye_world,n)));
    vec3 room=interior_color(pane,eye)*vec3(.65,.82,.95);
    room=mix(vec3(.035,.06,.075),room,resolved);
    float edge=min(min(pane.x,1.0-pane.x),min(pane.y,1.0-pane.y));
    float seal=(1.0-smoothstep(.018,.045,edge))*resolved;
    room=mix(room,vec3(.008,.012,.016),seal*.85);
    vec2 bend=(pane-.5)*vec2(.004,.003)*glass*resolved;
    vec3 bent=normalize(n+horizontal*bend.x+vec3(0,1,0)*bend.y);
    NORMAL=normalize((VIEW_MATRIX*vec4(bent,0.0)).xyz);
    vec3 reflection_direction=reflect(-eye_world,bent);
    float blur=mix(3.0,.25,resolved);
    vec3 north=textureLod(reflection_north,reflection_uv(reflection_direction),blur).rgb;
    vec3 south=textureLod(reflection_south,reflection_uv(reflection_direction),blur).rgb;
    vec3 reflected=mix(north,south,smoothstep(-160.0,160.0,position_world.z));
    float fresnel=(.46+.45*pow(1.0-clamp(dot(bent,eye_world),0.0,1.0),5.0))*reflection_amount;
    ALBEDO=mix(wall,room*(1.0-fresnel),glass);
    // Captured environmental radiance remains visible in shaded windows.
    vec2 cell=floor(UV*4.0)+floor(position_world.xz/160.0)*vec2(17.0,31.0);
    float random=fract(sin(dot(cell,vec2(12.9898,78.233)))*43758.5453);
    float occupied=mix(step(.48,random),.52,1.0-resolved);
    vec3 room_light=mix(vec3(.80,.46,.20),vec3(.45,.55,.65),step(.82,random));
    float room_shading=mix(.65,clamp(dot(room,vec3(.3333))*10.0,.3,1.0),resolved);
    EMISSION=reflected*fresnel*glass*(1.0-seal*.85)*reflection_exposure+room_light*room_shading*occupied*glass*(1.0-seal*.85)*night_factor;
    pane_coverage=glass*(1.0-seal*.8);
    METALLIC=0.0;
    ROUGHNESS=mix(.85,mix(.44,glass_roughness,resolved),pane_coverage);
    SPECULAR=mix(.18,0.0,pane_coverage);
    CLEARCOAT=0.0;
    CLEARCOAT_ROUGHNESS=.28;
}
void light(){
    float facing=max(dot(NORMAL,LIGHT),0.0);
    DIFFUSE_LIGHT+=facing*ATTENUATION*LIGHT_COLOR/PI;
    // Keep clear environment reflections but bound the direct solar highlight,
    // so the sun gives a soft glint instead of flashing white window-sized patches.
    vec3 half_vector=normalize(LIGHT+VIEW);
    float glint=pow(max(dot(NORMAL,half_vector),0.0),56.0);
    SPECULAR_LIGHT+=LIGHT_COLOR*ATTENUATION*facing*glint*pane_coverage*glass_specular*.065;
}
