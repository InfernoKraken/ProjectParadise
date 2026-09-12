class_name FakemonArtPackage
extends RefCounted

const MEMBERS := {
	"player":{"label":"Player Battle","folder":"assets/fakemon/battle","suffix":"_Player.png","side":"Player"},
	"wild":{"label":"Wild Battle","folder":"assets/fakemon/battle","suffix":"_Wild.png","side":"Wild"},
	"down":{"label":"Follow Down","folder":"assets/fakemon/overworld","suffix":"_Follow_Down.png"},
	"up":{"label":"Follow Up","folder":"assets/fakemon/overworld","suffix":"_Follow_Up.png"},
	"right":{"label":"Follow Right","folder":"assets/fakemon/overworld","suffix":"_Follow_Right.png"},
	"left":{"label":"Follow Left","folder":"assets/fakemon/overworld","suffix":"_Follow_Left.png"},
}
const REQUIRED := ["head","origin"]
const OPTIONAL := ["mouth","neck","left_wing","right_wing","tail"]
const COLORS := {"head":Color8(255,32,32),"origin":Color8(32,255,32),"mouth":Color8(32,96,255),"neck":Color8(255,224,32),"left_wing":Color8(255,32,224),"right_wing":Color8(32,255,224),"tail":Color8(255,128,32)}
const SIGNATURE := [Color8(65,78,67),Color8(72,79,82),Color8(1,0,0)]

var root: String
var art_id := ""
var original_art_id := ""
var staged: Dictionary = {}
var anchors := {"Player":{},"Wild":{}}
var original_anchors := {"Player":{},"Wild":{}}
var anchor_dirty := {"Player":false,"Wild":false}
var error := ""

func _init(game_root: String) -> void: root=game_root
func load_package(id: String) -> void:
	art_id=id; original_art_id=id; staged.clear(); anchor_dirty={"Player":false,"Wild":false}
	for side in ["Player","Wild"]:
		anchors[side]=_load_anchors(side); original_anchors[side]=anchors[side].duplicate(true)

func path_for(key: String, id := "") -> String:
	var use_id:=art_id if id.is_empty() else id; var spec:Dictionary=MEMBERS[key]
	return root.path_join(spec.folder).path_join(use_id+String(spec.suffix))
func anchor_path(side: String) -> String: return root.path_join("assets/fakemon/battle/%s_%s.anchors.png"%[art_id,side])
func image_for(key: String) -> Image:
	if staged.has(key): return staged[key]
	var image:=Image.new(); return image if image.load(path_for(key))==OK else null
func stage(key: String, source_path: String) -> bool:
	var image:=Image.new(); var result:=image.load(source_path)
	if result!=OK or image.is_empty(): error="The selected file is not a readable image."; return false
	staged[key]=image; return true
func unstage(key:String)->void: staged.erase(key)
func is_dirty()->bool: return not staged.is_empty() or bool(anchor_dirty.Player) or bool(anchor_dirty.Wild) or art_id!=original_art_id

func package_ids()->Array[String]:
	var found:Dictionary={}
	for spec:Dictionary in MEMBERS.values():
		var dir:=DirAccess.open(root.path_join(spec.folder)); if dir==null:continue
		for file in dir.get_files():
			if file.ends_with(spec.suffix):found[file.trim_suffix(spec.suffix)]=true
	var result:Array[String]=[]
	for id in found.keys(): result.append(String(id))
	result.sort()
	return result

func health()->Array[String]:
	var result:Array[String]=[]
	for key in MEMBERS:
		var state:="STAGED" if staged.has(key) else "OK" if FileAccess.file_exists(path_for(key)) else "MISSING"
		result.append("%s|%s"%[state,MEMBERS[key].label])
	for side in ["Player","Wild"]:
		var battle_key:String=side.to_lower(); var source:Image=image_for(battle_key); var ap:=anchor_path(side)
		if not FileAccess.file_exists(ap):result.append("MISSING|%s Anchors"%side);continue
		var map:=Image.new(); map.load(ap)
		if source==null or map.get_size()!=source.get_size():result.append("INVALID|%s Anchors (dimension mismatch)"%side)
		else:
			var missing:=[]; for required in REQUIRED:if not anchors[side].has(required):missing.append(required)
			var signature_ok:=map.get_width()>=3
			if signature_ok:
				for i in 3:
					if map.get_pixel(i,0).to_rgba32()!=SIGNATURE[i].to_rgba32():signature_ok=false
			var detail:=" (invalid v1 signature)" if not signature_ok else " (missing "+", ".join(missing)+")" if not missing.is_empty() else ""
			result.append(("OK" if signature_ok and missing.is_empty() else "INVALID")+"|%s Anchors%s"%[side,detail])
	return result

func replacement_warning(side:String)->String:
	var key:=side.to_lower(); if not staged.has(key):return ""
	var old:=Image.new(); var old_size:=Vector2i.ZERO if old.load(path_for(key))!=OK else old.get_size(); var new_size:Vector2i=staged[key].get_size()
	if old_size!=Vector2i.ZERO and old_size!=new_size:return "⚠ %s ANCHORS REQUIRE REVIEW — dimensions changed %s → %s"%[side.to_upper(),old_size,new_size]
	return "⚠ %s Battle image changed — review anchor placement."%side

func set_anchor(side:String,name:String,point:Vector2i)->void: anchors[side][name]=point; anchor_dirty[side]=anchors[side]!=original_anchors[side]
func clear_anchor(side:String,name:String)->void: if not REQUIRED.has(name):anchors[side].erase(name);anchor_dirty[side]=anchors[side]!=original_anchors[side]

func affected_files()->Array[String]:
	var files:Array[String]=[]; for key in staged:files.append(path_for(key).get_file())
	for side in ["Player","Wild"]:if anchor_dirty[side]:files.append(anchor_path(side).get_file())
	return files
func write()->bool:
	error=""
	for side in ["Player","Wild"]:
		if anchor_dirty[side]:
			var source:=image_for(side.to_lower()); if source==null:error="%s anchors have no battle image."%side;return false
			for required in REQUIRED:if not anchors[side].has(required):error="%s anchors require '%s'."%[side,required];return false
	for key in staged:
		if staged[key].save_png(path_for(key))!=OK:error="Could not write %s."%path_for(key);return false
	for side in ["Player","Wild"]:
		if anchor_dirty[side] and not _write_anchor_side(side):return false
	staged.clear(); original_art_id=art_id
	for side in ["Player","Wild"]:original_anchors[side]=anchors[side].duplicate(true);anchor_dirty[side]=false
	return true

func _load_anchors(side:String)->Dictionary:
	var image:=Image.new(); if image.load(anchor_path(side))!=OK:return {}
	return _extract(image)
func _write_anchor_side(side:String)->bool:
	var source:=image_for(side.to_lower());var map:=_create_anchor_image(source.get_size(),anchors[side])
	if map.save_png(anchor_path(side))!=OK:error="Could not write %s anchor map."%side;return false
	var generated_path:=root.path_join("data/generated_battle_anchors.json");var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(generated_path)) if FileAccess.file_exists(generated_path) else {}
	var generated:Dictionary=parsed if parsed is Dictionary else {};generated["format_version"]=1;generated.get_or_add("sprites",{})
	var processed:=map.duplicate();var scale:=minf(1.0,200.0/maxf(processed.get_width(),processed.get_height()));processed.resize(maxi(1,roundi(processed.get_width()*scale)),maxi(1,roundi(processed.get_height()*scale)),Image.INTERPOLATE_NEAREST)
	var points:=_extract(processed);var values:Dictionary={};for name in points:var p:Vector2=points[name];values[name]=[snappedf(p.x,0.001),snappedf(p.y,0.001)]
	generated.sprites[art_id+"_"+side]={"processed_size":[processed.get_width(),processed.get_height()],"anchors":values}
	var file:=FileAccess.open(generated_path,FileAccess.WRITE);if file==null:error="Could not update generated battle anchors.";return false
	file.store_string(JSON.stringify(generated,"  ")+"\n");return true
func _create_anchor_image(size:Vector2i,points:Dictionary)->Image:
	var image:=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT)
	for i in mini(3,size.x):image.set_pixel(i,0,SIGNATURE[i])
	for name:String in points:
		var color:=_color_for(name);var center:=Vector2i(points[name])
		for y in range(center.y-2,center.y+3):for x in range(center.x-2,center.x+3):if x>=0 and y>=0 and x<size.x and y<size.y:image.set_pixel(x,y,color)
	return image
func _extract(image:Image)->Dictionary:
	var sums:Dictionary={};var counts:Dictionary={}
	for y in image.get_height():for x in image.get_width():
		var color:=image.get_pixel(x,y);if color.a8==0 or SIGNATURE.any(func(c):return c.to_rgba32()==color.to_rgba32()):continue
		var name:=_name_for(color);if not name.is_empty():sums[name]=sums.get(name,Vector2.ZERO)+Vector2(x,y);counts[name]=counts.get(name,0)+1
	var result:Dictionary={}
	for name in sums: result[name]=sums[name]/counts[name]
	return result
func _color_for(name:String)->Color:
	if COLORS.has(name):return COLORS[name]
	var id:=int(name.trim_prefix("custom_"));return Color8(192+((id>>16)&63),(id>>8)&255,id&255)
func _name_for(color:Color)->String:
	for name in COLORS:if COLORS[name].to_rgba32()==color.to_rgba32():return name
	if color.a8==255 and color.r8>=192:var id:=((color.r8-192)<<16)|(color.g8<<8)|color.b8;return "custom_%d"%id if id>0 else ""
	return ""
