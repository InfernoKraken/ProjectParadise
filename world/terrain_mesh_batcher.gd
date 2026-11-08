extends RefCounted

const WaterClip := preload("res://tools/map_editor/core/wall_water_clip.gd")
const CHUNK_SIZE := 16

# Keep per-cell UVs and clipped shore geometry, but submit one mesh per terrain
# per chunk. Authoring and gameplay continue to use the original terrain grid.
static func build(grid:Dictionary,base_terrain:String,objects:Array=[])->Dictionary:
	var builders:Dictionary={}
	var positions:Array=grid.keys()
	positions.sort_custom(func(a:Vector2i,b:Vector2i):return a.y<b.y or (a.y==b.y and a.x<b.x))
	for position:Vector2i in positions:
		var terrain_type:=String(grid[position])
		var regions:Array=[Rect2(Vector2(position)-Vector2.ONE*0.5,Vector2.ONE)]
		if terrain_type=="water":regions=WaterClip.regions(position,grid,objects)
		if terrain_type!=base_terrain:
			for region:Rect2 in regions:_append_plane(_base_surface(builders,terrain_type,position),region,0.0)
		if terrain_type=="water" and base_terrain!="sand":
			for region:Rect2 in WaterClip.sand_regions(position,grid,objects):_append_plane(_base_surface(builders,"sand",position),region,0.0)
	var result:Dictionary={}
	for key in builders:
		result[key]={"terrain_type":builders[key].terrain_type,"mesh":builders[key].surface.commit()}
	return result

static func _base_surface(builders:Dictionary,terrain_type:String,position:Vector2i)->SurfaceTool:
	var key:="%s_%d_%d"%[terrain_type,floori(float(position.x)/CHUNK_SIZE),floori(float(position.y)/CHUNK_SIZE)]
	if not builders.has(key):
		var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		builders[key]={"terrain_type":terrain_type,"surface":surface}
	return builders[key].surface

# Composite shoreline textures are already shared/cached. Keep one draw per
# shared texture, render height and chunk instead of one draw per edge tile.
static func build_transitions(cells:Array[Dictionary])->Array[Dictionary]:
	var builders:Dictionary={}
	for cell in cells:
		var tile:Vector2i=cell.tile
		var chunk:=Vector2i(floori(float(tile.x)/CHUNK_SIZE),floori(float(tile.y)/CHUNK_SIZE))
		var texture:Texture2D=cell.texture
		var key:="%d_%d_%d_%d"%[chunk.x,chunk.y,texture.get_instance_id(),int(cell.priority)]
		if not builders.has(key):
			var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			builders[key]={"texture":texture,"surface":surface,"chunk":chunk,"cells":[],"operation_count":0}
		var batch:Dictionary=builders[key]
		var rect:Rect2=cell.rect
		_append_plane(batch.surface,rect,0.405+float(cell.priority)*0.002)
		batch.cells.append({"tile":tile,"rect":rect,"priority":cell.priority,"patches":cell.get("patches",[])})
		batch.operation_count+=cell.get("patches",[]).size()
	var result:Array[Dictionary]=[]
	for batch in builders.values():
		result.append({"texture":batch.texture,"mesh":batch.surface.commit(),"chunk":batch.chunk,"cells":batch.cells,"operation_count":batch.operation_count})
	return result

static func _append_plane(surface:SurfaceTool,rect:Rect2,height:float)->void:
	var plane:=PlaneMesh.new();plane.size=rect.size
	var transform:=Transform3D(Basis.IDENTITY,Vector3(rect.get_center().x,height,rect.get_center().y))
	surface.append_from(plane,0,transform)
