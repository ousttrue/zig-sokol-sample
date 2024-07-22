@vs vs
uniform vs_params {
  mat4 u_modelMatrix;
  mat4 u_viewProj;
};

in vec3 inPosition;
in vec3 inNormal;

out vec3 v_position;
out vec3 v_normal;

void main()
{
    vec4 worldPos = u_modelMatrix * vec4(inPosition, 1);
    v_position = worldPos.xyz;
    v_normal = normalize((u_modelMatrix * vec4(inNormal,0)).xyz);
    gl_Position = u_viewProj * worldPos;
}
@end

@fs fs
uniform fs_params {
  vec3 u_diffuse;
  vec3 u_eye;
};

in vec3 v_position;
in vec3 v_normal;

out vec4 f_color;

vec3 compute_lighting(vec3 eyeDir, vec3 position, vec3 color)
{
    vec3 light = vec3(0, 0, 0);
    vec3 lightDir = normalize(position - v_position);
    light += color * u_diffuse * max(dot(v_normal, lightDir), 0);
    vec3 halfDir = normalize(lightDir + eyeDir);
    light += color * u_diffuse * pow(max(dot(v_normal, halfDir), 0), 128);
    return light;
}

void main()
{
    vec3 eyeDir = vec3(0, 1, -2);
    vec3 light = vec3(0, 0, 0);
    light += compute_lighting(eyeDir, vec3(+3, 1, 0), vec3(235.0/255.0, 43.0/255.0, 211.0/255.0));
    light += compute_lighting(eyeDir, vec3(-3, 1, 0), vec3(43.0/255.0, 236.0/255.0, 234.0/255.0));
    f_color = vec4(light + vec3(0.5, 0.5, 0.5), 1.0);
}
@end

@program teapot vs fs
