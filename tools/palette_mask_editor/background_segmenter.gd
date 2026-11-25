extends RefCounted
# Independent source-only segmentation. No mask or semantic labels are inputs.
# states: 0 = no background evidence, 1 = background, 2 = enclosed candidate.
static func segment(image: Image) -> Dictionary:
	var w := image.get_width()
	var h := image.get_height()
	var states := PackedByteArray(); states.resize(w*h)
	var transparent := 0
	for y in h:
		for x in w:
			if image.get_pixel(x,y).a == 0:
				states[y*w+x] = 1; transparent += 1
	if transparent > 0:
		return {"states":states,"mode":"alpha","border_fraction":0.0,"transparent":transparent}
	var histogram := {}
	var border_count := 0
	for y in h:
		for x in w:
			if x != 0 and y != 0 and x != w-1 and y != h-1: continue
			var key := image.get_pixel(x,y).to_rgba32()
			histogram[key] = histogram.get(key,0)+1; border_count += 1
	var dominant := 0
	for key in histogram:
		if histogram[key] > histogram.get(dominant,0): dominant = key
	var fraction: float = float(histogram.get(dominant,0))/maxi(1,border_count)
	# Refuse a background guess when border evidence is not dominant.
	if fraction < 0.6: return {"states":states,"mode":"opaque_no_dominant_border","border_fraction":fraction,"transparent":0}
	var candidate := PackedByteArray(); candidate.resize(w*h)
	var todo: Array[int] = []
	for y in h:
		for x in w:
			var i := y*w+x
			# Exact color deliberately avoids antialias tolerance leaking into artwork.
			if image.get_pixel(x,y).to_rgba32() == dominant:
				candidate[i] = 1
				states[i] = 2
				if x == 0 or y == 0 or x == w-1 or y == h-1:
					states[i] = 1; todo.append(i)
	while not todo.is_empty():
		var i: int = todo.pop_back()
		var p := Vector2i(i%w,i/w)
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var q: Vector2i = p+delta
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h: continue
			var j := q.y*w+q.x
			if candidate[j] and states[j] != 1:
				states[j] = 1; todo.append(j)
	return {"states":states,"mode":"opaque_exterior_exact","border_fraction":fraction,"transparent":0,"border_rgba":dominant}
