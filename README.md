# zig-sokol 練習

sokol の zig binding を練習する。

- `zig-0.15.1`
- `sokol-2025-09`

zig と sokol のバージョンアップについていけるようにシンプル化。
あと emsdk4。
sokol の API breaking change が来た。

- [The sokol-gfx resource view update.](https://floooh.github.io/2025/08/17/sokol-gfx-view-update.html)

## bun site

- package.json
- docs/
- src/
- sokol_examples
  - `*-sapp` sokolのサンプルビルド。
  - `zig build -Dtarget=wasm32-emscripten` により `zig-out/web` に wasm を出力できる。
