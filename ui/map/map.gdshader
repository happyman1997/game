// Карта: рельеф, море, раскраска режима карты, границы держав и провинций,
// оккупация, наведение и выделение. Всё считается по растру провинций
// (id_tex) и маленьким таблицам данных на каждую провинцию. Местность — по
// клеткам (cell_tex: шестиугольная сетка odd-r, как в ядре): цвета соседних
// клеток смешиваются, а вблизи у каждой местности свой узор (кроны, борозды,
// бочаги, пепел).
shader_type canvas_item;
render_mode blend_mix;

// Индекс провинции в пикселе: R + G*256, A = 1 — вода.
uniform sampler2D id_tex : filter_nearest, repeat_disable;
// Вода = 1 (с мип-уровнями — для мягких берегов и глубины моря).
uniform sampler2D land_tex : filter_linear_mipmap, repeat_disable;
// Бесшовный шум (рельеф, бумага, волны).
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// Таблицы по провинциям (ширина TW): местность, цвет режима, держава, флаги.
uniform sampler2D terrain_tex : filter_nearest; // rgb — цвет местности, a — высота
uniform sampler2D color_tex : filter_nearest;   // rgb — цвет режима, a — есть ли цвет
uniform sampler2D realm_tex : filter_nearest;   // rg — держава, ba — поддержава
uniform sampler2D flags_tex : filter_nearest;   // rgb — цвет оккупанта, a: 1 — оккупация, 0.5 — подсветка
// Клетки: r — местность (255 — нет), g — 1: здесь идут работы.
uniform sampler2D cell_tex : filter_nearest;
// Местности (по индексу): строка 0 — rgb цвет, a — высота; строка 1 — r: узор.
uniform sampler2D tt_tex : filter_nearest;
uniform float cell_size = 7.5;
uniform ivec2 cell_grid = ivec2(0, 0);

uniform int TW = 256;
uniform vec2 map_size = vec2(1400.0, 1300.0);
uniform vec2 rect_size = vec2(1600.0, 900.0);
uniform vec2 origin = vec2(0.0);   // точка карты в левом верхнем углу
uniform float zoom = 1.0;          // экранных пикселей на пиксель карты
uniform int hover_idx = -1;
uniform int sel_idx = -1;
uniform float overlay_strength = 1.0; // 1 — политическая раскраска, 0.4 — «прозрачная»
uniform float time = 0.0;
uniform float paper_bias = 0.0;    // +1 — всегда бумага, -1 — никогда

const vec3 PARCHMENT = vec3(0.86, 0.80, 0.66);
const vec3 INK = vec3(0.13, 0.09, 0.05);

int decode_id(vec4 c) {
	if (c.a > 0.5) return -1;
	return int(c.r * 255.0 + 0.5) + int(c.g * 255.0 + 0.5) * 256;
}

int prov_at(vec2 mp) {
	ivec2 ip = ivec2(floor(mp));
	if (ip.x < 0 || ip.y < 0 || float(ip.x) >= map_size.x || float(ip.y) >= map_size.y) return -1;
	return decode_id(texelFetch(id_tex, ip, 0));
}

ivec2 tcoord(int i) {
	return ivec2(i % TW, i / TW);
}

vec4 realm_info(int i) {
	if (i < 0) return vec4(1.0);
	return texelFetch(realm_tex, tcoord(i), 0);
}

float land_at(vec2 mp, float lod) {
	vec2 uv = mp / map_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return 0.0;
	return 1.0 - textureLod(land_tex, uv, lod).r;
}

float noise(vec2 p) {
	return texture(noise_tex, p).r;
}

// Клетка (столбец, строка) под точкой карты: шестиугольники «остриём вверх»,
// нечётные строки сдвинуты (odd-r).
ivec2 hex_at(vec2 p) {
	float q = (0.57735027 * p.x - 0.33333333 * p.y) / cell_size;
	float r = (0.66666667 * p.y) / cell_size;
	float x = q;
	float z = r;
	float y = -x - z;
	float rx = round(x);
	float ry = round(y);
	float rz = round(z);
	float dx = abs(rx - x);
	float dy = abs(ry - y);
	float dz = abs(rz - z);
	if (dx > dy && dx > dz) rx = -ry - rz;
	else if (dy > dz) ry = -rx - rz;
	else rz = -rx - ry;
	int row = int(rz);
	int col = int(rx) + (row - (row & 1)) / 2;
	return ivec2(col, row);
}

// Местность клетки (−1 — нет) и метка работ.
ivec2 cell_info(ivec2 cr) {
	if (cr.x < 0 || cr.y < 0 || cr.x >= cell_grid.x || cr.y >= cell_grid.y) return ivec2(-1, 0);
	vec4 c = texelFetch(cell_tex, cr, 0);
	int t = int(c.r * 255.0 + 0.5);
	return ivec2(t >= 255 ? -1 : t, int(c.g * 255.0 + 0.5));
}

float cell_hash(ivec2 cr) {
	return fract(sin(float(cr.x) * 12.9898 + float(cr.y) * 78.233) * 43758.5453);
}

// Узор местности вблизи: 1 — лес, 2 — дремучий, 3 — пашня, 4 — трава,
// 5 — топь, 6 — пепел, 7 — пни, 8 — вереск.
vec3 land_pattern(vec3 col, int pat, vec2 mp, ivec2 cr, float detail) {
	if (detail <= 0.0 || pat == 0) return col;
	if (pat == 1 || pat == 2) {
		float n = noise(mp / (pat == 2 ? 1.9 : 2.4) + 0.13);
		float crown = smoothstep(pat == 2 ? 0.42 : 0.5, pat == 2 ? 0.55 : 0.63, n);
		col *= mix(1.0, pat == 2 ? 0.66 : 0.76, crown * detail);
		col += vec3(0.03, 0.05, 0.02) * smoothstep(0.72, 0.8, n) * detail;
	} else if (pat == 3) {
		// наделы: полосы вдоль борозд; направление — одно из трёх, по
		// неровным пятнам шума (границы пятен не совпадают с клетками)
		float sel = noise(mp / 26.0 + 0.21);
		float a = sel < 0.42 ? 0.35 : (sel < 0.58 ? 1.4 : 2.45);
		vec2 dir = vec2(cos(a), sin(a));
		vec2 perp = vec2(-dir.y, dir.x);
		float u = dot(mp, dir) / 3.2;
		float v = dot(mp, perp) / 7.0;
		vec2 parcel = floor(vec2(u, v));
		float h = fract(sin(dot(parcel, vec2(12.9898, 78.233)) + a) * 43758.5453);
		float edge = 1.0 - smoothstep(0.0, 0.07, min(fract(u), 1.0 - fract(u)));
		float furrow = 0.5 + 0.5 * sin(dot(mp, dir) * 3.1);
		col *= 1.0 + ((h - 0.5) * 0.16 - furrow * 0.04 - edge * 0.08) * detail;
	} else if (pat == 4) {
		col *= 1.0 + (noise(mp / 1.7) - 0.5) * 0.12 * detail;
	} else if (pat == 5) {
		float n = noise(mp / 2.8 + 0.31);
		col = mix(col, vec3(0.30, 0.45, 0.50), smoothstep(0.6, 0.66, n) * 0.6 * detail);
		col *= 1.0 + (noise(mp / 1.3) - 0.5) * 0.1 * detail;
	} else if (pat == 6) {
		float n = noise(mp / 1.6 + 0.57);
		col *= mix(1.0, 0.55, smoothstep(0.58, 0.66, n) * detail);
	} else if (pat == 7) {
		vec2 g = fract(mp / 2.2 + cell_hash(cr)) - 0.5;
		col = mix(col, vec3(0.42, 0.32, 0.2), (1.0 - smoothstep(0.08, 0.16, length(g))) * 0.6 * detail);
	} else if (pat == 8) {
		float n = noise(mp / 1.5 + 0.77);
		col = mix(col, vec3(0.55, 0.42, 0.55), smoothstep(0.62, 0.7, n) * 0.35 * detail);
	}
	return col;
}

// Высота рельефа: крупные холмы + мелкая фактура, горы — гребнями.
float height_at(vec2 mp, float rough) {
	float n1 = noise(mp / 230.0);
	float n2 = noise(mp / 75.0 + 0.37);
	float n3 = noise(mp / 24.0 + 0.71);
	float ridge = 1.0 - abs(n2 * 2.0 - 1.0);
	float h = n1 * 0.55 + n2 * 0.3 + n3 * 0.1;
	h += ridge * ridge * smoothstep(0.35, 0.9, rough) * 0.8;
	return h * (0.2 + rough * 1.4);
}

void fragment() {
	vec2 local = UV * rect_size;
	vec2 mp = origin + local / zoom;
	float px = 1.0 / zoom; // один экранный пиксель в пикселях карты
	int idx = prov_at(mp);
	// Сглаженный берег: при приближении сушу/воду определяет билинейная маска.
	float water_s = 1.0;
	{
		vec2 uv0 = mp / map_size;
		if (uv0.x >= 0.0 && uv0.y >= 0.0 && uv0.x <= 1.0 && uv0.y <= 1.0) water_s = textureLod(land_tex, uv0, clamp(zoom * 0.25, 0.0, 1.0)).r;
	}
	if (zoom > 1.3) {
		if (water_s > 0.5) idx = -1;
		else if (idx < 0) {
			idx = prov_at(mp + vec2(1.0, 0.0));
			if (idx < 0) idx = prov_at(mp - vec2(1.0, 0.0));
			if (idx < 0) idx = prov_at(mp + vec2(0.0, 1.0));
			if (idx < 0) idx = prov_at(mp - vec2(0.0, 1.0));
		}
	}
	float coast_line = 1.0 - smoothstep(0.6, 1.6, abs(water_s - 0.5) / max(fwidth(water_s), 1e-4));
	// «Бумажная» карта при отдалении, как в CK3.
	float paper = clamp(1.0 - smoothstep(0.55, 1.15, zoom) + paper_bias, 0.0, 1.0);
	float grain = noise(mp / 9.0) * 0.6 + noise(mp / 37.0) * 0.4;

	vec3 col;
	if (idx < 0) {
		// ---------------- море
		float l1 = land_at(mp, 1.5);
		float l3 = land_at(mp, 3.5);
		float l5 = land_at(mp, 5.5);
		float near = clamp(l3 * 1.6 + l5 * 1.2, 0.0, 1.0);
		vec3 deep = vec3(0.11, 0.22, 0.31);
		vec3 shallow = vec3(0.25, 0.43, 0.50);
		col = mix(deep, shallow, smoothstep(0.0, 0.85, near));
		float waves = noise(mp / 60.0 + vec2(time * 0.004, time * 0.002)) * 0.6 + noise(mp / 17.0 - vec2(time * 0.006, 0.0)) * 0.4;
		col *= 0.9 + waves * 0.2;
		// мягкая светлая кромка у берега
		col = mix(col, vec3(0.55, 0.66, 0.66), smoothstep(0.08, 0.5, l1) * 0.45);
		// бумажный вид: приглушённое море с контурами вдоль берега
		vec3 pcol = mix(vec3(0.42, 0.53, 0.55), vec3(0.58, 0.66, 0.64), near) * (0.93 + grain * 0.1);
		float lv = l5 * 1.4 + l3 * 0.6;
		float contour = 0.0;
		for (int k = 1; k <= 3; k++) {
			float level = 0.07 * float(k);
			float d = abs(lv - level) / max(fwidth(lv), 1e-4);
			contour = max(contour, (1.0 - clamp(d - 0.3, 0.0, 1.0)) * (1.0 - float(k) * 0.22));
		}
		pcol = mix(pcol, INK * 1.4, contour * 0.35);
		col = mix(col, pcol, paper);
		if (zoom > 1.3) col = mix(col, INK * 1.3, coast_line * 0.8);
	} else {
		// ---------------- суша
		vec4 tinfo = texelFetch(terrain_tex, tcoord(idx), 0);
		bool waste = tinfo.a > 0.99;
		// местность по клеткам: смешиваем соседние клетки (со сдвигом шумом —
		// края пятен живые, без шестиугольников)
		vec2 warp = (vec2(noise(mp / 31.0), noise(mp / 31.0 + 0.5)) - 0.5) * cell_size * 1.7;
		vec2 q = mp + warp;
		ivec2 ccr = hex_at(q);
		ivec2 cinf = cell_info(ccr);
		vec3 tcol = vec3(0.0);
		float rough = 0.0;
		float wsum = 0.0;
		if (cinf.x >= 0) {
			vec4 tt = texelFetch(tt_tex, ivec2(cinf.x, 0), 0);
			tcol += tt.rgb * 2.0;
			rough += tt.a * 2.0;
			wsum += 2.0;
		}
		for (int k = 0; k < 6; k++) {
			float a = float(k) * 1.0472 + 0.5236;
			ivec2 ci = cell_info(hex_at(q + vec2(cos(a), sin(a)) * cell_size * 0.75));
			if (ci.x >= 0) {
				vec4 tt = texelFetch(tt_tex, ivec2(ci.x, 0), 0);
				tcol += tt.rgb;
				rough += tt.a;
				wsum += 1.0;
			}
		}
		if (wsum > 0.0) {
			tcol /= wsum;
			rough /= wsum;
		} else {
			tcol = tinfo.rgb;
			rough = tinfo.a;
		}
		if (waste) rough = 0.45;
		// отмывка рельефа
		float e = 0.75;
		float h0 = height_at(mp, rough);
		float hx = height_at(mp + vec2(e, 0.0), rough);
		float hy = height_at(mp + vec2(0.0, e), rough);
		vec2 grad = vec2(hx - h0, hy - h0) / e;
		float shade = clamp(1.0 - (grad.x + grad.y) * 3.2, 0.62, 1.3);
		vec3 terrain = tcol * (0.92 + noise(mp / 40.0) * 0.16) * shade;
		// вблизи — узор местности клетки и штриховка работ
		float detail = smoothstep(1.1, 2.6, zoom);
		if (cinf.x >= 0 && !waste) {
			int pat = int(texelFetch(tt_tex, ivec2(cinf.x, 1), 0).r * 255.0 + 0.5);
			terrain = land_pattern(terrain, pat, mp, ccr, detail);
			if (cinf.y == 1) {
				float hatch = step(0.62, fract((mp.x + mp.y) / (3.2 * max(1.0, px))));
				terrain = mix(terrain, vec3(0.96, 0.84, 0.5) * shade, hatch * (0.22 + 0.1 * sin(time * 2.0)) * smoothstep(0.7, 1.4, zoom));
			}
		}
		if (waste) {
			shade = mix(1.0, shade, 0.45);
			// непроходимые земли: тёмные, приглушённые, со штриховкой
			float hatch = smoothstep(0.35, 0.5, abs(fract((mp.x - mp.y) / (5.0 * max(1.0, px))) - 0.5));
			terrain = mix(vec3(0.33, 0.30, 0.27), vec3(0.45, 0.41, 0.36), noise(mp / 60.0)) * shade * (0.9 + hatch * 0.1);
		}
		// светлая полоса пляжа у воды
		float water_near = 1.0 - land_at(mp, 1.0);
		terrain = mix(terrain, vec3(0.80, 0.74, 0.55) * shade, smoothstep(0.15, 0.6, water_near) * 0.35);

		vec4 mc = texelFetch(color_tex, tcoord(idx), 0);
		vec3 land = terrain;
		if (mc.a > 0.01) {
			vec3 tint = mc.rgb * mix(0.72, 1.0, clamp(shade, 0.0, 1.2) - 0.2);
			land = mix(terrain, tint, overlay_strength * mc.a * mix(0.84, 0.5, smoothstep(1.6, 4.5, zoom)));
		}
		// бумажный вид: пергамент + акварельная заливка режима
		vec3 pl = PARCHMENT * (0.9 + grain * 0.14);
		if (mc.a > 0.01) pl = mix(pl, mc.rgb * (0.92 + grain * 0.12), 0.78 * mc.a * max(overlay_strength, 0.6));
		pl *= mix(1.0, shade, 0.18);
		if (waste) {
			float hatch = 1.0 - smoothstep(0.08, 0.16, abs(fract((mp.x - mp.y) / (6.0 * max(1.0, px))) - 0.5));
			pl = mix(PARCHMENT * 0.72 * (0.92 + grain * 0.1), INK, hatch * 0.25);
		}
		col = mix(land, pl, paper);

		// оккупация — диагональные полосы цвета захватчика; подсветка
		vec4 fl = texelFetch(flags_tex, tcoord(idx), 0);
		if (fl.a > 0.75) {
			float stripe = step(0.55, fract((mp.x + mp.y) / (7.0 * max(1.0, px * 2.0))));
			col = mix(col, fl.rgb * shade, stripe * 0.75);
		} else if (fl.a > 0.25) {
			float stripe = step(0.6, fract((mp.x - mp.y) / (6.0 * max(1.0, px * 2.0))));
			col = mix(col, vec3(1.0, 0.92, 0.6), stripe * 0.35);
		}

		// ---------------- границы
		vec4 my_realm = realm_info(idx);
		float d_prov = 99.0;
		float d_realm = 99.0;
		float d_sub = 99.0;
		float d_coast = 99.0;
		for (int ring = 1; ring <= 4; ring++) {
			float r = float(ring) * px * 0.9;
			for (int k = 0; k < 8; k++) {
				float a = float(k) * 0.7854;
				vec2 off = vec2(cos(a), sin(a)) * r;
				int j = prov_at(mp + off);
				if (j == idx) continue;
				float dpx = float(ring) * 0.9;
				if (j < 0) {
					d_coast = min(d_coast, dpx);
					continue;
				}
				d_prov = min(d_prov, dpx);
				vec4 ri = realm_info(j);
				if (distance(ri.rg, my_realm.rg) > 0.001) d_realm = min(d_realm, dpx);
				else if (distance(ri.ba, my_realm.ba) > 0.001) d_sub = min(d_sub, dpx);
			}
		}
		// граница провинции: тонкая, видна при приближении
		float prov_vis = waste ? 0.0 : smoothstep(0.7, 1.6, zoom) * 0.38 + paper * 0.12;
		col = mix(col, INK, (1.0 - smoothstep(0.6, 1.3, d_prov)) * prov_vis);
		// граница вассальной державы
		col = mix(col, INK, (1.0 - smoothstep(1.0, 1.9, d_sub)) * 0.55);
		// граница державы: тёмная линия + светлая кайма цвета державы
		if (d_realm < 90.0) {
			float line = 1.0 - smoothstep(1.4, 2.4, d_realm);
			float glow = (1.0 - smoothstep(2.0, 3.8, d_realm)) * (1.0 - line);
			vec3 light = mix(col, (mc.a > 0.01 ? mc.rgb : col) * 1.35 + 0.08, 0.6);
			col = mix(col, light, glow * 0.7);
			col = mix(col, INK * 0.7, line * 0.9);
		}
		// береговая линия
		if (zoom > 1.3) col = mix(col, INK * 1.3, coast_line * 0.8);
		else col = mix(col, INK * 1.3, (1.0 - smoothstep(0.8, 1.6, d_coast)) * 0.75);

		// наведение и выделение
		if (idx == hover_idx) {
			col = mix(col, vec3(1.0, 0.97, 0.88), 0.14);
			col = mix(col, vec3(1.0, 0.95, 0.75), (1.0 - smoothstep(1.0, 2.0, d_prov)) * 0.55);
		}
		if (idx == sel_idx) {
			col = mix(col, vec3(1.0, 0.96, 0.82), 0.18 + 0.05 * sin(time * 3.0));
			col = mix(col, vec3(1.0, 0.86, 0.45), 1.0 - smoothstep(1.4, 3.2, d_prov));
		}
	}

	// за краями карты — тёмный фон
	vec2 outside = max(max(-mp, mp - map_size), vec2(0.0));
	float edge = max(outside.x, outside.y) * zoom;
	col = mix(col, vec3(0.07, 0.07, 0.07), smoothstep(0.0, 260.0, edge) * 0.6);
	// виньетка
	vec2 v = UV - 0.5;
	col *= 1.0 - 0.32 * pow(clamp(length(v * vec2(1.0, rect_size.y / rect_size.x)) * 1.35, 0.0, 1.0), 2.4);
	COLOR = vec4(col, 1.0);
}
