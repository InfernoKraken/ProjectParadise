extends RefCounted

# Four-connected flood fill; only complete grid cells inside the map are eligible.
static func empty_region(start:Vector2i,bounds:Rect2,occupied:Dictionary)->Array[Vector2i]:
	var result:Array[Vector2i]=[]
	var low:=Vector2i(ceili(bounds.position.x+0.5),ceili(bounds.position.y+0.5))
	var high:=Vector2i(floori(bounds.end.x-0.5),floori(bounds.end.y-0.5))
	var seen:=occupied.duplicate()
	var pending:Array[Vector2i]=[start]
	var cursor:=0
	while cursor<pending.size():
		var cell:=pending[cursor];cursor+=1
		if cell.x<low.x or cell.y<low.y or cell.x>high.x or cell.y>high.y or seen.has(cell):continue
		seen[cell]=true;result.append(cell)
		for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			pending.append(cell+step)
	return result
