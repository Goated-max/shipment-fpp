class_name Grenade
extends RigidBody3D
# Frag grenade: a rigid body that bounces off the arena and detonates after its fuse.

const FUSE := 2.0
const RADIUS := 6.0
const DAMAGE := 110.0
const SELF_RADIUS := 3.5
const SELF_DAMAGE := 60.0

var main: Main
var fuse := FUSE
var done := false

func _ready() -> void:
    add_to_group("grenade")
    collision_layer = 1
    collision_mask = 1
    continuous_cd = true
    var pm := PhysicsMaterial.new()
    pm.bounce = 0.45
    pm.friction = 0.7
    physics_material_override = pm
    var cs := CollisionShape3D.new()
    var sh := SphereShape3D.new()
    sh.radius = 0.08
    cs.shape = sh
    add_child(cs)
    var sm := SphereMesh.new()
    sm.radius = 0.08
    sm.height = 0.16
    var m := StandardMaterial3D.new()
    m.albedo_color = Color(0.2, 0.3, 0.15)
    sm.material = m
    var mi := MeshInstance3D.new()
    mi.mesh = sm
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mi)

func launch(pos: Vector3, vel: Vector3) -> void:
    global_position = pos
    linear_velocity = vel
    angular_velocity = Vector3(randf() * 10.0, randf() * 10.0, randf() * 10.0)

func _physics_process(dt: float) -> void:
    if done:
        return
    fuse -= dt
    if fuse <= 0.0:
        done = true
        main.explode(global_position, RADIUS, DAMAGE, SELF_RADIUS, SELF_DAMAGE)
        queue_free()
