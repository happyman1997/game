//! Клетки карты: шестиугольная сетка поверх растровой карты. У каждой
//! клетки суши — провинция, местность (land.rs) и цена пути по ней; поиск
//! пути A*; путники, которые ходят по клеткам и встречаются, оказавшись
//! рядом (замер).
//!
//! Сетка «нечётные строки сдвинуты» (odd-r): центр клетки (c, r) —
//! x = size·√3·(c + ½·(r & 1)), y = size·1,5·r.

use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashMap};
use std::time::Instant;

use godot::prelude::*;

use crate::rng::Rng;

pub(crate) const SQRT3: f32 = 1.732_050_8;
/// Соседи для чётных и нечётных строк: (dc, dr).
const NB_EVEN: [(i32, i32); 6] = [(1, 0), (0, -1), (-1, -1), (-1, 0), (-1, 1), (0, 1)];
const NB_ODD: [(i32, i32); 6] = [(1, 0), (1, -1), (0, -1), (-1, 0), (0, 1), (1, 1)];
/// Нет местности (вода).
pub(crate) const NONE: u8 = 255;

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct CellMap {
    pub(crate) cols: i32,
    pub(crate) rows: i32,
    pub(crate) size: f32,
    /// Провинция клетки (индекс в MapData.provinces), −1 — вода.
    pub(crate) prov: Vec<i32>,
    /// Проходима ли клетка (непроходимые провинции — горы без троп).
    pub(crate) pass: Vec<bool>,
    /// Цена входа в клетку (по её местности).
    pub(crate) cost: Vec<f32>,
    /// Проходимые соседи клетки (−1 — нет) — для путей.
    pub(crate) nb: Vec<[i32; 6]>,
    /// Все соседи-суша (−1 — нет) — для земли: рост участков, природа.
    pub(crate) adj: Vec<[i32; 6]>,
    /// Номера проходимых клеток.
    pub(crate) land: Vec<i32>,
    /// Связная область суши клетки (−1 — вода); клетки суши по областям.
    pub(crate) comp: Vec<i32>,
    pub(crate) comp_cells: Vec<Vec<i32>>,
    /// Клетки каждой провинции.
    pub(crate) owned: Vec<Vec<i32>>,
    /// Местность клетки (индекс в списке местностей, NONE — нет).
    pub(crate) terr: Vec<u8>,
    /// Цена пути по местностям.
    pub(crate) moves: Vec<f32>,
    base: Base<RefCounted>,
}

#[derive(Copy, Clone, PartialEq)]
struct Open {
    f: f32,
    cell: i32,
}

impl Eq for Open {}

impl Ord for Open {
    fn cmp(&self, other: &Self) -> Ordering {
        // BinaryHeap — максимум; нам нужен минимум f
        other.f.partial_cmp(&self.f).unwrap_or(Ordering::Equal).then_with(|| other.cell.cmp(&self.cell))
    }
}

impl PartialOrd for Open {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl CellMap {
    pub(crate) fn n(&self) -> usize {
        self.prov.len()
    }

    /// Случайная клетка той же области суши, что и from.
    fn random_reachable(&self, from: i32, rng: &mut Rng) -> i32 {
        let k = self.comp[from as usize];
        if k < 0 {
            return from;
        }
        let cells = &self.comp_cells[k as usize];
        cells[rng.below(cells.len())]
    }

    pub(crate) fn center(&self, id: i32) -> (f32, f32) {
        let c = id % self.cols;
        let r = id / self.cols;
        (self.size * SQRT3 * (c as f32 + 0.5 * (r & 1) as f32), self.size * 1.5 * r as f32)
    }

    /// Клетка, в которой лежит точка (ближайший центр), −1 — вне сетки.
    pub(crate) fn cell_at_point(&self, x: f32, y: f32) -> i32 {
        let r0 = (y / (self.size * 1.5)).floor() as i32;
        let mut best = -1;
        let mut best_d = f32::MAX;
        for r in r0 - 1..=r0 + 1 {
            if r < 0 || r >= self.rows {
                continue;
            }
            let c0 = (x / (self.size * SQRT3) - 0.5 * (r & 1) as f32).round() as i32;
            for c in c0 - 1..=c0 + 1 {
                if c < 0 || c >= self.cols {
                    continue;
                }
                let id = r * self.cols + c;
                let (cx, cy) = self.center(id);
                let d = (cx - x) * (cx - x) + (cy - y) * (cy - y);
                if d < best_d {
                    best_d = d;
                    best = id;
                }
            }
        }
        best
    }

    fn neighbors_of(&self, id: i32) -> [i32; 6] {
        let mut out = [-1; 6];
        let c = id % self.cols;
        let r = id / self.cols;
        let dirs = if r & 1 == 0 { &NB_EVEN } else { &NB_ODD };
        for (k, (dc, dr)) in dirs.iter().enumerate() {
            let (nc, nr) = (c + dc, r + dr);
            if nc >= 0 && nr >= 0 && nc < self.cols && nr < self.rows {
                out[k] = nr * self.cols + nc;
            }
        }
        out
    }

    /// Шагов между клетками (по кубическим координатам) — оценка для A*.
    pub(crate) fn hex_dist(&self, a: i32, b: i32) -> i32 {
        let cube = |id: i32| {
            let c = id % self.cols;
            let r = id / self.cols;
            let x = c - (r - (r & 1)) / 2;
            (x, r, -x - r)
        };
        let (ax, ay, az) = cube(a);
        let (bx, by, bz) = cube(b);
        ((ax - bx).abs()).max((ay - by).abs()).max((az - bz).abs())
    }

    /// Цена клетки по её местности.
    pub(crate) fn refresh_cost(&mut self, i: usize) {
        let t = self.terr[i] as usize;
        self.cost[i] = if t < self.moves.len() { self.moves[t].max(0.1) } else { 1.0 };
    }

    /// A*: путь от a до b включительно (пусто — пути нет).
    fn path(&self, a: i32, b: i32, scratch: &mut Scratch) -> Vec<i32> {
        let n = self.n();
        if a < 0 || b < 0 || a as usize >= n || b as usize >= n || !self.pass[a as usize] || !self.pass[b as usize] {
            return Vec::new();
        }
        scratch.prepare(n);
        let min_cost = self.moves.iter().cloned().fold(1.0_f32, f32::min).max(0.1);
        let mut open = BinaryHeap::new();
        scratch.g[a as usize] = 0.0;
        scratch.touch(a as usize);
        open.push(Open { f: self.hex_dist(a, b) as f32 * min_cost, cell: a });
        while let Some(Open { cell, .. }) = open.pop() {
            if cell == b {
                break;
            }
            let ci = cell as usize;
            if scratch.closed[ci] == scratch.stamp {
                continue;
            }
            scratch.closed[ci] = scratch.stamp;
            let g = scratch.g[ci];
            for &m in self.nb[ci].iter() {
                if m < 0 {
                    continue;
                }
                let mi = m as usize;
                let ng = g + (self.cost[ci] + self.cost[mi]) * 0.5;
                if scratch.seen[mi] != scratch.stamp || ng < scratch.g[mi] {
                    scratch.touch(mi);
                    scratch.g[mi] = ng;
                    scratch.from[mi] = cell;
                    open.push(Open { f: ng + self.hex_dist(m, b) as f32 * min_cost, cell: m });
                }
            }
        }
        if scratch.seen[b as usize] != scratch.stamp {
            return Vec::new();
        }
        let mut out = vec![b];
        let mut cur = b;
        while cur != a {
            cur = scratch.from[cur as usize];
            out.push(cur);
        }
        out.reverse();
        out
    }
}

/// Рабочие массивы A* — переиспользуются между поисками (метка поколения
/// вместо очистки).
#[derive(Default)]
struct Scratch {
    g: Vec<f32>,
    from: Vec<i32>,
    seen: Vec<u32>,
    closed: Vec<u32>,
    stamp: u32,
}

impl Scratch {
    fn prepare(&mut self, n: usize) {
        if self.g.len() != n {
            self.g = vec![0.0; n];
            self.from = vec![-1; n];
            self.seen = vec![0; n];
            self.closed = vec![0; n];
            self.stamp = 0;
        }
        self.stamp = self.stamp.wrapping_add(1);
        if self.stamp == 0 {
            self.seen.iter_mut().for_each(|x| *x = 0);
            self.closed.iter_mut().for_each(|x| *x = 0);
            self.stamp = 1;
        }
    }

    fn touch(&mut self, i: usize) {
        self.seen[i] = self.stamp;
    }
}

#[godot_api]
impl CellMap {
    /// Нарезать карту на клетки. pixels — индекс провинции на пиксель (−1 —
    /// вода), passable — 1 у проходимых провинций, centers — центры провинций
    /// (x, y парами), size — радиус клетки в пикселях. У каждой провинции
    /// будет хотя бы одна клетка (крохотной достаётся клетка у её центра).
    /// Возвращает число клеток суши.
    #[func]
    fn build(&mut self, width: i32, height: i32, pixels: PackedInt32Array, passable: PackedByteArray, centers: PackedFloat32Array, size: f32) -> i32 {
        let px = pixels.as_slice();
        let ps = passable.as_slice();
        let pc = centers.as_slice();
        let np = ps.len();
        self.size = size.max(1.0);
        self.cols = ((width as f32) / (self.size * SQRT3)).ceil() as i32 + 1;
        self.rows = ((height as f32) / (self.size * 1.5)).ceil() as i32 + 1;
        let n = (self.cols * self.rows) as usize;
        self.prov = vec![-1; n];
        for id in 0..n as i32 {
            let (x, y) = self.center(id);
            let (xi, yi) = (x as i32, y as i32);
            if xi < 0 || yi < 0 || xi >= width || yi >= height {
                continue;
            }
            let p = px[(yi * width + xi) as usize];
            if p >= 0 && (p as usize) < np {
                self.prov[id as usize] = p;
            }
        }
        // крохотные провинции: клетка у центра (у соседа, если у него их много)
        let mut count = vec![0usize; np];
        for &p in self.prov.iter() {
            if p >= 0 {
                count[p as usize] += 1;
            }
        }
        for p in 0..np {
            if count[p] > 0 || pc.len() < (p + 1) * 2 {
                continue;
            }
            let at = self.cell_at_point(pc[p * 2], pc[p * 2 + 1]);
            if at < 0 {
                continue;
            }
            let mut cands = vec![at];
            cands.extend(self.neighbors_of(at).iter().filter(|&&m| m >= 0));
            for &c in cands.iter() {
                let q = self.prov[c as usize];
                if q < 0 || count[q as usize] > 1 {
                    if q >= 0 {
                        count[q as usize] -= 1;
                    }
                    self.prov[c as usize] = p as i32;
                    count[p] += 1;
                    break;
                }
            }
        }
        self.pass = self.prov.iter().map(|&p| p >= 0 && ps[p as usize] == 1).collect();
        self.owned = vec![Vec::new(); np];
        self.land.clear();
        for id in 0..n {
            let p = self.prov[id];
            if p >= 0 {
                self.owned[p as usize].push(id as i32);
                if self.pass[id] {
                    self.land.push(id as i32);
                }
            }
        }
        self.adj = vec![[-1; 6]; n];
        self.nb = vec![[-1; 6]; n];
        for id in 0..n {
            if self.prov[id] < 0 {
                continue;
            }
            let near = self.neighbors_of(id as i32);
            for k in 0..6 {
                let m = near[k];
                if m >= 0 && self.prov[m as usize] >= 0 {
                    self.adj[id][k] = m;
                    if self.pass[id] && self.pass[m as usize] {
                        self.nb[id][k] = m;
                    }
                }
            }
        }
        // связные области проходимой суши (острова, материк)
        self.comp = vec![-1; n];
        self.comp_cells.clear();
        for &start in self.land.iter() {
            if self.comp[start as usize] >= 0 {
                continue;
            }
            let k = self.comp_cells.len() as i32;
            let mut cells = vec![start];
            self.comp[start as usize] = k;
            let mut i = 0;
            while i < cells.len() {
                let c = cells[i] as usize;
                for &m in self.nb[c].iter() {
                    if m >= 0 && self.comp[m as usize] < 0 {
                        self.comp[m as usize] = k;
                        cells.push(m);
                    }
                }
                i += 1;
            }
            self.comp_cells.push(cells);
        }
        self.terr = vec![NONE; n];
        self.cost = vec![1.0; n];
        self.owned.iter().map(|v| v.len()).sum::<usize>() as i32
    }

    #[func]
    fn component_count(&self) -> i32 {
        self.comp_cells.len() as i32
    }

    /// Проходимых клеток суши.
    #[func]
    fn land_count(&self) -> i32 {
        self.land.len() as i32
    }

    #[func]
    fn cell_count(&self) -> i32 {
        self.n() as i32
    }

    #[func]
    fn cols(&self) -> i32 {
        self.cols
    }

    #[func]
    fn rows(&self) -> i32 {
        self.rows
    }

    #[func]
    fn cell_size(&self) -> f32 {
        self.size
    }

    #[func]
    fn province_of(&self, cell: i32) -> i32 {
        self.prov.get(cell as usize).copied().unwrap_or(-1)
    }

    /// Клетка под точкой карты (−1 — вне сетки).
    #[func]
    fn cell_at(&self, x: f32, y: f32) -> i32 {
        self.cell_at_point(x, y)
    }

    #[func]
    fn cell_center(&self, cell: i32) -> Vector2 {
        let (x, y) = self.center(cell);
        Vector2::new(x, y)
    }

    #[func]
    fn find_path(&self, a: i32, b: i32) -> PackedInt32Array {
        let mut s = Scratch::default();
        PackedInt32Array::from(self.path(a, b, &mut s).as_slice())
    }

    /// Пустой вызов — замер цены перехода GDScript → Rust.
    #[func]
    fn noop(&self, x: i32) -> i32 {
        x + 1
    }

    /// Граф клеток для сравнения с GDScript: соседи (по 6 на клетку), цены.
    #[func]
    fn export_graph(&self) -> VarDictionary {
        let mut nb = Vec::with_capacity(self.nb.len() * 6);
        for row in self.nb.iter() {
            nb.extend_from_slice(row);
        }
        let mut d = VarDictionary::new();
        d.set("cols", self.cols);
        d.set("nb", &PackedInt32Array::from(nb.as_slice()));
        d.set("cost", &PackedFloat32Array::from(self.cost.as_slice()));
        d.set("land", &PackedInt32Array::from(self.land.as_slice()));
        d
    }

    /// Замер: pairs поисков пути между случайными клетками суши.
    #[func]
    fn bench_paths(&self, pairs: i32, seed: i64) -> VarDictionary {
        let mut rng = Rng::new(seed as u64);
        let mut s = Scratch::default();
        let t0 = Instant::now();
        let mut found = 0;
        let mut total_len = 0usize;
        for _ in 0..pairs {
            let a = self.land[rng.below(self.land.len())];
            let b = self.random_reachable(a, &mut rng);
            let p = self.path(a, b, &mut s);
            if !p.is_empty() {
                found += 1;
                total_len += p.len();
            }
        }
        let mut d = VarDictionary::new();
        d.set("ms", t0.elapsed().as_secs_f64() * 1000.0);
        d.set("found", found);
        d.set("avg_len", if found > 0 { total_len as f64 / found as f64 } else { 0.0 });
        d
    }

    /// Замер: agents путников days дней ходят по клеткам к случайным целям
    /// (speed — сколько «цены пути» проходят за день); каждый день —
    /// пространственный индекс и подсчёт встреч (двое в одной или соседней
    /// клетке).
    #[func]
    fn bench_movers(&self, agents: i32, days: i32, speed: f32, seed: i64) -> VarDictionary {
        let mut rng = Rng::new(seed as u64);
        let mut s = Scratch::default();
        let n = agents.max(0) as usize;
        let mut at: Vec<i32> = (0..n).map(|_| self.land[rng.below(self.land.len())]).collect();
        let mut route: Vec<Vec<i32>> = vec![Vec::new(); n];
        let mut step: Vec<usize> = vec![0; n];
        let mut budget: Vec<f32> = vec![0.0; n];
        let t0 = Instant::now();
        let mut paths = 0u64;
        let mut moves = 0u64;
        let mut encounters = 0u64;
        let mut grid: HashMap<i32, Vec<u32>> = HashMap::with_capacity(n * 2);
        for _ in 0..days {
            for i in 0..n {
                if step[i] + 1 >= route[i].len() {
                    let dest = self.random_reachable(at[i], &mut rng);
                    route[i] = self.path(at[i], dest, &mut s);
                    step[i] = 0;
                    paths += 1;
                    if route[i].len() < 2 {
                        continue;
                    }
                }
                budget[i] += speed;
                while step[i] + 1 < route[i].len() {
                    let next = route[i][step[i] + 1];
                    let c = (self.cost[at[i] as usize] + self.cost[next as usize]) * 0.5;
                    if budget[i] < c {
                        break;
                    }
                    budget[i] -= c;
                    step[i] += 1;
                    at[i] = next;
                    moves += 1;
                }
            }
            grid.clear();
            for (i, &c) in at.iter().enumerate() {
                grid.entry(c).or_default().push(i as u32);
            }
            for (i, &c) in at.iter().enumerate() {
                // в своей клетке — с теми, у кого номер больше; в соседних — тоже
                if let Some(v) = grid.get(&c) {
                    encounters += v.iter().filter(|&&j| j as usize > i).count() as u64;
                }
                for &m in self.nb[c as usize].iter() {
                    if m >= 0 {
                        if let Some(v) = grid.get(&m) {
                            encounters += v.iter().filter(|&&j| j as usize > i).count() as u64;
                        }
                    }
                }
            }
        }
        let mut d = VarDictionary::new();
        d.set("ms", t0.elapsed().as_secs_f64() * 1000.0);
        d.set("paths", paths as i64);
        d.set("moves", moves as i64);
        d.set("encounters", encounters as i64);
        d
    }
}
