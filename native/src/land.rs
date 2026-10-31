//! Земля по клеткам: местность каждой клетки, состав провинции, начальная
//! раскладка (возделанное — у селения, глушь — по краям), участки для работ
//! (растут от уже возделанной земли) и природа (зарастание идёт от опушек).
//!
//! Местность — индекс в списке местностей (его задаёт GDScript), NONE — вода.
//! Наборы местностей передаются битовой маской (местностей не больше 64).

use godot::prelude::*;

use crate::cells::{CellMap, NONE};
use crate::rng::Rng;

/// Плавный шум по точке (решётка со стороной scale пикселей), 0…1.
pub(crate) fn value_noise(seed: u64, x: f32, y: f32, scale: f32) -> f32 {
    let fx = x / scale;
    let fy = y / scale;
    let x0 = fx.floor();
    let y0 = fy.floor();
    let tx = fx - x0;
    let ty = fy - y0;
    let h = |ix: i64, iy: i64| -> f32 {
        let mut r = Rng::new(seed ^ (ix as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ (iy as u64).wrapping_mul(0xC2B2_AE3D_27D4_EB4F));
        (r.next_u64() >> 40) as f32 / (1u64 << 24) as f32
    };
    let (ix, iy) = (x0 as i64, y0 as i64);
    let (a, b, c, d) = (h(ix, iy), h(ix + 1, iy), h(ix, iy + 1), h(ix + 1, iy + 1));
    let sx = tx * tx * (3.0 - 2.0 * tx);
    let sy = ty * ty * (3.0 - 2.0 * ty);
    let ab = a + (b - a) * sx;
    let cd = c + (d - c) * sx;
    ab + (cd - ab) * sy
}

fn in_mask(mask: i64, t: u8) -> bool {
    t != NONE && t < 64 && (mask >> t) & 1 == 1
}

fn unit(rng: &mut Rng) -> f32 {
    (rng.next_u64() >> 40) as f32 / (1u64 << 24) as f32
}

impl CellMap {
    fn cells_of(&self, p: i32) -> &[i32] {
        if p < 0 || p as usize >= self.owned.len() {
            return &[];
        }
        &self.owned[p as usize]
    }

    /// Сколько соседей клетки — с местностью из маски.
    fn near_count(&self, c: i32, mask: i64) -> i32 {
        self.adj[c as usize].iter().filter(|&&m| m >= 0 && in_mask(mask, self.terr[m as usize])).count() as i32
    }
}

#[godot_api(secondary)]
impl CellMap {
    /// Цена пути по местностям (индекс — местность); пересчитать цены клеток.
    #[func]
    fn set_moves(&mut self, moves: PackedFloat32Array) {
        self.moves = moves.as_slice().to_vec();
        for i in 0..self.n() {
            if self.prov[i] >= 0 {
                self.refresh_cost(i);
            }
        }
    }

    /// Местность клетки (−1 — вода).
    #[func]
    fn terrain_at(&self, cell: i32) -> i32 {
        match self.terr.get(cell as usize) {
            Some(&t) if t != NONE => t as i32,
            _ => -1,
        }
    }

    /// Местность всех клеток (для сохранения и отрисовки).
    #[func]
    fn terrain_bytes(&self) -> PackedByteArray {
        PackedByteArray::from(self.terr.as_slice())
    }

    /// Загрузить местность всех клеток (из сохранения); false — не та сетка.
    #[func]
    fn load_terrain(&mut self, bytes: PackedByteArray) -> bool {
        let b = bytes.as_slice();
        if b.len() != self.n() {
            return false;
        }
        for i in 0..self.n() {
            self.terr[i] = if self.prov[i] >= 0 { b[i] } else { NONE };
            if self.prov[i] >= 0 {
                self.refresh_cost(i);
            }
        }
        true
    }

    /// Сменить местность клеток; возвращает, сколько изменилось.
    #[func]
    fn set_cells(&mut self, cells: PackedInt32Array, t: i32) -> i32 {
        let t = if (0..255).contains(&t) { t as u8 } else { return 0 };
        let mut n = 0;
        for &c in cells.as_slice() {
            let i = c as usize;
            if c < 0 || i >= self.n() || self.prov[i] < 0 || self.terr[i] == t {
                continue;
            }
            self.terr[i] = t;
            self.refresh_cost(i);
            n += 1;
        }
        n
    }

    #[func]
    fn province_cells(&self, p: i32) -> PackedInt32Array {
        PackedInt32Array::from(self.cells_of(p))
    }

    /// Сколько клеток каждой местности в провинции (nt — число местностей).
    #[func]
    fn province_counts(&self, p: i32, nt: i32) -> PackedInt32Array {
        let mut out = vec![0i32; nt.max(0) as usize];
        for &c in self.cells_of(p) {
            let t = self.terr[c as usize] as usize;
            if t < out.len() {
                out[t] += 1;
            }
        }
        PackedInt32Array::from(out.as_slice())
    }

    /// Начальная раскладка провинции: terrains по порядку — от селения к
    /// краям, shares — их доли. Порядок клеток — расстояние до середины
    /// провинции с плавным шумом (поля — пятном у селения, лес — по краям и
    /// языками внутрь).
    #[func]
    fn seed_province(&mut self, p: i32, terrains: PackedInt32Array, shares: PackedFloat32Array, seed: i64) {
        let cells: Vec<i32> = self.cells_of(p).to_vec();
        let ts = terrains.as_slice();
        let sh = shares.as_slice();
        if cells.is_empty() || ts.is_empty() || ts.len() != sh.len() {
            return;
        }
        let (mut cx, mut cy) = (0.0f32, 0.0f32);
        for &c in cells.iter() {
            let (x, y) = self.center(c);
            cx += x;
            cy += y;
        }
        cx /= cells.len() as f32;
        cy /= cells.len() as f32;
        let mut maxd = 1.0f32;
        for &c in cells.iter() {
            let (x, y) = self.center(c);
            maxd = maxd.max(((x - cx).powi(2) + (y - cy).powi(2)).sqrt());
        }
        let s = seed as u64;
        let mut keyed: Vec<(f32, i32)> = cells
            .iter()
            .map(|&c| {
                let (x, y) = self.center(c);
                let d = ((x - cx).powi(2) + (y - cy).powi(2)).sqrt() / maxd;
                let k = d * 0.6 + value_noise(s, x, y, self.size * 5.0) * 0.4;
                (k, c)
            })
            .collect();
        keyed.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal).then(a.1.cmp(&b.1)));
        let total: f32 = sh.iter().map(|x| x.max(0.0)).sum::<f32>().max(1e-6);
        let n = keyed.len();
        let mut acc = 0.0f32;
        let mut start = 0usize;
        for (k, &t) in ts.iter().enumerate() {
            acc += sh[k].max(0.0) / total;
            let end = if k + 1 == ts.len() { n } else { ((acc * n as f32).round() as usize).clamp(start, n) };
            for &(_, c) in keyed[start..end].iter() {
                self.terr[c as usize] = if (0..255).contains(&t) { t as u8 } else { NONE };
                self.refresh_cost(c as usize);
            }
            start = end;
        }
    }

    /// Участок для работы: до n клеток провинции p с местностью из from_mask.
    /// Участок растёт связным пятном: начинается там, где рядом уже есть
    /// местность из toward_mask (поле расширяют от поля), и прирастает
    /// соседними клетками. Ничего не меняет — только выбирает.
    #[func]
    fn pick_patch(&self, p: i32, from_mask: i64, toward_mask: i64, n: i32, seed: i64) -> PackedInt32Array {
        let mut rng = Rng::new(seed as u64);
        let mut cand: Vec<i32> = self.cells_of(p).iter().copied().filter(|&c| in_mask(from_mask, self.terr[c as usize])).collect();
        let mut chosen: Vec<i32> = Vec::new();
        let want = n.max(0) as usize;
        while chosen.len() < want && !cand.is_empty() {
            // кандидаты на краю участка
            let mut best = usize::MAX;
            let mut best_s = f32::MIN;
            for (i, &c) in cand.iter().enumerate() {
                let touching = self.adj[c as usize].iter().filter(|&&m| m >= 0 && chosen.contains(&m)).count() as f32;
                let toward = self.near_count(c, toward_mask) as f32;
                let s = if chosen.is_empty() {
                    toward + unit(&mut rng) * 0.9
                } else if touching > 0.0 {
                    100.0 + touching + toward * 0.5 + unit(&mut rng) * 0.8
                } else {
                    // оторванный кусок — только если край участка исчерпан
                    toward + unit(&mut rng) * 0.9
                };
                if s > best_s {
                    best_s = s;
                    best = i;
                }
            }
            if best == usize::MAX {
                break;
            }
            chosen.push(cand.swap_remove(best));
        }
        PackedInt32Array::from(chosen.as_slice())
    }

    /// Природа: какие клетки местности from_t в провинции p перейдут за год.
    /// Шанс клетки — chance · (base + per_near · соседей из near_mask) (так
    /// вырубка зарастает от опушки). Ничего не меняет — только выбирает.
    #[func]
    fn drift_pick(&self, p: i32, from_t: i32, chance: f32, near_mask: i64, base: f32, per_near: f32, seed: i64) -> PackedInt32Array {
        let mut rng = Rng::new(seed as u64);
        let mut out = Vec::new();
        for &c in self.cells_of(p) {
            if self.terr[c as usize] as i32 != from_t {
                continue;
            }
            let k = if near_mask != 0 { self.near_count(c, near_mask) as f32 } else { 0.0 };
            let prob = chance * (base + per_near * k);
            if unit(&mut rng) < prob {
                out.push(c);
            }
        }
        PackedInt32Array::from(out.as_slice())
    }

    /// Для отрисовки: по два байта на клетку — местность и метка (1 — клетка
    /// из marks: здесь идёт работа).
    #[func]
    fn paint(&self, marks: PackedInt32Array) -> PackedByteArray {
        let n = self.n();
        let mut out = vec![0u8; n * 2];
        for i in 0..n {
            out[i * 2] = self.terr[i];
        }
        for &c in marks.as_slice() {
            if c >= 0 && (c as usize) < n {
                out[c as usize * 2 + 1] = 1;
            }
        }
        PackedByteArray::from(out.as_slice())
    }
}
