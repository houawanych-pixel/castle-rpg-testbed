extends SceneTree
var failures=0
func check(ok: bool, label: String) -> void:
    if not ok:
        failures+=1
        push_error(label)
    else: print("PASS: "+label)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var g=load("res://scripts/Game.gd").new()
    g.save_path="user://ccl_mobile_smoke_test.save"
    root.add_child(g)
    await process_frame
    g.set_physics_process(false); g.set_process(false)
    g._start_game(false)
    check(g.enemies.is_empty(),"Village is safe")
    var graph_ok=true
    var opposites=[1,0,3,2]
    for id in g.rooms:
        for i in range(4):
            var target=g.rooms[id].exits[i]
            if target!="" and g.rooms[target].exits[opposites[i]]!=id: graph_ok=false
    check(graph_ok,"Every world connection has a matching return exit")
    check(g.rooms.size()==36,"All 36 adventure rooms exist")
    g._touch_button_press(Vector2(610,20))
    check(g.paused,"Touch menu pauses")
    for i in range(6):
        g._touch_button_press(g._item_rect(i).get_center())
        g._touch_button_press(Vector2(180,252))
        check(g.player.item_a==g.menu_items[i],"Touch selects and equips "+g.menu_items[i])
    g._touch_button_press(Vector2(160,306))
    check(not g.paused,"Touch resume unpauses")
    var press=InputEventScreenTouch.new()
    press.index=1; press.position=g.STICK+Vector2(20,0); press.pressed=true
    g._input(press)
    var sword=InputEventScreenTouch.new()
    sword.index=2; sword.position=g.SWORD; sword.pressed=true
    g._input(sword)
    check(g.move_vec.x>0 and g.touch_attack,"Two-finger movement and attack work together")
    press.pressed=false; g._input(press)
    sword.pressed=false; g._input(sword)
    check(g.move_vec==Vector2.ZERO,"Movement finger release clears motion")
    g._reset_touch()
    g._load_room("field_0",Vector2(490,128)); g.transition_t=0
    g._world_bounds_and_transitions()
    check(g.room_id=="field_1","East transition loads the linked room")
    g._load_room("field_0",Vector2(256,244)); g.transition_t=0
    g._world_bounds_and_transitions()
    check(g.room_id=="water_0","South transition is reachable")
    g._load_room("water_0",Vector2(100,100)); g.player.flippers=false
    g.player.pos=Vector2(150,100); g.safe_pos=Vector2(100,100)
    check(g._in_water(g.player.pos),"Water geometry is detected")
    g._load_room("dungeon_0",Vector2(44,128))
    check(not g._gate_open(),"Torch seal starts locked")
    for o in g.objects:
        if o.kind=="torch": o.lit=true
    g._update_puzzle()
    check(g._gate_open(),"Two lit braziers open the seal")
    g._load_room("dungeon_3",Vector2(44,128))
    var plate_pos=Vector2.ZERO
    for o in g.objects:
        if o.kind=="switch": plate_pos=o.rect.get_center()
    for o in g.objects:
        if o.kind=="block": o.rect.position=plate_pos-o.rect.size/2
    g._update_puzzle()
    check(g._gate_open(),"Block pressure puzzle opens the seal")
    g._load_room("dungeon_1",Vector2(44,128)); g.player.keys=0
    check(not g._gate_open(),"Key gate rejects missing key")
    g.player.keys=1
    check(g._gate_open() and g.player.keys==0,"Key gate consumes one key")
    check(g._gate_open() and g.player.keys==0,"Unlocked gate does not consume another key")
    g._load_room("dungeon_2",Vector2(44,128))
    check(not g._gate_open(),"Living guardian locks east exit")
    g.room_cleared[g.room_id]=true
    check(g._gate_open(),"Defeated guardian opens exit")
    g._load_room("castle_0",Vector2(400,64))
    g._environment_player_checks()
    g.room_states[g.room_id]=g.objects.duplicate(true)
    g.player.coins=73; g._save_game()
    g.player.coins=0; g._start_game(true)
    check(g.player.coins==73 and g.room_id=="castle_0","Save and continue restore player and room")
    var opened=false
    for o in g.objects:
        if o.kind=="chest": opened=o.opened
    check(opened,"Opened chest persists after save/load")
    for id in g.rooms:
        g._load_room(id,Vector2(44,128))
        for tick in range(5): g._physics_process(1.0/60.0)
    check(true,"Every room and boss executes physics")
    # Test an actual complete route through every original wing, including victory.
    g.flags.clear();g.room_states.clear();g.room_cleared.clear();g.player.keys=0
    for i in range(27):
        g._load_room("dungeon_%d"%i,Vector2(44,128))
        if i%3==0:
            for o in g.objects:
                if o.kind=="torch": o.lit=true
            var plate=Vector2.ZERO
            for o in g.objects:
                if o.kind=="switch": plate=o.rect.get_center()
            for o in g.objects:
                if o.kind=="block": o.rect.position=plate-o.rect.size/2
            g._update_puzzle()
        if i%3!=2:
            g.player.pos=Vector2(410,82);g._environment_player_checks()
        else:
            var boss=g.enemies[0]
            boss.t=1.5;boss.state=0
            g._damage_enemy(boss,100,"ice")
        check(g._gate_open(),"Wing route seal %02d"%(i+1))
    check(g.flags.get("victory",false),"Final guardian triggers adventure victory")
    print("RESULT: ",failures," failures")
    g._exit_tree()
    await create_timer(0.25).timeout
    g.free()
    await process_frame
    await process_frame
    quit(1 if failures else 0)
