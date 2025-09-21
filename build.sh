set -x

mkdir -p public/wasm

pushd sokol_examples
dirs=$(find . -type d -name "*-sapp")
for d in $dirs; do
  pushd $d
  zig build -Dtarget=wasm32-emscripten
  cp -rp zig-out/web/* ../../public/wasm/
  popd
done
