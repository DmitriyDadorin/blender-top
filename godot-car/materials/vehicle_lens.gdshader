shader_type spatial;
uniform mat4 part_to_vehicle;
uniform vec4 lens_color : source_color = vec4(.85,.94,1.0,1.0);
uniform bool rear_lens = false;
uniform float head_energy = 0.0;
uniform float tail_energy = 0.0;
uniform float brake_energy = 0.0;
varying vec3 lamp_position;
void vertex(){lamp_position=(part_to_vehicle*vec4(VERTEX,1.0)).xyz;}
void fragment(){
    bool tail=rear_lens || (lamp_position.z>.5 && abs(lamp_position.x)>.3 && lamp_position.y>.8);
    vec3 color=tail ? vec3(.48,.006,.003) : lens_color.rgb;
    float energy=tail ? max(tail_energy,brake_energy) : (lamp_position.z<-.5 ? head_energy : head_energy*.025);
    ALBEDO=color;
    EMISSION=color*energy;
    ROUGHNESS=.24;
    SPECULAR=.3;
}
