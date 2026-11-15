extends Control
const Bounds=preload("res://scripts/city_world.gd")
var game: Node
func _process(_delta: float) -> void:
    queue_redraw()
func point(pos: Vector3) -> Vector2:
    var scale:=90.0/350 if game.selected_map=="palm_bay" else .18
    return Vector2(110+pos.x*scale,110+pos.z*scale)
func _draw() -> void:
    if not is_instance_valid(game) or not game.is_route_map(): return
    draw_style_box(get_theme_stylebox("panel","Panel"),Rect2(Vector2.ZERO,Vector2(220,220)))
    draw_rect(Rect2(0,0,220,220),Color(.015,.035,.05,.9))
    # Western coastline and the playable limit are visible independently of the skyline.
    draw_rect(Rect2(0,0,14,220),Color(.03,.20,.29,.9))
    var resort:bool=game.selected_map=="palm_bay"
    var edge:=350.0 if resort else Bounds.PLAY_LIMIT
    var start:=point(Vector3(-edge,0,-edge))
    draw_rect(Rect2(start,point(Vector3(edge,0,edge))-start),Color(1,.65,.2,.5),false,1.0)
    var axes:Array=[-320,-160,0,160,320] if resort else [-480,-320,-160,0,160,320,480]
    var extent:=365.0 if resort else 530.0
    for axis in axes:
        draw_line(point(Vector3(axis,0,-extent)),point(Vector3(axis,0,extent)),Color(.3,.36,.4),2)
        draw_line(point(Vector3(-extent,0,axis)),point(Vector3(extent,0,axis)),Color(.3,.36,.4),2)
    var route := PackedVector2Array()
    for pos in game.city_route:route.append(point(pos))
    draw_polyline(route,Color(.10,.35,.40),2,true)
    var remaining:=PackedVector2Array()
    for i in range(maxi(0,game.next_gate-1),game.city_route.size()):remaining.append(point(game.city_route[i]))
    if remaining.size()>1:draw_polyline(remaining,Color(.1,.8,.95),3,true)
    for i in game.city_gates.size():
        draw_circle(point(game.city_gates[i]),4,Color(.25,1,.5) if i<game.next_gate else Color(1,.69,.22))
    if game.next_gate<game.city_gates.size():draw_arc(point(game.city_gates[game.next_gate]),7,0,TAU,20,Color.WHITE,1.5,true)
    var center := point(game.car.position)
    var forward: Vector3 = -game.car.global_basis.z
    var dir := Vector2(forward.x,forward.z)
    var right := Vector2(-dir.y,dir.x)
    draw_colored_polygon(PackedVector2Array([center+dir*8,center-dir*5+right*4,center-dir*5-right*4]),Color.WHITE)
