extends Node2D

const VW := 640.0
const VH := 360.0
const TILE := 16.0
const PLAY_RECT := Rect2(16, 16, 480, 240)
const UI_Y := 256.0
const ROOM_COLS := 30
const ROOM_ROWS := 15

var player := {
    "pos": Vector2(256, 180), "vel": Vector2.ZERO, "dir": Vector2.DOWN,
    "speed": 92.0, "hp": 8, "max_hp": 8, "invuln": 0.0,
    "attack_t": 0.0, "shield": false, "swim": false, "fall_t": 0.0,
    "item_a": "boomerang", "item_b": "bow", "arrows": 20, "bombs": 8,
    "magic": 12, "max_magic": 12, "keys": 0, "flippers": false,
    "has_lantern": true, "coins": 0
}

var room_id := "field_0"
var rooms := {}
var enemies: Array = []
var npcs: Array = []
var objects: Array = []
var projectiles: Array = []
var effects: Array = []
var room_cleared := {}
var flags := {}
var paused := false
var title_screen = true
var map_open = false
var visited = {}
var room_states = {}
var safe_pos = Vector2(256,180)
var save_clock = 0.0
var transition_t = 0.0
var hit_stop = 0.0
var item_cooldown = 0.0
var mute = false
var initial_player = {}
var save_path = "user://ccl_mobile_v1.save"
const WORLD_OFFSET = Vector2(64, 0)
const STICK = Vector2(86,306)
const SWORD = Vector2(554,310)
const SHIELD = Vector2(482,313)
const ITEM_A = Vector2(407,297)
const ITEM_B = Vector2(407,341)
var menu_cursor := 0
var menu_items := ["boomerang", "bow", "bomb", "fire", "ice", "lantern"]
var menu_assign_target := "a"
var message := "Explore the mechanics testbed"
var message_t := 3.0
var secret_flash := 0.0
var shake_t := 0.0
var shake_mag := 0.0
var elapsed := 0.0

# Touch state: true multi-touch by finger index.
var touch_points := {}
var move_touch := -1
var move_origin := Vector2.ZERO
var move_vec := Vector2.ZERO
var touch_attack := false
var touch_shield := false
var touch_item_a := false
var touch_item_b := false

var rng := RandomNumberGenerator.new()

# Original pixel-art and audio assets bundled with this build.
var hero_walk_tex: Texture2D
var hero_attack_tex: Texture2D
var enemy_tex: Texture2D
var cast_tex: Texture2D
var world_atlas_tex: Texture2D
var npc_textures: Array = []
var music_player: AudioStreamPlayer
var sfx_pool: Array = []
var sfx_index := 0
var current_music_path := ""
var step_timer := 0.0

func _ready() -> void:
    rng.seed = 246813579
    initial_player = player.duplicate(true)
    _load_assets()
    _setup_audio()
    _build_world()
    _load_room(room_id, Vector2(256, 180))
    queue_redraw()

func _load_assets() -> void:
    hero_walk_tex = load("res://assets/sprites/hero_walk_v2.png")
    hero_attack_tex = load("res://assets/sprites/hero_attack.png")
    cast_tex=load("res://assets/sprites/cast_v2.png")
    enemy_tex = load("res://assets/sprites/enemies.png")
    world_atlas_tex = load("res://assets/environment/world_atlas_v2.png")
    npc_textures.clear()
    for i in range(4):
        npc_textures.append(load("res://assets/sprites/npc_%d.png" % i))

func _setup_audio() -> void:
    music_player = AudioStreamPlayer.new()
    music_player.volume_db = -10.0
    add_child(music_player)
    music_player.finished.connect(_on_music_finished)
    for i in range(6):
        var p := AudioStreamPlayer.new()
        p.volume_db = -5.0
        add_child(p)
        sfx_pool.append(p)

func _on_music_finished() -> void:
    if current_music_path != "" and music_player.stream != null:
        music_player.play()

func _play_sfx(name: String, volume_db := -4.0) -> void:
    if sfx_pool.is_empty(): return
    var p = sfx_pool[sfx_index % sfx_pool.size()] as AudioStreamPlayer
    sfx_index += 1
    var path := "res://audio/sfx/%s.wav" % name
    var stream = load(path)
    if stream == null: return
    p.stream = stream
    p.volume_db = volume_db
    p.play()

func _music_for_room() -> String:
    var r: Dictionary = rooms[room_id]
    if int(r.boss) >= 0 and not room_cleared.get(room_id, false): return "boss"
    match str(r.theme):
        "field", "water": return "overworld"
        "castle": return "castle"
        "cave", "dark": return "cave"
        _: return "dungeon"

func _update_music() -> void:
    var name := _music_for_room()
    var path := "res://audio/music/%s.wav" % name
    if path == current_music_path and music_player.playing: return
    current_music_path = path
    var stream = load(path)
    if stream != null:
        music_player.stream = stream
        music_player.play()

func _build_world() -> void:
    # 8 overworld/castle/cave/water rooms + a 27-room dungeon with 9 boss chambers.
    rooms["field_0"] = _room("Verdant Crossroads", "field", ["castle_0", "field_1", "cave_0", "water_0"], 0)
    rooms["field_1"] = _room("Windcut Meadow", "field", ["field_0", "field_2", "", ""], 1)
    rooms["field_2"] = _room("Old Stone Approach", "field", ["field_1", "dungeon_0", "", ""], 2)
    rooms["castle_0"] = _room("Amberkeep Hall", "castle", ["castle_1", "field_0", "", ""], 3)
    rooms["castle_1"] = _room("Amberkeep Gallery", "castle", ["", "castle_0", "", ""], 4)
    rooms["cave_0"] = _room("Gloam Cave", "cave", ["", "", "cave_1", "field_0"], 5)
    rooms["cave_1"] = _room("Torch Grotto", "dark", ["", "", "", "cave_0"], 6)
    rooms["water_0"] = _room("Mosswater Shore", "water", ["", "", "field_0", "water_1"], 7)
    rooms["water_1"] = _room("Sunken Steps", "water", ["", "", "water_0", ""], 8)
    for i in range(27):
        var exits = ["", "", "", ""]
        if i > 0: exits[0] = "dungeon_%d" % (i - 1)
        if i < 26: exits[1] = "dungeon_%d" % (i + 1)
        if i == 0: exits[0] = "field_2"
        var boss_index = -1
        if i in [2,5,8,11,14,17,20,23,26]: boss_index = int((i - 2) / 3)
        rooms["dungeon_%d" % i] = _room("Labyrinth Depth %02d" % (i + 1), "dungeon", exits, 20 + i, boss_index)

func _room(title: String, theme: String, exits: Array, seed_value: int, boss_index = -1) -> Dictionary:
    return {"title": title, "theme": theme, "exits": exits, "seed": seed_value, "boss": boss_index}

func _load_room(id: String, spawn: Vector2) -> void:
    room_id = id
    visited[id] = true
    safe_pos = spawn
    transition_t = 0.22
    player.pos = spawn
    player.vel = Vector2.ZERO
    enemies.clear(); npcs.clear(); objects.clear(); projectiles.clear(); effects.clear()
    var r: Dictionary = rooms[id]
    var local_rng := RandomNumberGenerator.new(); local_rng.seed = 9001 + int(r.seed) * 97
    _generate_room_objects(r, local_rng)
    _prepare_layout(r)
    if room_states.has(id): objects = room_states[id].duplicate(true)
    _spawn_npcs(r, local_rng)
    if int(r.boss) >= 0 and not room_cleared.get(id, false):
        _spawn_boss(int(r.boss))
    elif not room_cleared.get(id, false):
        _spawn_room_enemies(r, local_rng)
    message = str(r.title)
    message_t = 2.0
    _update_music()
    queue_redraw()

func _generate_room_objects(r: Dictionary, rr: RandomNumberGenerator) -> void:
    var theme := str(r.theme)
    # Borders and interior obstacles.
    for x in range(1, 30):
        if x not in [15,16]:
            objects.append(_obj("wall", Vector2(x * TILE, 16), Vector2(16,16), true))
            objects.append(_obj("wall", Vector2(x * TILE, 240), Vector2(16,16), true))
    for y in range(2, 15):
        if y not in [7,8]:
            objects.append(_obj("wall", Vector2(16, y * TILE), Vector2(16,16), true))
            objects.append(_obj("wall", Vector2(480, y * TILE), Vector2(16,16), true))
    # Four door gaps are represented by transition zones, so remove wall tiles around their center visually via doors.
    objects.append(_obj("door_n", Vector2(248,16), Vector2(32,16), false))
    objects.append(_obj("door_s", Vector2(248,240), Vector2(32,16), false))
    objects.append(_obj("door_w", Vector2(16,120), Vector2(16,32), false))
    objects.append(_obj("door_e", Vector2(480,120), Vector2(16,32), false))
    if theme in ["field", "water"]:
        for i in range(16):
            objects.append(_obj("grass", Vector2(rr.randi_range(48,448), rr.randi_range(48,216)), Vector2(12,12), false))
        for i in range(6):
            objects.append(_obj("rock", Vector2(rr.randi_range(64,432), rr.randi_range(56,208)), Vector2(16,16), true))
        for i in range(5):
            objects.append(_obj("tree", Vector2(rr.randi_range(48,464), rr.randi_range(48,220)), Vector2(18,18), true))
        for i in range(6):
            objects.append(_obj("bush", Vector2(rr.randi_range(48,464), rr.randi_range(48,220)), Vector2(12,12), false))
        if room_id == "field_0":
            objects.append(_obj("house", Vector2(128,76), Vector2(38,28), true))
            objects.append(_obj("shop", Vector2(382,76), Vector2(38,28), true))
            objects.append(_obj("house", Vector2(128,190), Vector2(38,28), true))
    if theme in ["castle", "dungeon", "cave", "dark"]:
        for i in range(6):
            objects.append(_obj("pot", Vector2(rr.randi_range(56,440), rr.randi_range(56,208)), Vector2(12,12), true))
        objects.append(_obj("switch", Vector2(248,136), Vector2(16,16), false))
        objects.append(_obj("chest", Vector2(400,64), Vector2(18,14), true, {"opened": false}))
    if theme == "dark":
        objects.append(_obj("torch", Vector2(96,64), Vector2(8,16), false, {"lit": false}))
        objects.append(_obj("torch", Vector2(416,64), Vector2(8,16), false, {"lit": false}))
    if theme == "water":
        objects.append(_obj("water", Vector2(144,64), Vector2(224,144), false, {"deep": true}))
        objects.append(_obj("shallow", Vector2(112,48), Vector2(288,176), false))
        if room_id == "water_1" and not flags.get("flippers", false):
            objects.append(_obj("upgrade", Vector2(416,192), Vector2(14,14), false, {"upgrade_kind": "flippers"}))
    if str(r.theme) == "dungeon":
        var s := int(r.seed)
        if s % 3 == 0:
            for k in range(4): objects.append(_obj("block", Vector2(176+k*32,128), Vector2(16,16), true, {"pushable": true}))
        if s % 4 == 0:
            objects.append(_obj("pit", Vector2(192,80), Vector2(128,64), false))
        if s % 5 == 0:
            objects.append(_obj("ice_floor", Vector2(128,64), Vector2(256,144), false))
        if s % 6 == 0:
            objects.append(_obj("cracked", Vector2(384,128), Vector2(16,32), true, {"hp": 1}))
        if s % 7 == 0:
            objects.append(_obj("torch", Vector2(112,72), Vector2(8,16), false, {"lit": false}))
            objects.append(_obj("torch", Vector2(400,72), Vector2(8,16), false, {"lit": false}))

func _obj(kind: String, pos: Vector2, size: Vector2, solid: bool, extra = {}) -> Dictionary:
    var d = {"kind":kind, "rect":Rect2(pos-size*0.5,size), "solid":solid, "dead":false, "state":0}
    for k in extra: d[k] = extra[k]
    return d

func _spawn_npcs(r: Dictionary, rr: RandomNumberGenerator) -> void:
    var theme := str(r.theme)
    var count := 0
    if room_id == "field_0": count = 6
    elif theme == "castle": count = 3
    elif theme == "field": count = 2
    for i in range(count):
        var pos := Vector2(rr.randi_range(70, 440), rr.randi_range(58, 214))
        npcs.append({"pos":pos, "vel":Vector2.ZERO, "dir":Vector2.DOWN, "variant":i % 4, "t":rr.randf_range(0.0, 4.0), "move_t":rr.randf_range(0.3, 1.8)})

func _update_npcs(delta: float) -> void:
    for n in npcs:
        n.t += delta
        n.move_t -= delta
        if n.move_t <= 0.0:
            n.move_t = rng.randf_range(0.8, 2.4)
            if rng.randf() < 0.25:
                n.vel = Vector2.ZERO
            else:
                var dirs = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
                n.dir = dirs[rng.randi_range(0, 3)]
                n.vel = n.dir * 18.0
        var old: Vector2 = n.pos
        n.pos += n.vel * delta
        n.pos.x = clamp(n.pos.x, 38.0, 474.0)
        n.pos.y = clamp(n.pos.y, 38.0, 226.0)
        var nr := Rect2(n.pos - Vector2(5,5), Vector2(10,10))
        for o in objects:
            if o.dead or not o.solid: continue
            if nr.intersects(o.rect):
                n.pos = old
                n.vel = Vector2.ZERO
                n.move_t = 0.2
                break

func _spawn_room_enemies(r: Dictionary, rr: RandomNumberGenerator) -> void:
    if room_id == "field_0": return
    var count := 3 + int(r.seed) % 3
    var kinds = ["chaser","archer","bat","burrow","bouncer","patrol","elemental"]
    for i in range(count):
        var kind = kinds[(i + int(r.seed)) % kinds.size()]
        var spawn=Vector2(rr.randi_range(72,440), rr.randi_range(56,208))
        for attempt in range(30):
            if not _rect_hits_solid(Rect2(spawn-Vector2(7,7),Vector2(14,14)),{}): break
            spawn=Vector2(rr.randi_range(72,440), rr.randi_range(56,208))
        enemies.append(_enemy(kind,spawn))

func _enemy(kind: String, pos: Vector2) -> Dictionary:
    var hp = 2
    if kind == "elemental": hp = 3
    return {"kind":kind,"pos":pos,"vel":Vector2.ZERO,"hp":hp,"max_hp":hp,"t":rng.randf_range(0,2),"hurt":0.0,"dead":false,"state":0,"burn":0.0,"freeze":0.0,"radius":7.0}

func _spawn_boss(idx: int) -> void:
    var names = ["Miremaw","Glasscoil","Ramhorn Warden","Cinder Oracle","Twinshade Archers","Floodheart","Thorn Engine","Prism Regent","Ninefold Colossus"]
    var hp = 10 + idx * 3
    enemies.append({"kind":"boss","boss":idx,"name":names[idx],"pos":Vector2(256,112),"vel":Vector2.ZERO,"hp":hp,"max_hp":hp,"t":0.0,"hurt":0.0,"dead":false,"state":0,"phase":0,"burn":0.0,"freeze":0.0,"radius":18.0})
    message = "BOSS — %s" % names[idx]; message_t = 3.0

func _physics_process(delta: float) -> void:
    elapsed += delta
    if message_t > 0: message_t -= delta
    if secret_flash > 0: secret_flash -= delta
    if shake_t > 0: shake_t -= delta
    if paused or title_screen or map_open:
        queue_redraw(); return
    if hit_stop > 0:
        hit_stop -= delta
        queue_redraw(); return
    transition_t = maxf(0, transition_t-delta)
    item_cooldown = maxf(0,item_cooldown-delta)
    save_clock += delta
    if fmod(elapsed,3.0)<delta and player.magic<player.max_magic: player.magic+=1
    if save_clock > 15:
        _save_game(); save_clock = 0
    _update_player(delta)
    _update_npcs(delta)
    _update_enemies(delta)
    _update_projectiles(delta)
    _update_effects(delta)
    _cleanup_and_drops()
    _check_room_clear()
    _update_puzzle()
    _collect_drops()
    queue_redraw()

func _update_player(delta: float) -> void:
    if player.invuln > 0: player.invuln -= delta
    if player.attack_t > 0: player.attack_t -= delta
    if player.fall_t > 0:
        player.fall_t -= delta
        if player.fall_t <= 0:
            player.pos = safe_pos; _hurt_player(1, Vector2.ZERO)
        return
    var input_vec = Input.get_vector("move_left","move_right","move_up","move_down")
    if move_vec.length() > 0.1: input_vec = move_vec
    if input_vec.length() > 0.1:
        player.dir = Vector2(signf(input_vec.x),0) if abs(input_vec.x)>abs(input_vec.y) else Vector2(0,signf(input_vec.y))
        step_timer -= delta
        if step_timer <= 0.0:
            _play_sfx("swim" if _in_water(player.pos) else "step", -13.0)
            step_timer = 0.30 if _in_water(player.pos) else 0.24
    else:
        step_timer = 0.0
    var speed = float(player.speed)
    if _in_water(player.pos): speed *= 0.58 if player.flippers else 0.0
    if player.shield: speed *= 0.62
    if _on_ice(player.pos):
        player.vel = player.vel.lerp(input_vec.normalized()*speed, delta*1.8)
    else:
        player.vel = input_vec.normalized()*speed
    var old = player.pos
    player.pos += player.vel * delta
    _resolve_player_solids(old)
    if _in_water(player.pos) and not player.flippers: player.pos = old
    _world_bounds_and_transitions()
    _environment_player_checks()
    if not _in_water(player.pos) and player.fall_t <= 0: safe_pos = player.pos
    if Input.is_action_just_pressed("interact"): _interact()

    var attack_pressed = Input.is_action_just_pressed("attack") or touch_attack
    var shield_now = Input.is_action_pressed("shield") or touch_shield
    player.shield = shield_now
    if attack_pressed and player.attack_t <= 0 and not _in_water(player.pos):
        player.attack_t = 0.24; _sword_hit()
    if Input.is_action_just_pressed("item_a") or touch_item_a: _use_item(str(player.item_a))
    if Input.is_action_just_pressed("item_b") or touch_item_b: _use_item(str(player.item_b))
    touch_attack = false; touch_item_a = false; touch_item_b = false

func _resolve_player_solids(old: Vector2) -> void:
    var pr = Rect2(player.pos-Vector2(6,6), Vector2(12,12))
    for o in objects:
        if o.dead or not o.solid: continue
        if pr.intersects(o.rect):
            if o.kind == "block" and o.get("pushable", false):
                var push = player.dir.round() * 16.0
                var new_rect: Rect2 = o.rect; new_rect.position += push
                if not _rect_hits_solid(new_rect, o): o.rect = new_rect
                else: player.pos = old
            else:
                player.pos = old
            break

func _rect_hits_solid(r: Rect2, ignore: Dictionary) -> bool:
    if not PLAY_RECT.encloses(r): return true
    for o in objects:
        if o == ignore or o.dead or not o.solid: continue
        if r.intersects(o.rect): return true
    return false

func _world_bounds_and_transitions() -> void:
    var r: Dictionary = rooms[room_id]
    if player.pos.x < 24:
        _transition(str(r.exits[0]), Vector2(468,128))
    elif player.pos.x > 488:
        _transition(str(r.exits[1]), Vector2(44,128))
    elif player.pos.y < 24:
        _transition(str(r.exits[2]), Vector2(256,224))
    elif player.pos.y > 242:
        _transition(str(r.exits[3]), Vector2(256,40))
    player.pos.x = clamp(player.pos.x, 20.0, 492.0)
    player.pos.y = clamp(player.pos.y, 20.0, 244.0)

func _transition(target: String, spawn: Vector2) -> void:
    if target == "" or transition_t > 0: return
    if target == str(rooms[room_id].exits[1]) and room_id.begins_with("dungeon_"):
        if not _gate_open():
            player.pos.x = 475
            message = _gate_hint(); message_t = 2
            return
    room_states[room_id] = objects.duplicate(true)
    _play_sfx("door", -8.0)
    _load_room(target, spawn)
    _save_game()

func _environment_player_checks() -> void:
    for o in objects:
        if o.dead: continue
        if o.kind == "pit" and o.rect.has_point(player.pos):
            player.fall_t = 0.55; player.vel = Vector2.ZERO
        elif o.kind == "upgrade" and o.rect.grow(6).has_point(player.pos):
            if o.kind == "upgrade" and o.get("upgrade_kind", "") == "flippers":
                player.flippers = true; flags["flippers"] = true; o.dead = true
                _play_sfx("pickup"); _announce_secret("Swim Fins acquired — deep water unlocked!")
        elif o.kind == "chest" and not o.opened and o.rect.grow(12).has_point(player.pos):
            o.opened = true; player.keys += 1; player.bombs += 2; player.arrows += 5
            _play_sfx("chest"); _announce_secret("Chest opened: key, bombs, arrows")

func _sword_hit() -> void:
    _play_sfx("sword_swing")
    var center = player.pos + player.dir * 15.0
    var hit = Rect2(center-Vector2(10,10),Vector2(20,20))
    for e in enemies:
        if e.dead: continue
        var to_enemy: Vector2=e.pos-player.pos
        if to_enemy.length()<29+float(e.radius)*0.4 and player.dir.dot(to_enemy.normalized())>0.15: _damage_enemy(e, 1, "sword")
    for o in objects:
        if o.dead: continue
        if hit.intersects(o.rect):
            if o.kind == "grass":
                o.dead = true; _maybe_drop(o.rect.get_center())
            elif o.kind == "bush":
                o.dead=true; _maybe_drop(o.rect.get_center())
            elif o.kind == "pot":
                o.dead = true; _maybe_drop(o.rect.get_center())
            elif o.kind == "switch":
                o.state = 1 - int(o.state); _play_sfx("switch"); _announce_secret("Floor switch toggled")
            elif o.kind == "cracked":
                message = "This wall needs an explosion"; message_t = 1.2

func _use_item(kind: String) -> void:
    if item_cooldown > 0: return
    item_cooldown = 0.25
    match kind:
        "bow":
            if player.arrows <= 0: return
            _play_sfx("bow")
            player.arrows -= 1; _spawn_projectile("arrow", player.pos + player.dir*10, player.dir*180, 1, "player")
        "boomerang":
            _play_sfx("boomerang")
            _spawn_projectile("boomerang", player.pos + player.dir*10, player.dir*145, 0, "player", 0.7)
        "bomb":
            if player.bombs <= 0: return
            _play_sfx("bomb", -7.0)
            player.bombs -= 1; effects.append({"kind":"bomb","pos":player.pos+player.dir*14,"t":1.2,"done":false})
        "fire":
            if player.magic <= 0: return
            _play_sfx("fire")
            player.magic -= 1; _spawn_projectile("fire", player.pos+player.dir*10, player.dir*125, 2, "player", 0.8)
        "ice":
            if player.magic <= 0: return
            _play_sfx("ice")
            player.magic -= 1; _spawn_projectile("ice", player.pos+player.dir*10, player.dir*125, 1, "player", 0.9)
        "lantern":
            _play_sfx("lantern")
            _lantern_pulse()

func _spawn_projectile(kind: String, pos: Vector2, vel: Vector2, dmg: int, owner: String, life = 1.4) -> void:
    projectiles.append({"kind":kind,"pos":pos,"vel":vel,"dmg":dmg,"owner":owner,"life":life,"dead":false,"origin":pos})

func _lantern_pulse() -> void:
    for o in objects:
        if o.dead: continue
        if o.kind == "torch" and o.rect.get_center().distance_to(player.pos) < 42:
            o.lit = true; _play_sfx("lantern"); _announce_secret("Torch lit")
        if o.kind == "grass" and o.rect.get_center().distance_to(player.pos) < 28:
            o.dead = true; effects.append({"kind":"ember","pos":o.rect.get_center(),"t":0.5})

func _update_enemies(delta: float) -> void:
    for e in enemies:
        if e.dead: continue
        e.t += delta
        if e.hurt > 0: e.hurt -= delta
        if e.burn > 0:
            e.burn -= delta
            if fmod(e.burn,0.5) < delta: _damage_enemy(e,1,"burn")
        if e.freeze > 0:
            e.freeze -= delta; continue
        if e.kind == "boss": _update_boss(e,delta); continue
        var to_p: Vector2 = player.pos - e.pos
        match e.kind:
            "chaser": e.vel = to_p.normalized()*44
            "archer":
                e.vel = -to_p.normalized()*22 if to_p.length()<95 else Vector2.ZERO
                if fmod(e.t,1.7) < delta: _spawn_projectile("enemy_orb",e.pos,to_p.normalized()*85,1,"enemy")
            "bat": e.vel = (to_p.normalized()*46 + Vector2(sin(e.t*5),cos(e.t*4))*24)
            "burrow":
                e.state = int(e.t*1.2)%3
                e.vel = to_p.normalized()*65 if e.state == 2 else Vector2.ZERO
            "bouncer":
                if e.vel.length()<1: e.vel=Vector2(1,1).rotated(rng.randf()*TAU)*55
                if e.pos.x<40 or e.pos.x>472: e.vel.x*=-1
                if e.pos.y<40 or e.pos.y>224: e.vel.y*=-1
            "patrol": e.vel = Vector2(cos(e.t*1.7),sin(e.t*1.1))*36
            "elemental":
                e.vel = to_p.normalized()*30
                if fmod(e.t,2.1)<delta: _spawn_projectile("enemy_orb",e.pos,to_p.normalized()*75,1,"enemy")
        var old_pos: Vector2=e.pos
        e.pos += e.vel*delta
        if e.kind!="bat":
            for o in objects:
                if not o.dead and o.solid and o.rect.grow(5).has_point(e.pos):
                    e.pos=old_pos; e.vel=-e.vel; break
        e.pos.x=clamp(e.pos.x,32.0,480.0); e.pos.y=clamp(e.pos.y,32.0,232.0)
        _enemy_contact(e)

func _update_boss(e: Dictionary, delta: float) -> void:
    var i := int(e.boss)
    var to_p: Vector2 = player.pos - e.pos
    e.phase = 1 if e.hp < e.max_hp/2 else 0
    match i:
        0: # Burrowing emerging boss
            e.state = int(e.t*1.1)%4
            if e.state == 3: e.vel = to_p.normalized()*90
            else: e.vel = Vector2.ZERO
        1: # Segmented/worm-style orbit and rush
            e.vel = Vector2(cos(e.t*2.4),sin(e.t*1.8))*58 + to_p.normalized()*18
        2: # Fast charger, vulnerable after wall-like recovery window
            var cycle=fmod(e.t,2.4)
            if cycle<0.45: e.vel=to_p.normalized()*160
            elif cycle<1.0: e.vel*=0.92
            else: e.vel=Vector2.ZERO
        3: # Projectile-heavy oracle
            e.vel=Vector2(cos(e.t),sin(e.t*1.3))*22
            if fmod(e.t,0.55 if e.phase else 0.85)<delta:
                for a in range(8): _spawn_projectile("enemy_orb",e.pos,Vector2.RIGHT.rotated(a*TAU/8+e.t)*72,1,"enemy")
        4: # Ranged fight
            e.vel=-to_p.normalized()*38 if to_p.length()<120 else to_p.normalized()*16
            if fmod(e.t,0.7)<delta: _spawn_projectile("enemy_orb",e.pos,to_p.normalized()*120,1,"enemy")
        5: # Environmental water puzzle boss; ice does bonus
            e.vel=Vector2(cos(e.t*1.4),sin(e.t*1.7))*48
            if fmod(e.t,1.4)<delta:
                for a in range(4): _spawn_projectile("enemy_orb",e.pos,Vector2.RIGHT.rotated(a*PI/2)*95,1,"enemy")
        6: # Thorn engine: shield helps vs rings; fire weakness
            e.vel=Vector2(cos(e.t*2),sin(e.t*2))*34
            if fmod(e.t,1.2)<delta:
                for a in range(12): _spawn_projectile("enemy_orb",e.pos,Vector2.RIGHT.rotated(a*TAU/12)*88,1,"enemy")
        7: # Prism phases elemental weakness swaps
            e.vel=to_p.normalized()*42
            e.state=int(e.t/2.0)%2
            if fmod(e.t,0.5)<delta: _spawn_projectile("enemy_orb",e.pos,Vector2.RIGHT.rotated(rng.randf()*TAU)*110,1,"enemy")
        8: # Final combined encounter
            var mode=int(e.t/3.0)%4
            if mode==0: e.vel=to_p.normalized()*120
            elif mode==1:
                e.vel=Vector2.ZERO
                if fmod(e.t,0.45)<delta:
                    for a in range(6): _spawn_projectile("enemy_orb",e.pos,Vector2.RIGHT.rotated(a*TAU/6+e.t)*100,1,"enemy")
            elif mode==2: e.vel=Vector2(cos(e.t*2),sin(e.t*1.6))*70
            else: e.vel=to_p.normalized()*45
    e.pos += e.vel*delta
    if e.pos.x<42 or e.pos.x>470: e.vel.x*=-1
    if e.pos.y<42 or e.pos.y>220: e.vel.y*=-1
    e.pos.x=clamp(e.pos.x,36.0,476.0); e.pos.y=clamp(e.pos.y,36.0,228.0)
    _enemy_contact(e)

func _enemy_contact(e: Dictionary) -> void:
    if e.pos.distance_to(player.pos) < e.radius + 7:
        if player.shield and player.dir.dot((e.pos-player.pos).normalized()) > 0.25:
            e.vel = (e.pos-player.pos).normalized()*70
            _play_sfx("shield_block", -5.0)
        else: _hurt_player(1,(player.pos-e.pos).normalized())

func _damage_enemy(e: Dictionary, amount: int, source: String) -> void:
    if e.hurt > 0 or e.dead: return
    var dmg=amount
    if e.kind=="elemental" and source=="ice": dmg+=2
    if e.kind=="boss":
        var i=int(e.boss)
        if i==5 and source=="ice": dmg+=2
        if i==6 and source=="fire": dmg+=2
        if i==7:
            if int(e.state)==0 and source!="ice": dmg=0
            if int(e.state)==1 and source!="fire": dmg=0
        if i==2 and fmod(e.t,2.4)<1.0: dmg=0
    if dmg<=0: return
    hit_stop = 0.035
    e.hp -= dmg; e.hurt=0.16; shake_t=0.08; shake_mag=2.0
    _play_sfx("enemy_hit", -7.0)
    if source=="fire": e.burn=1.2
    if source=="ice": e.freeze=1.4
    if e.hp<=0:
        e.dead=true
        _play_sfx("boss_die" if e.kind=="boss" else "enemy_die", -5.0)
        effects.append({"kind":"burst","pos":e.pos,"t":0.65})
        if e.kind=="boss":
            room_cleared[room_id]=true; player.max_hp+=1; player.hp=player.max_hp
            player.magic=player.max_magic
            player.arrows=maxi(player.arrows,15); player.bombs=maxi(player.bombs,4)
            _play_sfx("victory", -8.0); _announce_secret("Boss defeated! Health and supplies restored.")
            if int(e.boss)==8:
                flags["victory"]=true
                message="THE NINEFOLD VAULT IS FREE. Return to the village!"; message_t=8
            _update_music()

func _hurt_player(amount: int, knock: Vector2) -> void:
    if player.invuln>0: return
    player.hp -= amount; player.invuln=0.85; player.pos += knock*12
    _play_sfx("hurt", -4.0)
    shake_t=0.16; shake_mag=4
    if player.hp<=0:
        player.hp=player.max_hp; player.magic=player.max_magic
        room_states[room_id]=objects.duplicate(true)
        _load_room("field_0",Vector2(256,180)); message="You awaken at the crossroads"; message_t=2.5

func _update_projectiles(delta: float) -> void:
    for p in projectiles:
        if p.dead: continue
        p.life-=delta; p.pos+=p.vel*delta
        if p.kind=="boomerang" and p.life<0.35:
            p.vel=(player.pos-p.pos).normalized()*180
        if p.life<=0 or not PLAY_RECT.grow(8).has_point(p.pos): p.dead=true; continue
        if p.owner=="player":
            for e in enemies:
                if e.dead: continue
                if p.pos.distance_to(e.pos)<e.radius+4:
                    if p.kind=="boomerang": e.freeze=1.2
                    _damage_enemy(e,int(p.dmg),str(p.kind));
                    if p.kind!="boomerang": p.dead=true
            for o in objects:
                if o.dead: continue
                if o.rect.grow(3).has_point(p.pos):
                    if p.kind=="fire": _fire_interact(o)
                    elif p.kind=="ice": _ice_interact(o)
                    elif o.solid and p.kind!="boomerang": p.dead=true
        else:
            if p.pos.distance_to(player.pos)<8:
                if player.shield and player.dir.dot((p.pos-player.pos).normalized())>0.15:
                    p.dead=true; effects.append({"kind":"spark","pos":p.pos,"t":0.25})
                else: _hurt_player(int(p.dmg),(player.pos-p.pos).normalized()); p.dead=true

func _fire_interact(o: Dictionary) -> void:
    if o.kind=="grass": o.dead=true; effects.append({"kind":"ember","pos":o.rect.get_center(),"t":0.6})
    elif o.kind=="torch": o.lit=true; _announce_secret("A torch catches flame")

func _ice_interact(o: Dictionary) -> void:
    if o.kind=="water":
        effects.append({"kind":"ice_patch","pos":o.rect.get_center(),"rect":Rect2(o.rect.get_center()-Vector2(28,18),Vector2(56,36)),"t":6.0})
        _announce_secret("Water temporarily freezes into a crossing")

func _update_effects(delta: float) -> void:
    for fx in effects:
        fx.t-=delta
        if fx.kind=="bomb" and fx.t<=0 and not fx.get("done",false):
            fx.done=true; fx.t=0.35; shake_t=0.3; shake_mag=5
            for e in enemies:
                if not e.dead and e.pos.distance_to(fx.pos)<52: _damage_enemy(e,3,"bomb")
            for o in objects:
                if not o.dead and o.rect.get_center().distance_to(fx.pos)<50:
                    if o.kind in ["grass","pot","cracked"]:
                        o.dead=true
                        if o.kind=="cracked": _announce_secret("A hidden passage is revealed!")

func _cleanup_and_drops() -> void:
    enemies = enemies.filter(func(e): return not e.dead)
    projectiles = projectiles.filter(func(p): return not p.dead)
    effects = effects.filter(func(fx): return fx.t>0)
    # Retain dead props for persistent room state.

func _check_room_clear() -> void:
    if enemies.size()==0 and not room_cleared.get(room_id,false):
        room_cleared[room_id]=true
        if str(rooms[room_id].theme)=="dungeon": player.keys+=1

func _maybe_drop(pos: Vector2) -> void:
    if rng.randf()<0.45:
        var kind=["heart","arrow","bomb","magic","coin"][rng.randi_range(0,4)]
        effects.append({"kind":"drop","drop":kind,"pos":pos,"t":8.0})

func _collect_drops() -> void:
    for fx in effects:
        if fx.kind=="drop" and fx.pos.distance_to(player.pos)<12:
            match fx.drop:
                "heart": player.hp=min(player.max_hp,player.hp+2)
                "arrow": player.arrows+=3
                "bomb": player.bombs+=1
                "magic": player.magic=min(player.max_magic,player.magic+3)
                "coin": player.coins+=1
            _play_sfx("pickup", -9.0)
            fx.t=0

func _in_water(pos: Vector2) -> bool:
    for o in objects:
        if not o.dead and o.kind=="water" and o.rect.has_point(pos):
            # Ice patches override water locally.
            for fx in effects:
                if fx.kind=="ice_patch" and fx.rect.has_point(pos): return false
            return true
    return false

func _on_ice(pos: Vector2) -> bool:
    for o in objects:
        if o.kind=="ice_floor" and o.rect.has_point(pos): return true
    for fx in effects:
        if fx.kind=="ice_patch" and fx.rect.has_point(pos): return true
    return false

func _announce_secret(text: String) -> void:
    message=text; message_t=2.3; secret_flash=0.35
    _play_sfx("secret", -9.0)

func _process(_delta: float) -> void:
    if Input.is_action_just_pressed("pause_menu"):
        if title_screen: _start_game(FileAccess.file_exists(save_path))
        elif map_open: map_open=false
        else: _toggle_pause()
    if title_screen and Input.is_action_just_pressed("attack"): _start_game(false)
    if paused:
        if Input.is_action_just_pressed("move_left"): menu_cursor=(menu_cursor+5)%6
        if Input.is_action_just_pressed("move_right"): menu_cursor=(menu_cursor+1)%6
        if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("move_down"): menu_cursor=(menu_cursor+3)%6
        if Input.is_action_just_pressed("item_a"): player.item_a=menu_items[menu_cursor]
        if Input.is_action_just_pressed("item_b"): player.item_b=menu_items[menu_cursor]
        if Input.is_action_just_pressed("attack"):
            player["item_"+menu_assign_target]=menu_items[menu_cursor]
            menu_assign_target="b" if menu_assign_target=="a" else "a"
    queue_redraw()

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        var p = event.position
        if event.pressed:
            touch_points[event.index]=p
            if not paused and not title_screen and not map_open and p.distance_to(STICK)<65 and move_touch==-1:
                move_touch=event.index; move_origin=STICK
                move_vec=((p-STICK)/38.0).limit_length()
            else: _touch_button_press(p)
        else:
            touch_points.erase(event.index)
            if event.index==move_touch: move_touch=-1; move_vec=Vector2.ZERO
            _refresh_hold_buttons()
    elif event is InputEventScreenDrag:
        var p=event.position
        touch_points[event.index]=p
        if event.index==move_touch: move_vec=((p-STICK)/38.0).limit_length()
        _refresh_hold_buttons()
    elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
        if event.pressed:
            if event.position.distance_to(STICK)<65 and not title_screen and not paused:
                move_touch=-2; move_vec=((event.position-STICK)/38.0).limit_length()
            else: _touch_button_press(event.position)
        else: move_touch=-1; move_vec=Vector2.ZERO; touch_shield=false
    elif event is InputEventMouseMotion and move_touch==-2:
        move_vec=((event.position-STICK)/38.0).limit_length()

func _screen_to_virtual(p: Vector2) -> Vector2:
    # Godot already delivers canvas_items input in viewport coordinates.
    return p

func _touch_button_press(p: Vector2) -> void:
    if title_screen:
        if Rect2(182,188,276,42).has_point(p): _start_game(false)
        elif Rect2(182,240,276,36).has_point(p) and FileAccess.file_exists(save_path): _start_game(true)
        return
    if map_open:
        map_open=false; _reset_touch(); return
    if paused:
        for i in range(6):
            if _item_rect(i).has_point(p):
                menu_cursor=i; _play_sfx("menu",-12); return
        if Rect2(90,238,210,36).has_point(p): player.item_a=menu_items[menu_cursor]
        elif Rect2(340,238,210,36).has_point(p): player.item_b=menu_items[menu_cursor]
        elif Rect2(90,290,140,34).has_point(p): _toggle_pause()
        elif Rect2(250,290,140,34).has_point(p): _save_game(); paused=false; map_open=true; _reset_touch()
        elif Rect2(410,290,140,34).has_point(p):
            mute=not mute; AudioServer.set_bus_mute(0,mute)
        return
    if p.distance_to(SWORD)<32: touch_attack=true
    elif p.distance_to(SHIELD)<28: touch_shield=true
    elif p.distance_to(ITEM_A)<23: touch_item_a=true
    elif p.distance_to(ITEM_B)<20: touch_item_b=true
    elif Rect2(584,7,50,30).has_point(p): _toggle_pause()
    elif Rect2(584,44,50,30).has_point(p): map_open=true; _reset_touch()
    elif Rect2(584,217,50,34).has_point(p): _interact()

func _refresh_hold_buttons() -> void:
    touch_shield=false
    if paused or title_screen or map_open: return
    for p in touch_points.values():
        if p.distance_to(SHIELD)<28: touch_shield=true

func _draw() -> void:
    draw_rect(Rect2(0,0,VW,VH),Color("111c28"))
    var off=Vector2.ZERO
    if shake_t>0: off=Vector2(rng.randf_range(-shake_mag,shake_mag),rng.randf_range(-shake_mag,shake_mag))
    draw_set_transform(WORLD_OFFSET+off)
    _draw_room()
    _draw_objects(true)
    _draw_effects()
    # Sort tall scenery, NPCs, enemies and hero by their ground contact.
    var renderables=[]
    for o in objects:
        if not o.dead and o.kind in ["tree","bush","rock","house","shop","pot","chest","torch","block","cracked"]:
            renderables.append({"y":o.rect.get_center().y,"type":"prop","data":o})
    for n in npcs: renderables.append({"y":n.pos.y,"type":"npc","data":n})
    for e in enemies: renderables.append({"y":e.pos.y,"type":"enemy","data":e})
    renderables.append({"y":player.pos.y,"type":"hero"})
    renderables.sort_custom(func(a,b): return a.y<b.y)
    for entry in renderables:
        match entry.type:
            "prop": _draw_objects(false,entry.data)
            "npc": _draw_npc(entry.data)
            "enemy": _draw_enemy(entry.data)
            "hero": _draw_player()
    _draw_projectiles()
    _draw_gate()
    if transition_t>0: draw_rect(Rect2(0,0,512,256),Color(0.04,0.07,0.1,transition_t*2))
    draw_set_transform(Vector2.ZERO)
    _draw_hud()
    _draw_touch_controls()
    if message_t>0 and not paused and not title_screen and not map_open: _draw_message()
    if paused: _draw_inventory()
    if map_open: _draw_map()
    if title_screen: _draw_title()

func _theme_colors() -> Array:
    var t=str(rooms[room_id].theme)
    match t:
        "field": return [Color("#547a45"),Color("#6f9852"),Color("#314c2d")]
        "castle": return [Color("#7e6b55"),Color("#a28b6a"),Color("#493d35")]
        "cave","dark": return [Color("#3d3943"),Color("#55495a"),Color("#25232b")]
        "water": return [Color("#3f7180"),Color("#5f9d9f"),Color("#294c58")]
        _: return [Color("#463f57"),Color("#675978"),Color("#292536")]

func _draw_room() -> void:
    var outdoor=str(rooms[room_id].theme) in ["field","water"]
    var c=_theme_colors()
    draw_rect(Rect2(0,0,512,256),Color("284536") if outdoor else c[2])
    for y in range(16):
        for x in range(32):
            var h=posmod(x*73+y*197+int(rooms[room_id].seed)*13,17)
            var r=Rect2(x*16,y*16,16,16)
            if outdoor:
                draw_rect(r,Color("42664c") if h<8 else Color("466d50"))
                draw_line(r.position+Vector2(3+h%6,9),r.position+Vector2(4+h%6,6),Color("59815a"),1)
                if h==2: draw_rect(Rect2(r.position+Vector2(10,3),Vector2(2,2)),Color("c7b976"))
            else:
                draw_rect(r.grow(-0.5),c[0].lightened(float(h)*0.006))
                draw_line(r.position+Vector2(1,1),r.position+Vector2(14,1),c[1],1)
                if h==3: draw_line(r.position+Vector2(4,5),r.position+Vector2(10,9),c[2],1)
    if outdoor:
        # Broad, unobstructed travel paths remain readable behind the props.
        draw_rect(Rect2(16,116,480,24),Color("958663"))
        draw_rect(Rect2(244,16,24,224),Color("958663"))
        for x in range(20,492,13): draw_line(Vector2(x,119),Vector2(x+6,119),Color("b1a079"),1)
    draw_rect(Rect2(16,16,480,224),Color(0.02,0.05,0.07,0.2),false,3)
    if str(rooms[room_id].theme)=="dark":
        draw_rect(Rect2(0,0,512,256),Color(0.02,0.02,0.08,0.25))

func _draw_atlas_tile(tile_index: int, dest: Rect2) -> void:
    if world_atlas_tex == null: return
    var cell = world_atlas_tex.get_size()/Vector2(4,2)
    var src = Rect2(Vector2(tile_index % 4, int(tile_index / 4))*cell, cell)
    draw_texture_rect_region(world_atlas_tex, dest, src)

func _draw_objects(ground=false, single={}) -> void:
    for o in ([single] if not single.is_empty() else objects):
        var tall = o.kind in ["tree","bush","rock","house","shop","pot","chest","torch","block","cracked"]
        if ground and tall: continue
        if o.dead: continue
        var r: Rect2 = o.rect
        match o.kind:
            "tree": _draw_atlas_tile(0, Rect2(r.get_center()-Vector2(24,42), Vector2(48,48)))
            "bush": _draw_atlas_tile(1, Rect2(r.get_center()-Vector2(16,20), Vector2(32,32)))
            "rock": _draw_atlas_tile(2, Rect2(r.get_center()-Vector2(14,18), Vector2(28,28)))
            "house": _draw_atlas_tile(3, Rect2(r.get_center()-Vector2(30,40), Vector2(60,60)))
            "shop": _draw_atlas_tile(4, Rect2(r.get_center()-Vector2(30,40), Vector2(60,60)))
            "pot": _draw_atlas_tile(5, Rect2(r.get_center()-Vector2(10,14), Vector2(20,20)))
            "chest":
                _draw_atlas_tile(6, Rect2(r.get_center()-Vector2(14,20), Vector2(28,28)))
                if o.opened: draw_rect(Rect2(r.get_center()-Vector2(8,8),Vector2(16,5)),Color("211c25"))
            "torch":
                _draw_atlas_tile(7, Rect2(r.get_center()-Vector2(10,21), Vector2(20,20)))
                if o.get("lit",false): draw_circle(r.position+Vector2(4,-2),6+sin(elapsed*8),Color("#ffb52e"))
            "wall":
                draw_rect(r,Color("282938")); draw_rect(r.grow(-1),Color("56616a"))
                draw_line(r.position+Vector2(1,1),r.position+Vector2(14,1),Color("87928a"),2)
                draw_line(r.position+Vector2(8,8),r.position+Vector2(8,15),Color("333c49"),1)
                draw_line(r.position+Vector2(1,8),r.position+Vector2(15,8),Color("333c49"),1)
            "grass":
                draw_line(r.position+Vector2(2,10),r.position+Vector2(5,2),Color("#a8c95b"),2)
                draw_line(r.position+Vector2(7,10),r.position+Vector2(10,1),Color("#7faf4c"),2)
            "switch": draw_rect(r,Color("#4a3d38")); draw_rect(r.grow(-4),Color("#e6be52") if o.state==1 else Color("#8b7447"))
            "water":
                draw_rect(r,Color("285775")); draw_rect(r.grow(-3),Color("347b91"))
                for wy in range(int(r.position.y)+5,int(r.end.y)-3,11):
                    for wx in range(int(r.position.x)+6,int(r.end.x)-12,22):
                        var wave=sin(elapsed*2+wy+wx)*3
                        draw_line(Vector2(wx+wave,wy),Vector2(wx+8+wave,wy),Color("67adb4"),1)
            "shallow": draw_rect(r,Color(0.25,0.65,0.75,0.18),false,2)
            "pit": draw_rect(r,Color("#111019")); draw_rect(r.grow(-4),Color("#050509"))
            "ice_floor": draw_rect(r,Color(0.55,0.8,0.9,0.45)); draw_line(r.position,r.end,Color(0.8,0.95,1,0.45),1)
            "block": draw_rect(r,Color("#665b76")); draw_rect(r.grow(-3),Color("#887e95"))
            "cracked": draw_rect(r,Color("#51495a")); draw_line(r.position+Vector2(3,2),r.end-Vector2(4,3),Color("#1c1920"),2)
            "upgrade": draw_circle(r.get_center(),8,Color("#57d8f0")); draw_string(ThemeDB.fallback_font,r.position+Vector2(-10,-4),"FINS",HORIZONTAL_ALIGNMENT_LEFT,32,8,Color.WHITE)
            "door_n","door_s","door_w","door_e": pass

func _dir_row(dir: Vector2) -> int:
    if abs(dir.x) > abs(dir.y):
        return 1 if dir.x < 0 else 2
    return 3 if dir.y < 0 else 0

func _draw_npc(n: Dictionary) -> void:
    var cell=cast_tex.get_size()/4.0
    var bob=sin(n.t*9)*0.7 if n.vel.length()>1 else 0.0
    var dest=Rect2(n.pos-Vector2(15,24+bob),Vector2(30,32))
    draw_circle(n.pos+Vector2(0,4),6,Color(0,0,0,0.16))
    draw_texture_rect_region(cast_tex,dest,Rect2(Vector2(int(n.variant)%4,0)*cell,cell))

func _draw_enemy(e: Dictionary) -> void:
    var kind_rows := {"chaser":0,"archer":1,"bat":2,"burrow":3,"bouncer":4,"patrol":5,"elemental":6,"boss":7}
    if e.dead: return
    var row := int(kind_rows.get(e.kind,0))
    var frame := int(elapsed*6.0 + e.t) % 2
    var size := 48.0 if e.kind=="boss" else 24.0
    var tile=4+row
    if e.kind=="boss": tile=[11,12,13,14,5,12,11,14,15][int(e.boss)]
    var cell=cast_tex.get_size()/4.0
    var bob=sin(elapsed*7+float(e.t))*1.0
    var dest=Rect2(e.pos-Vector2(size/2.0,size*0.75+bob),Vector2(size,size))
    draw_circle(e.pos+Vector2(0,5),float(e.radius)*0.75,Color(0,0,0,0.2))
    draw_texture_rect_region(cast_tex,dest,Rect2(Vector2(tile%4,int(tile/4))*cell,cell))
    if e.kind=="boss":
        var boss_colors=[Color("87c17b"),Color("8bcbdc"),Color("e4bb7e"),Color("f0976b"),Color("bb99d5"),Color("79c9dd"),Color("a4cb74"),Color("8be5ff") if e.state==0 else Color("ff885f"),Color("e1c885")]
        draw_arc(e.pos,float(e.radius)+5,0,TAU,24,boss_colors[int(e.boss)],2)
    if e.hurt>0: draw_circle(e.pos,float(e.radius)+2,Color(1,1,1,0.35),false,2)
    if e.freeze>0: draw_circle(e.pos,float(e.radius)+4,Color(0.6,0.9,1,0.45),false,2)
    if e.kind=="boss":
        var w=120.0; draw_rect(Rect2(196,22,w,7),Color("#251c24")); draw_rect(Rect2(198,24,(w-4)*float(e.hp)/float(e.max_hp),3),Color("#e34f5f"))
        draw_string(ThemeDB.fallback_font,Vector2(190,18),str(e.name),HORIZONTAL_ALIGNMENT_CENTER,132,11,Color.WHITE)

func _draw_projectiles() -> void:
    for p in projectiles:
        var c=Color.WHITE
        match p.kind:
            "arrow": c=Color("#f0d07c")
            "boomerang": c=Color("#9fd6d2")
            "fire": c=Color("#ff793d")
            "ice": c=Color("#8be5ff")
            "enemy_orb": c=Color("#ef5b73")
        draw_circle(p.pos,4,c)
        if p.vel.length()>0: draw_line(p.pos,p.pos-p.vel.normalized()*7,c,2)

func _draw_effects() -> void:
    for fx in effects:
        match fx.kind:
            "bomb": draw_circle(fx.pos,7,Color("#25242c")); draw_circle(fx.pos+Vector2(3,-5),2,Color("#ffac38"))
            "burst": draw_circle(fx.pos,18*(1.0-fx.t/0.65),Color(1,0.7,0.25,fx.t))
            "ember": draw_circle(fx.pos,8,Color(1,0.4,0.1,fx.t))
            "spark": draw_circle(fx.pos,6,Color(1,1,0.6,fx.t*3))
            "ice_patch": draw_rect(fx.rect,Color(0.65,0.9,1,0.65))
            "drop":
                var c={"heart":Color("#ef4662"),"arrow":Color("#e7d47b"),"bomb":Color("#44434c"),"magic":Color("#61c878"),"coin":Color("#f0cf4f")}.get(fx.drop,Color.WHITE)
                draw_circle(fx.pos,5,c)

func _draw_player() -> void:
    if player.invuln>0 and int(elapsed*20)%2==0: return
    var row=_dir_row(player.dir)
    var frame=int(elapsed*9)%4 if player.vel.length()>1 else 0
    var cell=hero_walk_tex.get_size()/4.0
    var scale_factor=clampf(player.fall_t/0.55,0.1,1.0) if player.fall_t>0 else 1.0
    var size=Vector2(34,34)*scale_factor
    var source=Rect2(Vector2(frame,row)*cell,cell)
    var dest=Rect2(player.pos-Vector2(size.x/2,size.y*0.8),size)
    if _in_water(player.pos):
        source.size.y*=0.56; dest.size.y*=0.56
        draw_arc(player.pos+Vector2(0,1),10,0,TAU,18,Color("9bd4df"),1)
    else:
        draw_circle(player.pos+Vector2(0,4),7,Color(0,0,0,0.18))
    draw_texture_rect_region(hero_walk_tex,dest,source)
    if player.attack_t>0:
        var angle=player.dir.angle()+lerpf(-1.25,1.25,1.0-player.attack_t/0.24)
        var tip=player.pos+Vector2.RIGHT.rotated(angle)*27
        draw_line(player.pos+Vector2.RIGHT.rotated(angle)*7,tip,Color("556c91"),5)
        draw_line(player.pos+Vector2.RIGHT.rotated(angle)*9,tip,Color("e8f5f8"),3)
        draw_arc(player.pos,25,angle-0.5,angle,8,Color(0.7,0.92,1,0.65),2)
    if player.shield:
        var side=Vector2(-player.dir.y,player.dir.x)
        draw_line(player.pos+player.dir*9-side*6,player.pos+player.dir*9+side*6,Color("d7b85b"),5)
        draw_line(player.pos+player.dir*10-side*4,player.pos+player.dir*10+side*4,Color("527bb0"),3)

func _draw_hud() -> void:
    draw_rect(Rect2(0,256,640,104),Color("111c28"))
    draw_line(Vector2(0,257),Vector2(640,257),Color("bd9857"),2)
    for i in range(player.max_hp):
        var p=Vector2(163+(i%12)*13,273+int(i/12)*10)
        var c=Color("f36b78") if i<player.hp else Color("384450")
        draw_circle(p+Vector2(-2,-1),3,c); draw_circle(p+Vector2(2,-1),3,c)
        draw_colored_polygon(PackedVector2Array([p+Vector2(-5,0),p+Vector2(5,0),p+Vector2(0,6)]),c)
    draw_string(ThemeDB.fallback_font,Vector2(162,304),"MAGIC",0,70,9,Color("9eaeb8"))
    draw_rect(Rect2(207,297,95,6),Color("2b3b46"))
    draw_rect(Rect2(207,297,95*float(player.magic)/player.max_magic,6),Color("6dccab"))
    draw_string(ThemeDB.fallback_font,Vector2(162,323),"KEY %d   ARROW %d   BOMB %d"%[player.keys,player.arrows,player.bombs],0,225,10,Color("e2d6b9"))
    draw_string(ThemeDB.fallback_font,Vector2(162,343),str(rooms[room_id].title),0,230,10,Color("a0b8c4"))
    _panel_button(Rect2(584,7,50,30),"MENU")
    _panel_button(Rect2(584,44,50,30),"MAP")
    _panel_button(Rect2(584,217,50,34),"TALK")
    draw_string(ThemeDB.fallback_font,Vector2(7,22),"C C L",0,50,11,Color("d9ba74"))
    draw_string(ThemeDB.fallback_font,Vector2(9,43),"VAULT",0,50,8,Color("9db0bd"))

func _draw_touch_controls() -> void:
    if paused or title_screen or map_open: return
    draw_circle(STICK,44,Color("243a49")); draw_arc(STICK,44,0,TAU,48,Color("648693"),1)
    draw_line(STICK-Vector2(31,0),STICK+Vector2(31,0),Color("3e5665"),1)
    draw_line(STICK-Vector2(0,31),STICK+Vector2(0,31),Color("3e5665"),1)
    draw_circle(STICK+move_vec*24,18,Color("8ea9b2"))
    _button(SWORD,30,"SWORD")
    _button(SHIELD,26,"GUARD")
    _button(ITEM_A,22,_item_label(str(player.item_a)))
    _button(ITEM_B,18,_item_label(str(player.item_b)))

func _button(p:Vector2,r:float,label:String)->void:
    draw_circle(p+Vector2(0,2),r,Color("080f1b"))
    draw_circle(p,r,Color("304959"))
    draw_arc(p,r-1,0,TAU,40,Color("b2a47b"),1)
    draw_string(ThemeDB.fallback_font,p+Vector2(-r,3),label,HORIZONTAL_ALIGNMENT_CENTER,r*2,8,Color("f6e8c7"))

func _draw_inventory() -> void:
    draw_rect(Rect2(0,0,VW,VH),Color(0.02,0.04,0.07,0.95))
    draw_rect(Rect2(68,20,504,320),Color("9f895e"),false,2)
    draw_string(ThemeDB.fallback_font,Vector2(90,53),"EQUIPMENT",0,460,22,Color("efd494"))
    draw_string(ThemeDB.fallback_font,Vector2(90,75),"Select an item, then choose its touch button.",0,460,12,Color("b7c8d1"))
    for i in range(6):
        var r=_item_rect(i)
        draw_rect(r,Color("416171") if i==menu_cursor else Color("243442"))
        draw_rect(r,Color("e6c783") if i==menu_cursor else Color("506472"),false,1)
        draw_string(ThemeDB.fallback_font,r.position+Vector2(8,28),menu_items[i].to_upper(),HORIZONTAL_ALIGNMENT_CENTER,r.size.x-16,13,Color.WHITE)
    _panel_button(Rect2(90,238,210,36),"A: "+str(player.item_a).to_upper())
    _panel_button(Rect2(340,238,210,36),"B: "+str(player.item_b).to_upper())
    _panel_button(Rect2(90,290,140,34),"SAVE + RESUME")
    _panel_button(Rect2(250,290,140,34),"ROUTE MAP")
    _panel_button(Rect2(410,290,140,34),"SOUND: "+("OFF" if mute else "ON"))

func _draw_message() -> void:
    draw_rect(Rect2(90,222,460,29),Color(0.04,0.08,0.12,0.94))
    draw_rect(Rect2(90,222,460,29),Color("ac975f"),false,1)
    draw_string(ThemeDB.fallback_font,Vector2(98,241),message,HORIZONTAL_ALIGNMENT_CENTER,444,10,Color("f6edda"))

func _prepare_layout(r: Dictionary) -> void:
    # Guarantee a clear cross through every room and clear every arrival point.
    var corridors=[Rect2(24,110,460,36),Rect2(238,24,36,214)]
    for o in objects:
        if o.kind in ["rock","tree","house","shop","block","pot","pit"]:
            for corridor in corridors:
                if o.rect.intersects(corridor): o.dead=true
    # Close non-existent exits. Border gaps align exactly with transition centers.
    for o in objects:
        if o.kind=="wall":
            if o.rect.get_center().y in [16.0,240.0] and absf(o.rect.get_center().x-256)<24: o.dead=true
            if o.rect.get_center().x in [16.0,480.0] and absf(o.rect.get_center().y-128)<24: o.dead=true
    var centers=[Vector2(16,128),Vector2(488,128),Vector2(256,16),Vector2(256,248)]
    for i in range(4):
        if str(r.exits[i])=="":
            objects.append(_obj("wall",centers[i],Vector2(16,40) if i<2 else Vector2(40,16),true))
    if room_id=="field_0":
        # Village is a safe place to learn the controls and replenish supplies.
        objects=objects.filter(func(o): return o.kind not in ["house","shop","rock","tree","bush"])
        objects.append(_obj("house",Vector2(140,84),Vector2(38,26),true))
        objects.append(_obj("shop",Vector2(380,84),Vector2(38,26),true))
        for pos in [Vector2(63,65),Vector2(202,69),Vector2(310,65),Vector2(453,73),Vector2(90,205),Vector2(423,210)]:
            objects.append(_obj("tree",pos,Vector2(16,14),true))
    if room_id.begins_with("dungeon_"):
        var index=int(room_id.trim_prefix("dungeon_"))
        if int(r.boss)<0:
            # Every three-room wing: puzzle, key gate, boss.
            if index%3==0:
                objects=objects.filter(func(o): return o.kind not in ["torch","switch","block","pot","pit"])
                if int(index/3)%2==0:
                    objects.append(_obj("torch",Vector2(144,84),Vector2(12,16),false,{"lit":false}))
                    objects.append(_obj("torch",Vector2(368,184),Vector2(12,16),false,{"lit":false}))
                else:
                    objects.append(_obj("switch",Vector2(320,180),Vector2(16,16),false))
                    objects.append(_obj("block",Vector2(272,180),Vector2(16,16),true,{"pushable":true}))
            # The chest is always approachable and supplies the next key gate.
            objects=objects.filter(func(o): return o.kind!="chest" and not (o.solid and o.kind!="wall" and o.rect.intersects(Rect2(377,40,60,56))))
            objects.append(_obj("chest",Vector2(410,65),Vector2(18,14),true,{"opened":false}))
        else:
            objects=objects.filter(func(o): return o.kind in ["wall","door_n","door_s","door_w","door_e"])
    # Stable IDs help inspection and leave room for future world authoring.
    for i in range(objects.size()): objects[i]["id"]=i

func _gate_open() -> bool:
    if not room_id.begins_with("dungeon_"): return true
    var r=rooms[room_id]
    if int(r.boss)>=0: return room_cleared.get(room_id,false)
    var index=int(room_id.trim_prefix("dungeon_"))
    if index%3==0: return flags.get(room_id+"_puzzle",false)
    if flags.get(room_id+"_unlock",false): return true
    if player.keys>0:
        player.keys-=1; flags[room_id+"_unlock"]=true
        _play_sfx("switch")
        return true
    return false

func _gate_hint() -> String:
    if int(rooms[room_id].boss)>=0: return "Defeat the guardian to open the eastern seal."
    var index=int(room_id.trim_prefix("dungeon_"))
    if index%3==1: return "A key opens this seal. Search the treasure chest."
    if int(index/3)%2==0: return "Light both braziers with the lantern or fire rod."
    return "Push the stone onto the gold pressure plate."

func _update_puzzle() -> void:
    if not room_id.begins_with("dungeon_") or int(rooms[room_id].boss)>=0: return
    var index=int(room_id.trim_prefix("dungeon_"))
    if index%3!=0 or flags.get(room_id+"_puzzle",false): return
    var solved=false
    if int(index/3)%2==0:
        var lit=0
        for o in objects:
            if o.kind=="torch" and o.get("lit",false): lit+=1
        solved=lit>=2
    else:
        for plate in objects:
            if plate.kind!="switch": continue
            for block in objects:
                if block.kind=="block" and block.rect.get_center().distance_to(plate.rect.get_center())<8:
                    plate.state=1; solved=true
    if solved:
        flags[room_id+"_puzzle"]=true
        _announce_secret("The eastern seal opens!")

func _draw_gate() -> void:
    var exits=rooms[room_id].exits
    var points=[Vector2(28,128),Vector2(477,128),Vector2(256,27),Vector2(256,233)]
    for i in range(4):
        if str(exits[i])=="": continue
        var p=points[i]
        var d=[Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN][i]
        var side=Vector2(-d.y,d.x)
        draw_line(p-d*4+side*4,p+d*2,Color("e5d59a"),2)
        draw_line(p-d*4-side*4,p+d*2,Color("e5d59a"),2)
    if not room_id.begins_with("dungeon_"): return
    var index=int(room_id.trim_prefix("dungeon_"))
    var open=room_cleared.get(room_id,false) if int(rooms[room_id].boss)>=0 else flags.get(room_id+("_puzzle" if index%3==0 else "_unlock"),false)
    if not open:
        for y in range(113,145,6): draw_line(Vector2(480,y),Vector2(490,y),Color("d9b46d"),2)
        draw_line(Vector2(485,110),Vector2(485,146),Color("8da0b0"),2)

func _interact() -> void:
    if room_id=="field_0":
        if player.pos.distance_to(Vector2(380,84))<65:
            player.hp=player.max_hp; player.magic=player.max_magic
            player.arrows=maxi(player.arrows,20); player.bombs=maxi(player.bombs,8)
            _announce_secret("Village provisions: health, magic, arrows and bombs restored.")
            _save_game(); return
        for n in npcs:
            if n.pos.distance_to(player.pos)<55:
                var lines=["Go east twice, then east again to reach the Ninefold Vault.","Swim fins wait on the far shore. Follow the dry shoreline.","Lanterns light nearby braziers without spending magic.","Use MENU to equip rods. Ice and fire break elemental wards."]
                message=lines[int(n.variant)%4]; message_t=5; return
        message="Visit the red-roof shop to restock. East leads to the vault."
    elif room_id.begins_with("dungeon_"):
        if int(rooms[room_id].boss)==7: message="Prism Regent: use ICE during blue, FIRE during red."
        else: message=_gate_hint()
    else: message="Follow the gold exit arrows. MAP shows the route."
    message_t=5

func _reset_touch() -> void:
    move_touch=-1; move_vec=Vector2.ZERO; touch_points.clear()
    touch_attack=false; touch_shield=false; touch_item_a=false; touch_item_b=false
    player.shield=false

func _toggle_pause() -> void:
    paused=not paused; _reset_touch()
    _save_game()

func _notification(what: int) -> void:
    if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
        _reset_touch()
        if not title_screen and not rooms.is_empty():
            paused=true; _save_game()

func _save_game() -> void:
    if title_screen: return
    room_states[room_id]=objects.duplicate(true)
    var f=FileAccess.open(save_path,FileAccess.WRITE)
    if f:
        f.store_var({"version":1,"player":player,"room":room_id,"states":room_states,"cleared":room_cleared,"flags":flags,"visited":visited,"safe":safe_pos,"mute":mute})
    else:
        message="Save unavailable: check device storage."; message_t=4

func _start_game(continue_save: bool) -> void:
    title_screen=false; paused=false; map_open=false
    _reset_touch()
    if continue_save:
        var f=FileAccess.open(save_path,FileAccess.READ)
        if f:
            var data=f.get_var(false)
            if data is Dictionary and data.get("version",0)==1 and rooms.has(data.get("room","")):
                player=data.player; room_states=data.states; room_cleared=data.cleared; flags=data.flags; visited=data.visited
                mute=data.get("mute",false); AudioServer.set_bus_mute(0,mute)
                _load_room(data.room,data.get("safe",Vector2(256,180)))
                player.invuln=1; player.fall_t=0; return
    player=initial_player.duplicate(true)
    flags.clear(); room_cleared.clear(); room_states.clear(); visited.clear()
    _load_room("field_0",Vector2(256,180))
    message="Welcome! Explore the village. The Ninefold Vault lies east."; message_t=6
    _save_game()

func _item_rect(i: int) -> Rect2:
    return Rect2(90+(i%3)*158,94+int(i/3)*66,144,54)

func _panel_button(r: Rect2, label: String) -> void:
    draw_rect(r,Color("263c4b")); draw_rect(r,Color("9b916d"),false,1)
    draw_string(ThemeDB.fallback_font,r.position+Vector2(3,r.size.y/2+4),label,HORIZONTAL_ALIGNMENT_CENTER,r.size.x-6,10,Color("f4e6c4"))

func _draw_title() -> void:
    draw_rect(Rect2(0,0,640,360),Color(0.025,0.055,0.09,0.94))
    for i in range(35):
        var p=Vector2(fmod(i*83.3,640),fmod(i*39.7+elapsed*5,360))
        draw_circle(p,1,Color(0.75,0.86,0.65,0.25+0.2*sin(elapsed+i)))
    draw_rect(Rect2(28,24,584,312),Color("847751"),false,1)
    draw_string(ThemeDB.fallback_font,Vector2(80,91),"CHRONICLE CLASH",HORIZONTAL_ALIGNMENT_CENTER,480,25,Color("efdbac"))
    draw_string(ThemeDB.fallback_font,Vector2(100,128),"T H E   N I N E F O L D   V A U L T",HORIZONTAL_ALIGNMENT_CENTER,440,14,Color("85bcc9"))
    draw_string(ThemeDB.fallback_font,Vector2(90,162),"Explore the wilds. Break the seals. Defeat nine guardians.",HORIZONTAL_ALIGNMENT_CENTER,460,12,Color("bdc9c8"))
    _panel_button(Rect2(182,188,276,42),"NEW ADVENTURE")
    if FileAccess.file_exists(save_path): _panel_button(Rect2(182,240,276,36),"CONTINUE SAVED ADVENTURE")
    draw_string(ThemeDB.fallback_font,Vector2(80,309),"Left stick: move   |   Sword / Guard   |   A / B: equipped items",HORIZONTAL_ALIGNMENT_CENTER,480,10,Color("b3c1cb"))

func _draw_map() -> void:
    draw_rect(Rect2(0,0,640,360),Color("101e2b"))
    draw_string(ThemeDB.fallback_font,Vector2(30,36),"EXPLORER'S ROUTE MAP",0,580,22,Color("e3cc94"))
    var overworld={"castle_1":Vector2(72,118),"castle_0":Vector2(149,118),"field_0":Vector2(226,118),"field_1":Vector2(303,118),"field_2":Vector2(380,118),"cave_0":Vector2(226,87),"cave_1":Vector2(226,58),"water_0":Vector2(226,149),"water_1":Vector2(226,180)}
    for id in overworld:
        var p=overworld[id]
        for target in rooms[id].exits:
            if overworld.has(target): draw_line(p,overworld[target],Color("506579"),2)
    for id in overworld:
        var p=overworld[id]
        var color=Color("ddbe75") if id==room_id else (Color("5b9a9a") if visited.has(id) else Color("2a4055"))
        draw_rect(Rect2(p-Vector2(26,10),Vector2(52,20)),color)
        draw_string(ThemeDB.fallback_font,p+Vector2(-25,3),id.replace("field","wild"),HORIZONTAL_ALIGNMENT_CENTER,50,8,Color.WHITE)
    draw_string(ThemeDB.fallback_font,Vector2(430,105),"EAST TO VAULT",0,180,11,Color("d7c398"))
    draw_line(Vector2(408,118),Vector2(594,118),Color("8e805d"),2)
    draw_string(ThemeDB.fallback_font,Vector2(30,219),"THE NINEFOLD VAULT  /  puzzle > key > guardian",0,560,13,Color("e3cc94"))
    for i in range(27):
        var id="dungeon_%d"%i
        var p=Vector2(40+(i%9)*67,240+int(i/9)*28)
        var c=Color("edc979") if id==room_id else (Color("467f88") if visited.has(id) else Color("25394b"))
        if room_cleared.get(id,false): c=c.lightened(0.12)
        draw_rect(Rect2(p,Vector2(54,21)),c)
        draw_string(ThemeDB.fallback_font,p+Vector2(3,15),"%02d%s"%[i+1," B" if i%3==2 else ""],HORIZONTAL_ALIGNMENT_CENTER,48,10,Color.WHITE)
    draw_string(ThemeDB.fallback_font,Vector2(30,344),"Gold: you   Teal: visited   B: guardian   |   Tap anywhere to return",0,590,11,Color("c2cdd4"))

func _exit_tree() -> void:
    if is_instance_valid(music_player):
        music_player.stop(); music_player.stream=null
    for channel in sfx_pool:
        if is_instance_valid(channel):
            channel.stop(); channel.stream=null

func _item_label(item: String) -> String:
    return {"boomerang":"RANG","lantern":"LAMP"}.get(item,item.to_upper())
