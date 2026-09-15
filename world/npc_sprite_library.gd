extends RefCounted

const CHILD_SHEET_PATH:="res://assets/trainers/Child Sprites.png"

# Source sheets are concept boards rather than transparent atlases. These rectangles
# isolate the neutral south-facing adult poses and a south-facing child idle extreme.
# Edge flood removal keeps pale clothing intact while discarding presentation art.
const SPRITES := {
	"man": {"remove_background":true,"idle_path":"res://assets/trainers/Young Man Idle.png","walk_path":"res://assets/trainers/Male Ref Citizen.png","idle":{"down":Rect2i(90,80,230,365),"up":Rect2i(470,80,230,365),"left":Rect2i(830,80,230,365),"right":Rect2i(1205,80,230,365)},"walk":{"down":[Rect2i(35,185,170,300),Rect2i(220,185,170,300),Rect2i(405,185,170,300),Rect2i(590,185,170,300)],"up":[Rect2i(820,185,170,300),Rect2i(1005,185,170,300),Rect2i(1185,185,170,300),Rect2i(1365,185,170,300)],"left":[Rect2i(35,600,170,300),Rect2i(220,600,170,300),Rect2i(405,600,170,300),Rect2i(590,600,170,300)],"right":[Rect2i(820,600,170,300),Rect2i(1005,600,170,300),Rect2i(1185,600,170,300),Rect2i(1365,600,170,300)]}},
	"woman": {"remove_background":true,"idle_path":"res://assets/trainers/Young Woman Idle.png","walk_path":"res://assets/trainers/Female Ref Citizen.png","idle":{"down":Rect2i(90,90,230,365),"up":Rect2i(470,80,230,375),"left":Rect2i(825,80,240,375),"right":Rect2i(1200,80,240,375)},"walk":{"down":[Rect2i(35,180,170,310),Rect2i(220,180,170,310),Rect2i(405,180,170,310),Rect2i(590,180,170,310)],"up":[Rect2i(820,180,170,310),Rect2i(1005,180,170,310),Rect2i(1185,180,170,310),Rect2i(1365,180,170,310)],"left":[Rect2i(25,590,175,320),Rect2i(210,590,175,320),Rect2i(395,590,175,320),Rect2i(580,590,175,320)],"right":[Rect2i(815,590,175,320),Rect2i(1000,590,175,320),Rect2i(1180,590,175,320),Rect2i(1360,590,175,320)]}},
	"boy": {"idle_path":CHILD_SHEET_PATH,"walk_path":CHILD_SHEET_PATH,"idle":{"down":Rect2i(0,0,85,160),"up":Rect2i(0,168,85,160),"left":Rect2i(0,340,85,165),"right":Rect2i(0,510,85,175)},"walk":{"down":[Rect2i(0,0,85,160),Rect2i(105,0,85,160),Rect2i(215,0,85,160),Rect2i(320,0,85,160)],"up":[Rect2i(0,168,85,160),Rect2i(105,168,85,160),Rect2i(215,168,85,160),Rect2i(320,168,85,160)],"left":[Rect2i(0,340,85,165),Rect2i(105,340,85,165),Rect2i(215,340,85,165),Rect2i(320,340,85,165)],"right":[Rect2i(0,510,85,175),Rect2i(105,510,85,175),Rect2i(215,510,85,175),Rect2i(320,510,85,175)]}},
	"girl": {"idle_path":CHILD_SHEET_PATH,"walk_path":CHILD_SHEET_PATH,"idle":{"down":Rect2i(445,0,95,165),"up":Rect2i(445,168,95,165),"left":Rect2i(445,340,95,170),"right":Rect2i(445,510,95,175)},"walk":{"down":[Rect2i(445,0,95,165),Rect2i(555,0,95,165),Rect2i(665,0,95,165),Rect2i(770,0,95,165)],"up":[Rect2i(445,168,95,165),Rect2i(555,168,95,165),Rect2i(665,168,95,165),Rect2i(770,168,95,165)],"left":[Rect2i(445,340,95,170),Rect2i(555,340,95,170),Rect2i(665,340,95,170),Rect2i(770,340,95,170)],"right":[Rect2i(445,510,95,175),Rect2i(555,510,95,175),Rect2i(665,510,95,175),Rect2i(770,510,95,175)]}},
}

static var _cache: Dictionary = {}
static var _warned: Dictionary = {}


static func texture_for(sprite_id:String,direction:String="down",walk_frame:int=-1)->Texture2D:
	var pose:="idle" if walk_frame<0 else "walk"
	var cache_key:="%s:%s:%s:%d"%[sprite_id,pose,direction,walk_frame]
	if _cache.has(cache_key):return _cache[cache_key]
	var spec:Dictionary=SPRITES.get(sprite_id,{})
	if spec.is_empty():
		_warn_once(sprite_id,"unknown NPC sprite id")
		return null
	var regions:Dictionary=spec.get(pose,{})
	if not regions.has(direction):direction="down"
	var rect:Rect2i
	if pose=="walk":
		var frames:Array=regions[direction]
		rect=frames[posmod(walk_frame,frames.size())]
	else:rect=regions[direction]
	var source_path:=String(spec.get(pose+"_path",""))
	var source:Texture2D=load(source_path) as Texture2D
	if source==null:
		_warn_once(sprite_id,"source sheet could not be imported: "+source_path)
		return null
	var image:=source.get_image()
	if image==null or not Rect2i(Vector2i.ZERO,image.get_size()).encloses(rect):
		_warn_once(sprite_id,"configured slice is outside the source sheet")
		return null
	var frame:=image.get_region(rect)
	if bool(spec.get("remove_background",false)):
		_remove_edge_background(frame)
	frame=_trim_transparent(frame,4)
	if frame.is_empty():
		_warn_once(sprite_id,"slice contained no usable sprite pixels")
		return null
	var texture:=ImageTexture.create_from_image(frame)
	_cache[cache_key]=texture
	return texture


static func _remove_edge_background(image:Image)->void:
	image.convert(Image.FORMAT_RGBA8)
	var size:=image.get_size()
	var visited:=PackedByteArray()
	visited.resize(size.x*size.y)
	var queue:Array[Vector2i]=[]
	for x in size.x:
		queue.append(Vector2i(x,0));queue.append(Vector2i(x,size.y-1))
	for y in range(1,size.y-1):
		queue.append(Vector2i(0,y));queue.append(Vector2i(size.x-1,y))
	var cursor:=0
	while cursor<queue.size():
		var point:=queue[cursor];cursor+=1
		var index:=point.y*size.x+point.x
		if visited[index]:continue
		visited[index]=1
		var color:=image.get_pixelv(point)
		image.set_pixelv(point,Color(color.r,color.g,color.b,0.0))
		for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var neighbor:Vector2i=point+step
			if neighbor.x<0 or neighbor.y<0 or neighbor.x>=size.x or neighbor.y>=size.y:continue
			var neighbor_index:int=neighbor.y*size.x+neighbor.x
			if visited[neighbor_index]:continue
			var next:=image.get_pixelv(neighbor)
			if _rgb_distance(color,next)<=0.075:queue.append(neighbor)


static func _rgb_distance(a:Color,b:Color)->float:
	return absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)


static func _trim_transparent(image:Image,padding:int)->Image:
	var used:=image.get_used_rect()
	if used.size==Vector2i.ZERO:return Image.new()
	used=used.grow(padding).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	return image.get_region(used)


static func _warn_once(sprite_id:String,message:String)->void:
	if _warned.has(sprite_id):return
	_warned[sprite_id]=true
	push_warning("NPC art '%s' unavailable (%s); using the colored placeholder."%[sprite_id,message])
