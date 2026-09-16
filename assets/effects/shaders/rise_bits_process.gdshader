shader_type particles;
render_mode disable_velocity;

const float DEG_TO_RAD = PI / 180.0;
const uint AMOUNT = uint(1);

struct Particle {
uint seed;
float delta;
float lifetime;
uint index;
uint number;
float age;
float normalized_age;
float normalized_index;
float normalized_number;
vec3 initial_position;
vec3 initial_scale;
vec4 initial_color;
vec3 initial_velocity;
float radial_velocity;
vec3 orbital_axis;
float initial_orbital_speed;
vec3 spawn_direction;
vec3 position;
vec3 scale;
vec4 color;
vec3 velocity;
vec3 orbital_velocity;
float orbital_speed;
vec3 rotation_axis;
float initial_rotation;
float rotation;
mat3 orientation;
vec3 force;
float animation_frame_normalized;
mat4 emission_transform;
mat4 previous_transform;
bool just_spawned;
bool collided;
vec3 collision_normal;
float collision_depth;
};

float rand(inout uint seed) {
int k;
int s = int(seed);
if (s == 0) {
		s = 305420679;
}
k = s / 127773;
s = 16807 * (s - k * 127773) - 2836 * k;
if (s < 0) {
s += 2147483647;
}
seed = uint(s);
return float(seed % uint(65536)) / 65535.0;
}

float rand_range(inout uint seed, float l, float h) {
return l + (h - l) * rand(seed);
}

uint hash(uint x) {
x = ((x >> uint(16)) ^ x) * uint(73244475);
x = ((x >> uint(16)) ^ x) * uint(73244475);
x = (x >> uint(16)) ^ x;
return x;
}

vec4 quat(vec3 axis, float angle) {
float s = sin(angle / 2.0);
return vec4(axis.x * s, axis.y * s, axis.z * s, cos(angle / 2.0));
}

vec3 rotated(vec3 v, vec3 axis, float angle) {
vec4 q = quat(axis, angle);
vec3 t = cross(q.xyz, v) + q.w * v;
return v + 2.0 * cross(q.xyz, t);
}

vec3 rotated(vec3 v, vec4 q) {
vec3 t = cross(q.xyz, v) + q.w * v;
return v + 2.0 * cross(q.xyz, t);
}

mat3 rotated(mat3 m, vec4 q) {
return mat3(rotated(m[0], q), rotated(m[1], q), rotated(m[2], q));
}

group_uniforms Spawn;
// Small square shards scattered around the entity axis, rising straight up.
uniform float scatter_radius = 0.55;
uniform float spawn_height_min = 0.05;
uniform float spawn_height_max = 0.35;
uniform float drift = 0.25;

group_uniforms Speed;
uniform float rise_speed_min = 1.9;
uniform float rise_speed_max = 2.7;

group_uniforms Size;
uniform float bit_size = 1.0;

group_uniforms Color;
uniform sampler2D u_m1_scale : repeat_disable;

uniform sampler2D u_m2_rgb : source_color, repeat_disable;

uniform sampler2D u_m2_alpha : repeat_disable;

void m0_initialize(inout Particle particle) {
float ang = rand_range(particle.seed, 0.0, 6.2831853);
float rad = scatter_radius * rand(particle.seed);
particle.initial_position = vec3(cos(ang) * rad, rand_range(particle.seed, spawn_height_min, spawn_height_max), sin(ang) * rad);
particle.initial_velocity = vec3(rand_range(particle.seed, -drift, drift), rand_range(particle.seed, rise_speed_min, rise_speed_max), rand_range(particle.seed, -drift, drift));
particle.initial_scale = vec3(bit_size * rand_range(particle.seed, 0.7, 1.5));
particle.rotation_axis = vec3(0.0, 1.0, 0.0);
particle.initial_rotation = 0.0;
}

void m1_scale_size(inout Particle particle) {
float s = texture(u_m1_scale, vec2(particle.normalized_age)).r;
particle.scale *= vec3(s);
}

void m2_scale_color(inout Particle particle) {
vec4 c = vec4(texture(u_m2_rgb, vec2(particle.normalized_age)));
float a = texture(u_m2_alpha, vec2(particle.normalized_age)).r;
particle.color = particle.initial_color * vec4(c.rgb, a);
}

void m3_set_rotation(inout Particle particle) {
// Slight random tilt around a horizontal axis + slow spin around Y.
vec3 haxis = vec3(rand_range(particle.seed, -1.0, 1.0), 0.0, rand_range(particle.seed, -1.0, 1.0));
float l = length(haxis);
haxis = l > 0.0001 ? haxis / l : vec3(1.0, 0.0, 0.0);
float tilt = rand_range(particle.seed, -45.0, 45.0);
float spin = rand_range(particle.seed, -100.0, 100.0);
particle.orientation = rotated(mat3(1.0), quat(haxis, tilt * DEG_TO_RAD));
particle.orientation = rotated(particle.orientation, quat(vec3(0.0, 1.0, 0.0), spin * DEG_TO_RAD * particle.normalized_age));
}

void initialize(inout Particle particle) {
particle.initial_position = vec3(0.0);
particle.initial_color = vec4(1.0);
particle.initial_scale = vec3(1.0);
particle.initial_velocity = vec3(0.0);
particle.initial_orbital_speed = 0.0;
particle.spawn_direction = vec3(0.0);
particle.animation_frame_normalized = 0.0;
particle.rotation_axis = vec3(1.0, 0.0, 0.0);
particle.initial_rotation = 0.0;
particle.radial_velocity = 0.0;
particle.orbital_axis = vec3(0.0, 1.0, 0.0);
particle.orbital_velocity = vec3(0.0);
m0_initialize(particle);
particle.scale = particle.initial_scale;
particle.color = particle.initial_color;
particle.orbital_speed = particle.initial_orbital_speed;
}

void start() {
Particle particle;
// Use INDEX instead of NUMBER for repeatability.
uint base_number = NUMBER;
particle.seed = hash(base_number + uint(1) + RANDOM_SEED);
particle.lifetime = LIFETIME;
particle.index = INDEX;
particle.number = NUMBER;
particle.age = 0.0;
particle.normalized_age = 0.0;
particle.normalized_index = 0.0;
particle.normalized_number = 0.0;
particle.position = vec3(0.0);
initialize(particle);
if (rand(particle.seed) > AMOUNT_RATIO) {
ACTIVE = false;
}
if (RESTART_CUSTOM) {
CUSTOM = vec4(0.0);
CUSTOM.x = particle.initial_rotation;
}
if (RESTART_COLOR) {
COLOR = particle.initial_color;
}
if (RESTART_ROT_SCALE) {
TRANSFORM[0].xyz = rotated(vec3(1.0, 0.0, 0.0), particle.rotation_axis, particle.initial_rotation) * particle.initial_scale.x;
TRANSFORM[1].xyz = rotated(vec3(0.0, 1.0, 0.0), particle.rotation_axis, particle.initial_rotation) * particle.initial_scale.y;
TRANSFORM[2].xyz = rotated(vec3(0.0, 0.0, 1.0), particle.rotation_axis, particle.initial_rotation) * particle.initial_scale.z;
}
if (RESTART_POSITION) {
TRANSFORM[3].xyz = particle.initial_position;
TRANSFORM = EMISSION_TRANSFORM * TRANSFORM;
}
if (RESTART_VELOCITY) {
		VELOCITY = (EMISSION_TRANSFORM * vec4(particle.initial_velocity, 0.0)).xyz;
}
}

void process() {
Particle particle;
// Use INDEX instead of NUMBER for repeatability.
uint base_number = NUMBER;
particle.seed = hash(base_number + uint(1) + RANDOM_SEED);
particle.delta = DELTA;
particle.lifetime = LIFETIME;
particle.index = INDEX;
particle.number = NUMBER;
particle.age = 0.0;
particle.normalized_age = 0.0;
particle.normalized_index = 0.0;
particle.normalized_number = 0.0;
particle.position = TRANSFORM[3].xyz;
particle.velocity = VELOCITY;
particle.orientation = mat3(
normalize(TRANSFORM[0].xyz),
normalize(TRANSFORM[1].xyz),
normalize(TRANSFORM[2].xyz));
particle.force = vec3(0.0);
particle.emission_transform = EMISSION_TRANSFORM;
particle.previous_transform = TRANSFORM;
particle.rotation = CUSTOM.x;
particle.just_spawned = abs(CUSTOM.y) < 0.0001;
particle.collided = COLLIDED;
particle.collision_normal = COLLISION_NORMAL;
particle.collision_depth = COLLISION_DEPTH;
particle.color = COLOR;
initialize(particle);
CUSTOM.y += DELTA / particle.lifetime;
CUSTOM.y = mix(CUSTOM.y, 1.0, INTERPOLATE_TO_END);
CUSTOM.y = clamp(CUSTOM.y, 0.0, 1.0);
particle.age = CUSTOM.y * particle.lifetime;
particle.normalized_age = CUSTOM.y;
m1_scale_size(particle);
m2_scale_color(particle);
m3_set_rotation(particle);
particle.position += particle.velocity * particle.delta;
VELOCITY = particle.velocity;
TRANSFORM[0].xyz = particle.orientation[0] * particle.scale.x;
TRANSFORM[1].xyz = particle.orientation[1] * particle.scale.y;
TRANSFORM[2].xyz = particle.orientation[2] * particle.scale.z;
TRANSFORM[3].xyz = particle.position;
COLOR = particle.color;
CUSTOM.x = particle.rotation;

if (particle.age >= LIFETIME) { ACTIVE = false;  }
}
