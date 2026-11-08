shader_type spatial;
render_mode world_vertex_coords;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_color : source_color = vec4(.3,.3,.28,1.0);
uniform bool use_texture = false;
uniform bool coastal_cutoff = false;
varying vec3 world_position;
varying vec3 world_normal;
void vertex(){world_position=VERTEX;world_normal=NORMAL;}
float pool(vec2 p,vec2 lamp){
    float d=length((p-lamp)/vec2(19.0,24.0));
    return pow(max(0.0,1.0-d),1.4);
}
float lamp_irradiance(vec2 p){
    vec2 axis=clamp(round(p/160.0)*160.0,vec2(-480.0),vec2(480.0));
    vec2 along=clamp(round((p+420.0)/40.0)*40.0-420.0,vec2(-420.0),vec2(460.0));
    float vertical=pool(p,vec2(axis.x-6.2,along.y))+pool(p,vec2(axis.x+6.2,along.y));
    float horizontal=pool(p.yx,vec2(axis.y-6.2,along.x))+pool(p.yx,vec2(axis.y+6.2,along.x));
    return min(1.0,max(vertical,horizontal));
}
void fragment(){
    if(coastal_cutoff && world_position.x< -495.0)discard;
    ALBEDO=use_texture ? texture(surface_texture,UV).rgb : base_color.rgb;
    ROUGHNESS=.86;
    SPECULAR=.25;
    float ground=step(.5,world_normal.y)*(1.0-smoothstep(.4,1.0,world_position.y));
    // Fixed lamp illumination is evaluated like a baked surface light. Actual
    // nearby lights illuminate cars/people; the player's beams remain dynamic.
    EMISSION=ALBEDO*vec3(1.0,.62,.28)*lamp_irradiance(world_position.xz)*ground*.8;
}
