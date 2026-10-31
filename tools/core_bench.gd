extends SceneTree
## Замер нового ядра (native/, Rust): клетки карты и земля на них, поиск пути
## в Rust и в GDScript (цена клетки — по её местности), путники со встречами,
## цена вызова GDScript → Rust.
##   native/build.sh && godot --headless --path . -s tools/core_bench.gd

func _astar_gd(nb: PackedInt32Array, cost: PackedFloat32Array, cols: int, a: int, b: int) -> int:
	var n := cost.size()
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(1e30)
	var closed := PackedByteArray()
	closed.resize(n)
	var hf := PackedFloat32Array()
	var hc := PackedInt32Array()
	g[a] = 0.0
	hf.append(0.0)
	hc.append(a)
	var bc := b % cols
	var br := b / cols
	var bx := bc - (br - (br & 1)) / 2
	var bz := -bx - br
	while hc.size() > 0:
		# достать минимум (двоичная куча)
		var cell := hc[0]
		var last := hc.size() - 1
		hf[0] = hf[last]
		hc[0] = hc[last]
		hf.resize(last)
		hc.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			if l >= hc.size():
				break
			var m := l
			if l + 1 < hc.size() and hf[l + 1] < hf[l]:
				m = l + 1
			if hf[m] >= hf[i]:
				break
			var tf := hf[i]; hf[i] = hf[m]; hf[m] = tf
			var tc := hc[i]; hc[i] = hc[m]; hc[m] = tc
			i = m
		if cell == b:
			return 1
		if closed[cell] == 1:
			continue
		closed[cell] = 1
		var gc := g[cell]
		for k in 6:
			var m := nb[cell * 6 + k]
			if m < 0:
				continue
			var ng := gc + (cost[cell] + cost[m]) * 0.5
			if ng < g[m]:
				g[m] = ng
				var mc := m % cols
				var mr := m / cols
				var mx := mc - (mr - (mr & 1)) / 2
				var mz := -mx - mr
				var h := maxi(maxi(absi(mx - bx), absi(mr - br)), absi(mz - bz))
				hf.append(ng + h)
				hc.append(m)
				var j := hc.size() - 1
				while j > 0:
					var p := (j - 1) / 2
					if hf[p] <= hf[j]:
						break
					var tf2 := hf[p]; hf[p] = hf[j]; hf[j] = tf2
					var tc2 := hc[p]; hc[p] = hc[j]; hc[j] = tc2
					j = p
	return 0


func _init() -> void:
	if not ClassDB.class_exists("CellMap"):
		print("ядро не загружено")
		quit()
		return
	var e := ToolCommon.engine(ToolCommon.args())
	var g := e.new_game("b1066", 1)
	var t0 := Time.get_ticks_usec()
	var land := Land.new(g)
	var cm: Object = land.core
	print("клетки: суши %d из %d (проходимых %d), областей суши %d; нарезка и раскладка земли %.1f мс" % [
		cm.cell_count() - Array(cm.terrain_bytes()).count(255), cm.cell_count(), cm.land_count(), cm.component_count(), (Time.get_ticks_usec() - t0) / 1000.0])
	var bp: Dictionary = cm.bench_paths(1000, 7)
	print("Rust A*: 1000 путей за %.1f мс (%.3f мс на путь, найдено %d, средняя длина %.0f клеток)" % [bp.ms, bp.ms / 1000.0, bp.found, bp.avg_len])
	var gr: Dictionary = cm.export_graph()
	var lands: PackedInt32Array = gr.land
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var t1 := Time.get_ticks_usec()
	var found := 0
	var N := 60
	var reach: Dictionary = {}
	for i in N:
		var a := lands[rng.randi() % lands.size()]
		var p: PackedInt32Array = cm.find_path(a, lands[rng.randi() % lands.size()])
		var b := lands[rng.randi() % lands.size()]
		# цель — в той же области суши (как в Rust)
		while cm.find_path(a, b).is_empty():
			b = lands[rng.randi() % lands.size()]
		reach[i] = [a, b]
	var t1b := Time.get_ticks_usec()
	for i in N:
		found += _astar_gd(gr.nb, gr.cost, int(gr.cols), reach[i][0], reach[i][1])
	t1 = t1b
	var gd_ms := (Time.get_ticks_usec() - t1) / 1000.0
	print("GDScript A*: %d путей за %.1f мс (%.2f мс на путь, найдено %d) — Rust быстрее в %.0f раз" % [N, gd_ms, gd_ms / N, found, (gd_ms / N) / (bp.ms / 1000.0)])
	var bm: Dictionary = cm.bench_movers(500, 365, 3.0, 11)
	print("путники: 500 × 365 дней за %.1f мс — путей %d, шагов %d, встреч %d" % [bm.ms, bm.paths, bm.moves, bm.encounters])
	var bm2: Dictionary = cm.bench_movers(3000, 365, 3.0, 11)
	print("путники: 3000 × 365 дней за %.1f мс — путей %d, шагов %d, встреч %d" % [bm2.ms, bm2.paths, bm2.moves, bm2.encounters])
	var t2 := Time.get_ticks_usec()
	var s := 0
	for i in 100000:
		s = cm.noop(s)
	print("вызов GDScript → Rust: %.2f мкс" % ((Time.get_ticks_usec() - t2) / 100000.0))
	quit()
