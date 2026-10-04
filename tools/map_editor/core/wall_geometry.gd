class_name WallGeometry
extends RefCounted

# One authored filler interval in wall/grid space. This is geometry metadata,
# deliberately independent of texture pixel dimensions.
const MIN_FILLER_SPAN := 2.0

static func segment_is_cardinal(a:Vector2,b:Vector2)->bool:
	var delta:=b-a
	return is_zero_approx(delta.x) != is_zero_approx(delta.y)

static func segment_is_valid(a:Vector2,b:Vector2)->bool:
	if not segment_is_cardinal(a,b):return false
	var interval_count:=a.distance_to(b)/MIN_FILLER_SPAN
	return interval_count+0.0001>=1.0 and is_equal_approx(interval_count,roundf(interval_count))

static func invalid_segment_count(serialized_points:Array)->int:
	var invalid:=0
	for index in range(1,serialized_points.size()):
		var previous:Variant=serialized_points[index-1];var current:Variant=serialized_points[index]
		if not previous is Array or not current is Array or previous.size()<2 or current.size()<2:
			invalid+=1;continue
		if not segment_is_valid(Vector2(float(previous[0]),float(previous[1])),Vector2(float(current[0]),float(current[1]))):invalid+=1
	return invalid

static func normalize_points(serialized_points:Array)->Dictionary:
	var points:Array[Vector2]=[]
	for value:Variant in serialized_points:
		if value is Array and value.size()>=2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float):
			points.append(Vector2(float(value[0]),float(value[1])))
	var changed:=points.size()!=serialized_points.size();var searching:=true
	if not points.is_empty():
		var lattice_origin:=points[0]
		for index in range(1,points.size()):
			var snapped:=lattice_origin+Vector2(snappedf(points[index].x-lattice_origin.x,MIN_FILLER_SPAN),snappedf(points[index].y-lattice_origin.y,MIN_FILLER_SPAN))
			if not snapped.is_equal_approx(points[index]):points[index]=snapped;changed=true
	while searching and points.size()>2:
		searching=false
		for index in range(1,points.size()):
			var delta:=points[index]-points[index-1]
			if delta.length_squared()<0.0001:
				points.remove_at(index if index<points.size()-1 else index-1);changed=true;searching=true;break
			if segment_is_valid(points[index-1],points[index]):continue
			if not segment_is_cardinal(points[index-1],points[index]):continue
			# Remove only an anchor participating in the invalid short run, and only
			# when its two neighboring runs continue collinearly in the same direction.
			if index<points.size()-1 and _same_directed_line(delta,points[index+1]-points[index]) and segment_is_valid(points[index-1],points[index+1]):
				points.remove_at(index);changed=true;searching=true;break
			if index>=2 and _same_directed_line(points[index-1]-points[index-2],delta) and segment_is_valid(points[index-2],points[index]):
				points.remove_at(index-1);changed=true;searching=true;break
	var output:Array=[]
	for point in points:output.append([point.x,point.y])
	var valid:=points.size()>=2
	for index in range(1,points.size()):valid=valid and segment_is_valid(points[index-1],points[index])
	return {"points":output,"changed":changed,"valid":valid}

static func _same_directed_line(first:Vector2,second:Vector2)->bool:
	if first.length_squared()<0.0001 or second.length_squared()<0.0001:return false
	var same_axis:=(is_zero_approx(first.x) and is_zero_approx(second.x)) or (is_zero_approx(first.y) and is_zero_approx(second.y))
	return same_axis and first.dot(second)>0.0
