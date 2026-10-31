//! Ядро симуляции «Короны и Династии» — расширение Godot (GDExtension).
//! Разведка: клетки карты, поиск путей, путники и встречи.

use godot::prelude::*;

mod cells;
mod rng;

struct KoronaCore;

#[gdextension]
unsafe impl ExtensionLibrary for KoronaCore {}
