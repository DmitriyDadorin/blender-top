shader_type sky;
uniform vec3 zenith : source_color = vec3(.055,.14,.40);
uniform vec3 upper_sky : source_color = vec3(.49,.35,.62);
uniform vec3 horizon : source_color = vec3(.96,.56,.41);
void sky(){
    float height=clamp(EYEDIR.y,0.0,1.0);
    vec3 color=mix(horizon,upper_sky,smoothstep(0.0,.36,height));
    color=mix(color,zenith,smoothstep(.20,.88,height));
    float sun_dot=dot(EYEDIR,normalize(vec3(-.904,.276,-.329)));
    float disc=smoothstep(cos(.041),cos(.0385),sun_dot);
    COLOR=mix(color,vec3(1.0,.86,.51),disc);
}
