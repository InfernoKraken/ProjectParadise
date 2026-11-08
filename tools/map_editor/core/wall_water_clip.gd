extends RefCounted

static func regions(cell:Vector2i,grid:Dictionary,walls:Array)->Array[Rect2]:
	var full:=Rect2(Vector2(cell)-Vector2.ONE*0.5,Vector2.ONE)
	var halves:Array[Rect2]=[]
	for wall:Variant in walls:
		if not wall is Dictionary:continue
		var points:Array=wall.get("points",[])
		for index in range(1,points.size()):
			if wall.get("disabled_segments",[]).has(index-1):continue
			var piece:=bounds(cell,grid,[{"type":wall.get("type",""),"points":[points[index-1],points[index]]}])
			if piece!=full and not halves.has(piece):halves.append(piece)
	var neighbors:=0
	for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if grid.get(cell+offset,"")=="water":neighbors+=1
	if halves.size()==2 and neighbors>=3:
		var a:=halves[0];var b:=halves[1]
		if (a.size.x<1.0 and b.size.y<1.0) or (a.size.y<1.0 and b.size.x<1.0):
			# Union of perpendicular water halves, represented by two disjoint
			# rectangles. The missing quarter is the land side of the corner.
			if a.size.x<1.0:
				b.size.x=1.0-a.size.x;b.position.x=full.position.x if a.position.x>full.position.x else a.end.x
			else:
				b.size.y=1.0-a.size.y;b.position.y=full.position.y if a.position.y>full.position.y else a.end.y
			return [a,b]
	return [bounds(cell,grid,walls)]

# Shoreline decoration must not grow across a hard wall. Include endpoint
# footprints so the transition does not peek out underneath corner posts.
static func near_wall(cell:Vector2i,walls:Array)->bool:
	for wall:Variant in walls:
		if not wall is Dictionary or String(wall.get("type",""))!="wall.fence":continue
		var points:Array=wall.get("points",[]);var disabled:Array=wall.get("disabled_segments",[])
		for index in range(1,points.size()):
			if disabled.has(index-1):continue
			var a:=Vector2(float(points[index-1][0]),float(points[index-1][1]));var b:=Vector2(float(points[index][0]),float(points[index][1]))
			if not is_equal_approx(a.x,b.x) and not is_equal_approx(a.y,b.y):continue
			if Vector2(cell).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(cell),a,b))<=1.5:return true
	return false

# Derived visual bounds only; authored terrain and swimming identity stay intact.
static func bounds(cell:Vector2i,grid:Dictionary,walls:Array)->Rect2:
	var result:=Rect2(Vector2(cell)-Vector2.ONE*0.5,Vector2.ONE)
	for wall:Variant in walls:
		if not wall is Dictionary or String(wall.get("type",""))!="wall.fence":continue
		var points:Array=wall.get("points",[]);var disabled:Array=wall.get("disabled_segments",[])
		for index in range(1,points.size()):
			if disabled.has(index-1):continue
			var a:=Vector2(float(points[index-1][0]),float(points[index-1][1]));var b:=Vector2(float(points[index][0]),float(points[index][1]))
			if is_equal_approx(a.x,b.x) and a.x>result.position.x and a.x<result.end.x and float(cell.y)+0.5>=minf(a.y,b.y) and float(cell.y)-0.5<=maxf(a.y,b.y):
				var west:bool=grid.get(cell+Vector2i.LEFT,"")=="water";var east:bool=grid.get(cell+Vector2i.RIGHT,"")=="water"
				if west==east:
					# At a corner the perpendicular run can put water on both
					# sides of this tile. Sample one tile into this run instead.
					var inward:=Vector2i(0,1 if (a.y+b.y)*0.5>float(cell.y) else -1)
					west=grid.get(cell+inward+Vector2i.LEFT,"")=="water";east=grid.get(cell+inward+Vector2i.RIGHT,"")=="water"
				if west==east:continue
				if west:result.size.x=a.x-result.position.x
				else:var end:=result.end;result.position.x=a.x;result.size=end-result.position
			elif is_equal_approx(a.y,b.y) and a.y>result.position.y and a.y<result.end.y and float(cell.x)+0.5>=minf(a.x,b.x) and float(cell.x)-0.5<=maxf(a.x,b.x):
				var north:bool=grid.get(cell+Vector2i.UP,"")=="water";var south:bool=grid.get(cell+Vector2i.DOWN,"")=="water"
				if north==south:
					var inward:=Vector2i(1 if (a.x+b.x)*0.5>float(cell.x) else -1,0)
					north=grid.get(cell+inward+Vector2i.UP,"")=="water";south=grid.get(cell+inward+Vector2i.DOWN,"")=="water"
				if north==south:continue
				if north:result.size.y=a.y-result.position.y
				else:var end:=result.end;result.position.y=a.y;result.size=end-result.position
	return result

# Fill only the dry remainder of fence-clipped water when that side borders
# sand. The original water cell identity remains authoritative for gameplay.
static func sand_regions(cell:Vector2i,grid:Dictionary,walls:Array)->Array[Rect2]:
	var full:=Rect2(Vector2(cell)-Vector2.ONE*0.5,Vector2.ONE)
	var dry:Array[Rect2]=[full]
	for water:Rect2 in regions(cell,grid,walls):
		var next:Array[Rect2]=[]
		for piece in dry:
			var cut:=piece.intersection(water)
			if not cut.has_area():next.append(piece);continue
			for rect in [Rect2(piece.position,Vector2(cut.position.x-piece.position.x,piece.size.y)),Rect2(Vector2(cut.end.x,piece.position.y),Vector2(piece.end.x-cut.end.x,piece.size.y)),Rect2(Vector2(cut.position.x,piece.position.y),Vector2(cut.size.x,cut.position.y-piece.position.y)),Rect2(Vector2(cut.position.x,cut.end.y),Vector2(cut.size.x,piece.end.y-cut.end.y))]:
				if rect.has_area():next.append(rect)
		dry=next
	var result:Array[Rect2]=[]
	for rect in dry:
		if (is_equal_approx(rect.end.x,full.end.x) and grid.get(cell+Vector2i.RIGHT,"")=="sand") or (is_equal_approx(rect.position.x,full.position.x) and grid.get(cell+Vector2i.LEFT,"")=="sand") or (is_equal_approx(rect.end.y,full.end.y) and grid.get(cell+Vector2i.DOWN,"")=="sand") or (is_equal_approx(rect.position.y,full.position.y) and grid.get(cell+Vector2i.UP,"")=="sand"):result.append(rect)
	return result
