//! Ядро симуляции «Короны и Династии» — расширение Godot (GDExtension):
//! клетки карты, земля и дороги на них, поиск путей, путники и встречи.

use godot::prelude::*;

mod cells;
mod land;
mod rng;
mod roads;
mod world;

struct KoronaCore;

#[gdextension]
unsafe impl ExtensionLibrary for KoronaCore {}
