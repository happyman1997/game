#!/usr/bin/env bash
# Собрать ядро на Rust и положить библиотеку в bin/ (её грузит korona_core.gdextension).
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release
mkdir -p ../bin
case "$(uname -s)" in
	Linux*) cp target/release/libkorona_core.so ../bin/ ;;
	Darwin*) cp target/release/libkorona_core.dylib ../bin/ ;;
	MINGW*|MSYS*|CYGWIN*) cp target/release/korona_core.dll ../bin/ ;;
esac
echo "ядро собрано: $(ls ../bin)"
