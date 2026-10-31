//! Дороги по клеткам: у клетки — уровень дороги (0 — нет, 1 — тропа,
//! 2 — тракт, 3 — мощёная) и связи с соседними клетками (6 бит: по какой
//! стороне идёт дорога). Цена пути по клетке — местность × дорога. Дороги
//! прокладываются поиском пути (готовые дороги дешевле — новые к ним
//! прибиваются), рисуются линиями через середины сторон клеток.

use godot::prelude::*;

use crate::cells::CellMap;
use crate::land::value_noise;

/// Сдвиг точки дороги по плавному шуму: общие точки соседних клеток
/// сдвигаются одинаково, линия остаётся непрерывной, но не прямой.
fn jitter(p: Vector2, amp: f32) -> Vector2 {
    let dx = value_noise(101, p.x, p.y, 17.0) - 0.5;
    let dy = value_noise(202, p.x, p.y, 17.0) - 0.5;
    p + Vector2::new(dx, dy) * (amp * 2.0)
}

impl CellMap {
    /// Сторона k клетки a, ведущая в b (−1 — не соседи).
    fn dir_to(&self, a: i32, b: i32) -> i32 {
        for k in 0..6 {
            if self.adj[a as usize][k] == b {
                return k as i32;
            }
        }
        -1
    }

    fn link(&mut self, a: i32, b: i32) {
        let ka = self.dir_to(a, b);
        let kb = self.dir_to(b, a);
        if ka >= 0 && kb >= 0 {
            self.links[a as usize] |= 1 << ka;
            self.links[b as usize] |= 1 << kb;
        }
    }
}

#[godot_api(secondary)]
impl CellMap {
    /// Цена пути по уровням дороги (индекс — уровень 0…3); пересчитать цены клеток.
    #[func]
    fn set_road_moves(&mut self, moves: PackedFloat32Array) {
        self.road_moves = moves.as_slice().to_vec();
        for i in 0..self.n() {
            if self.prov[i] >= 0 {
                self.refresh_cost(i);
            }
        }
    }

    /// Проложить дорогу от клетки a до b не ниже уровня level (поиск пути:
    /// готовые дороги дешевле). Возвращает число клеток пути (0 — пути нет).
    #[func]
    fn trace_road(&mut self, a: i32, b: i32, level: i32) -> i32 {
        let path = self.path_cells(a, b, 2.5);
        if path.len() < 2 {
            return 0;
        }
        let lv = level.clamp(1, 3) as u8;
        for w in path.windows(2) {
            self.link(w[0], w[1]);
        }
        for &c in path.iter() {
            let i = c as usize;
            if self.road[i] < lv {
                self.road[i] = lv;
                self.refresh_cost(i);
            }
        }
        path.len() as i32
    }

    /// Убрать дороги с клеток местностей из маски (мёртвая земля): и сами
    /// дороги, и связи соседей с ними. Возвращает, сколько клеток очищено.
    #[func]
    fn clear_roads_on(&mut self, terrain_mask: i64) -> i32 {
        let mut n = 0;
        for i in 0..self.n() {
            let t = self.terr[i];
            if t == crate::cells::NONE || t >= 64 || (terrain_mask >> t) & 1 == 0 || self.links[i] == 0 {
                continue;
            }
            for k in 0..6 {
                let nb = self.adj[i][k];
                if nb >= 0 {
                    let back = (k + 3) % 6;
                    // сосед по стороне k видит эту клетку стороной напротив
                    let j = nb as usize;
                    if self.adj[j][back] == i as i32 {
                        self.links[j] &= !(1u8 << back);
                    } else {
                        for kk in 0..6 {
                            if self.adj[j][kk] == i as i32 {
                                self.links[j] &= !(1u8 << kk);
                            }
                        }
                    }
                    if self.links[j] == 0 && self.road[j] > 0 {
                        self.road[j] = 0;
                        self.refresh_cost(j);
                    }
                }
            }
            self.links[i] = 0;
            self.road[i] = 0;
            self.refresh_cost(i);
            n += 1;
        }
        n
    }

    /// Цена пути от a до b (−1 — пути нет).
    #[func]
    fn path_cost(&self, a: i32, b: i32) -> f32 {
        self.path_cost_of(a, b)
    }

    #[func]
    fn road_at(&self, cell: i32) -> i32 {
        self.road.get(cell as usize).copied().unwrap_or(0) as i32
    }

    /// Сменить уровень дороги клеток (связи остаются); сколько изменилось.
    #[func]
    fn set_road(&mut self, cells: PackedInt32Array, level: i32) -> i32 {
        let lv = level.clamp(0, 3) as u8;
        let mut n = 0;
        for &c in cells.as_slice() {
            let i = c as usize;
            if c < 0 || i >= self.n() || self.prov[i] < 0 || self.links[i] == 0 || self.road[i] == lv {
                continue;
            }
            self.road[i] = lv;
            self.refresh_cost(i);
            n += 1;
        }
        n
    }

    /// Клетки дорог провинции p с уровнями из маски (бит k — уровень k).
    #[func]
    fn road_cells(&self, p: i32, level_mask: i32) -> PackedInt32Array {
        let mut out = Vec::new();
        if p >= 0 && (p as usize) < self.owned.len() {
            for &c in self.owned[p as usize].iter() {
                let lv = self.road[c as usize];
                if lv > 0 && (level_mask >> lv) & 1 == 1 {
                    out.push(c);
                }
            }
        }
        PackedInt32Array::from(out.as_slice())
    }

    /// Дороги для сохранения: по два байта на клетку — уровень и связи.
    #[func]
    fn road_bytes(&self) -> PackedByteArray {
        let n = self.n();
        let mut out = vec![0u8; n * 2];
        for i in 0..n {
            out[i * 2] = self.road[i];
            out[i * 2 + 1] = self.links[i];
        }
        PackedByteArray::from(out.as_slice())
    }

    #[func]
    fn load_roads(&mut self, bytes: PackedByteArray) -> bool {
        let b = bytes.as_slice();
        if b.len() != self.n() * 2 {
            return false;
        }
        for i in 0..self.n() {
            if self.prov[i] < 0 {
                continue;
            }
            self.road[i] = b[i * 2].min(3);
            self.links[i] = b[i * 2 + 1] & 0x3f;
            self.refresh_cost(i);
        }
        true
    }

    /// Линии дорог для отрисовки: {pts — пары точек отрезков, lv — уровень
    /// отрезка}. Дорога идёт через середины сторон клетки; где у клетки две
    /// связи — плавной дугой через её середину.
    #[func]
    fn road_segments(&self) -> VarDictionary {
        let mut pts: Vec<Vector2> = Vec::new();
        let mut lvs: Vec<u8> = Vec::new();
        for i in 0..self.n() {
            let m = self.links[i];
            if m == 0 || self.road[i] == 0 {
                continue;
            }
            let (cx, cy) = self.center(i as i32);
            let amp = self.size * 0.45;
            let p = jitter(Vector2::new(cx, cy), amp);
            // середины сторон и уровень куска: не выше уровня соседа
            let mut mids: Vec<(Vector2, u8)> = Vec::new();
            let lv = self.road[i];
            for k in 0..6 {
                if (m >> k) & 1 == 1 {
                    let nb = self.adj[i][k];
                    if nb >= 0 && self.road[nb as usize] > 0 {
                        let (nx, ny) = self.center(nb);
                        let mid = jitter((Vector2::new(cx, cy) + Vector2::new(nx, ny)) * 0.5, amp * 0.8);
                        mids.push((mid, lv.min(self.road[nb as usize])));
                    }
                }
            }
            if mids.len() == 2 {
                // квадратичная дуга mid0 → (через середину клетки) → mid1;
                // первая половина — уровнем первого куска, вторая — второго
                let ((a, la), (b, lb)) = (mids[0], mids[1]);
                let steps = 4;
                let mut prev = a;
                for s in 1..=steps {
                    let t = s as f32 / steps as f32;
                    let u = 1.0 - t;
                    let q = a * (u * u) + p * (2.0 * u * t) + b * (t * t);
                    pts.push(prev);
                    pts.push(q);
                    lvs.push(if s * 2 <= steps { la } else { lb });
                    prev = q;
                }
            } else {
                for &(mid, l) in mids.iter() {
                    pts.push(mid);
                    pts.push(p);
                    lvs.push(l);
                }
            }
        }
        let mut d = VarDictionary::new();
        d.set("pts", &PackedVector2Array::from(pts.as_slice()));
        d.set("lv", &PackedByteArray::from(lvs.as_slice()));
        d
    }
}
