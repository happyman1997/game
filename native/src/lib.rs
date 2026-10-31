//! Ядро симуляции «Короны и Династии» — расширение Godot (GDExtension):
//! клетки карты и земля на них, поиск путей, путники и встречи.

use godot::prelude::*;

mod cells;
mod land;
mod rng;

struct KoronaCore;

#[gdextension]
unsafe impl ExtensionLibrary for KoronaCore {}
