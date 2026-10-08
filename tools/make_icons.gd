extends SceneTree
## Растеризует assets/icon.svg в PNG нужных размеров и собирает icon.ico
## (Windows) и icon_1024.png (macOS). Запуск:
##   godot --headless --path . -s tools/make_icons.gd


func _init() -> void:
	var svg := FileAccess.get_file_as_string("res://assets/icon.svg")
	var sizes := [256, 128, 64, 48, 32, 16]
	var pngs: Array[PackedByteArray] = []
	for s in sizes:
		var img := Image.new()
		img.load_svg_from_string(svg, s / 256.0)
		pngs.append(img.save_png_to_buffer())
	var big := Image.new()
	big.load_svg_from_string(svg, 1024 / 256.0)
	big.save_png("res://assets/icon_1024.png")
	# ICO с PNG внутри (поддерживается начиная с Windows Vista).
	var ico := PackedByteArray()
	ico.append_array(_u16(0))
	ico.append_array(_u16(1))
	ico.append_array(_u16(sizes.size()))
	var offset := 6 + 16 * sizes.size()
	for i in sizes.size():
		var s: int = sizes[i]
		ico.append(s % 256)
		ico.append(s % 256)
		ico.append(0)
		ico.append(0)
		ico.append_array(_u16(1))
		ico.append_array(_u16(32))
		ico.append_array(_u32(pngs[i].size()))
		ico.append_array(_u32(offset))
		offset += pngs[i].size()
	for p in pngs:
		ico.append_array(p)
	var f := FileAccess.open("res://assets/icon.ico", FileAccess.WRITE)
	f.store_buffer(ico)
	f.close()
	print("icon.ico и icon_1024.png готовы")
	quit()


func _u16(v: int) -> PackedByteArray:
	return PackedByteArray([v & 255, (v >> 8) & 255])


func _u32(v: int) -> PackedByteArray:
	return PackedByteArray([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255])
