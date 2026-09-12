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
// Hollow 3D square frames rise straight up, concentric on the entity axis.
uniform float spawn_height = 0.03;
uniform float rise_speed = 0.4;         // Lowered default to maximize tightly packed spawning
uniform float rise_acceleration = 6.0; // Added acceleration strength multiplier
uniform float acceleration_curve = 2.5; // Controls the exponential separation curve aggressiveness
uniform float square_size = 0.65;
uniform float yaw_angle = 0.0;

void m0_initialize(inout Particle particle) {
particle.initial_position = vec3(0.0, spawn_height, 0.0);
particle.initial_velocity = vec3(0.0, rise_speed, 0.0);
particle.initial_scale = vec3(square_size);
particle.rotation_axis = vec3(0.0, 1.0, 0.0);
particle.initial_rotation = yaw_angle * DEG_TO_RAD;
}

group_uniforms Color;
uniform sampler2D u_m2_rgb : source_color, repeat_disable;

uniform sampler2D u_m2_alpha : repeat_disable;

void m2_scale_color(inout Particle particle) {
vec4 c = vec4(texture(u_m2_rgb, vec2(particle.normalized_age)));
float a = texture(u_m2_alpha, vec2(particle.normalized_age)).r;
particle.color = particle.initial_color * vec4(c.rgb, a);
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
m2_scale_color(particle);

// --- SMOKE SIGNAL ACCELERATION LOGIC ---
// 1. Determine local upward movement direction scaled by the emitter's orientation matrix.
vec3 upward_dir = (particle.emission_transform * vec4(0.0, 1.0, 0.0, 0.0)).xyz;

// 2. Compute exponential scaling. A higher value on 'acceleration_curve' keeps particles bunched 
// low for longer before they break away.
float speed_multiplier = pow(particle.normalized_age, acceleration_curve);

// 3. Assign an age-dependent, absolute velocity. It overrides the frame-by-frame addition, 
// guaranteeing perfect spacing irrespective of sub-frame timing variations.
particle.velocity = (particle.emission_transform * vec4(particle.initial_velocity, 0.0)).xyz + (upward_dir * rise_acceleration * speed_multiplier * particle.lifetime);

// 4. Step position forward using calculated velocity
particle.position += particle.velocity * particle.delta;
VELOCITY = particle.velocity;
// ---------------------------------------

TRANSFORM[0].xyz = particle.orientation[0] * particle.scale.x;
TRANSFORM[1].xyz = particle.orientation[1] * particle.scale.y;
TRANSFORM[2].xyz = particle.orientation[2] * particle.scale.z;
TRANSFORM[3].xyz = particle.position;
COLOR = particle.color;
CUSTOM.x = particle.rotation;

if (particle.age >= LIFETIME) { ACTIVE = false;  }
}
