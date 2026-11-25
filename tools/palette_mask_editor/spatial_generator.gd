extends RefCounted
# Pure predictor: labels is a cropped training frame, never the full reference.
# Landmarks are paired frame-local pixel coordinates: [source_point,target_point].
static func predict(art: Image, labels: Image, target: Image, tolerance: float, landmarks: Array = []) -> Dictionary:
	var w := target.get_width()
	var h := target.get_height()
	var result := Image.create(w,h,false,Image.FORMAT_RGB8)
	var pending := PackedByteArray(); pending.resize(w*h); pending.fill(1)
	var classes := PackedByteArray(); classes.resize(w*h); classes.fill(2)
	var palette := [Color.RED,Color.GREEN,Color.BLACK,Color.WHITE]
	var source_size := Vector2(art.get_size())
	var target_size := Vector2(target.get_size())
	for y in h:
		for x in w:
			var i := y*w+x
			var pixel := target.get_pixel(x,y)
			if pixel.a == 0: classes[i] = 3; pending[i] = 0; continue
			var uv := (Vector2(x,y)+Vector2(0.5,0.5))/target_size
			var offset := Vector2.ZERO
			var weight_sum := 0.0
			for pair in landmarks:
				var src_uv: Vector2 = (Vector2(pair[0])+Vector2(0.5,0.5))/source_size
				var dst_uv: Vector2 = (Vector2(pair[1])+Vector2(0.5,0.5))/target_size
				var weight := 1.0/maxf(0.0001,uv.distance_squared_to(dst_uv))
				offset += (src_uv-dst_uv)*weight; weight_sum += weight
			if weight_sum > 0: uv += offset/weight_sum
			var center := Vector2i((uv*source_size).floor())
			var votes := [0.0,0.0,0.0,0.0]
			# A bounded spatial neighborhood prevents global RGB conflation.
			for dy in range(-6,7):
				for dx in range(-6,7):
					var q := center+Vector2i(dx,dy)
					if not Rect2i(Vector2i.ZERO,art.get_size()).has_point(q): continue
					var original := art.get_pixelv(q)
					if original.a == 0: continue
					var distance := Vector3(pixel.r-original.r,pixel.g-original.g,pixel.b-original.b).length()*255.0
					if distance > tolerance: continue
					var label_color := labels.get_pixelv(q)
					var category := palette.find(Color(label_color.r,label_color.g,label_color.b,1))
					if category < 0: continue
					votes[category] += 1.0/((1.0+distance)*(1.0+0.2*(dx*dx+dy*dy)))
			var best := 2
			var total := 0.0
			for c in 4:
				total += votes[c]
				if votes[c] > votes[best]: best = c
			classes[i] = best
			if total > 0 and votes[best]/total >= 0.9: pending[i] = 0
	# Refine only within four-connected exact-RGB source regions. Conflicting
	# spatial evidence prevents region propagation; disconnected colors never join.
	var visited := PackedByteArray(); visited.resize(w*h)
	for seed in w*h:
		if visited[seed]: continue
		var seed_point := Vector2i(seed%w,seed/w)
		var seed_color := target.get_pixelv(seed_point)
		var todo: Array[int] = [seed]
		var component: Array[int] = []
		var counts := [0,0,0,0]
		visited[seed] = 1
		while not todo.is_empty():
			var i: int = todo.pop_back()
			component.append(i)
			if pending[i] == 0: counts[classes[i]] += 1
			var p := Vector2i(i%w,i/w)
			for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var q: Vector2i = p+delta
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h: continue
				var j: int = q.y*w+q.x
				if not visited[j] and target.get_pixelv(q) == seed_color:
					visited[j] = 1; todo.append(j)
		var agreed := -1
		var conflict := false
		for c in 4:
			if counts[c] > 0:
				if agreed >= 0: conflict = true
				agreed = c
		if not conflict and agreed >= 0 and counts[agreed] >= 2:
			for i in component: classes[i] = agreed; pending[i] = 0
		# Conflicts block propagation; retain each pixel's independent local evidence.
	for y in h:
		for x in w: result.set_pixel(x,y,palette[classes[y*w+x]])
	return {"mask":result,"uncertain":pending}


