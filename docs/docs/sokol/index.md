# sokol-zig

[sokol-zig](https://github.com/floooh/sokol-zig) は、
[sokol](https://github.com/floooh/sokol) の [zig](https://ziglang.org/) binding です。

:::note sokol は OpenGL などの Graphics API の薄いラッパーです
:::

## sokol はビルドに shader 変換が必要問題

sokol は stb のような `header only` なので
組み込むのが簡単なのだけど、

shader を専用ツールで前処理して `C` のヘッダー化するという工程がある。
これをビルドシステムに組み込む必要があった。

:::note 前処理された Shader は、
VertexLayout や Uniform 変数に型付きでアクセスできるので便利。
事前に reflection されている感じになる。
:::

:::note sokol 専用ぽいビルドツール [fips](https://github.com/floooh/fips) もあります。
:::

`sokok-zig` は`build.zig` 内で [sokol-tools-bin](https://github.com/floooh/sokol-tools-bin) を呼び出してくれるので、`shader` 変換問題が解決していた。

## zig は便利な OpenGL バインディングが無い問題

zig は、 `cImport` で `glfw` と `OpenGL` を直接使えるのだけど、
`glad` とか `glew` などの OpenGL Loader もやる必要がある。
で、関数ポインタが `cImport` されるみたいになり、あまり使い勝手が良くなかった(language server 的な意味で)。

一方 `sokol-zig` は、 `cImport` でなくて `extern fn` で zig で書かれた
`C` ライブラリへのインタフェースがあり使い勝手が良かった(language server 的な意味で)。

## 少ない手順で組み込みできる

<details>
  <summary>手順</summary>
  <p>
1. `zig init`
2. `zig fetch --save=sokol git+https://github.com/floooh/sokol-zig.git`
3. `build.zig` に足す

```zig
const dep_sokol = b.dependency("sokol", .{
  .target = target,
  .optimize = optimize,
});
exe.root_module.addImport("sokol", dep_sokol.module("sokol")); 
```

4. `src/main.zig` で sokol を使う

```zig
//------------------------------------------------------------------------------
//  clear-sapp.c
//------------------------------------------------------------------------------
const sokol = @import("sokol");
const sg = sokol.gfx;
const dbgui = @import("dbgui");

var pass_action = sg.PassAction{};

export fn init() void {
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    };
    dbgui.setup(sokol.app.sampleCount());
}

export fn frame() void {
    const g = pass_action.colors[0].clear_value.g + 0.01;
    pass_action.colors[0].clear_value.g = if (g > 1.0) 0.0 else g;
    sg.beginPass(.{
        .action = pass_action,
        .swapchain = sokol.glue.swapchain(),
    });
    dbgui.draw();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    dbgui.shutdown();
    sg.shutdown();
}

pub fn main() void {
    sokol.app.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        // .event_cb = __dbgui_event,
        .width = 400,
        .height = 300,
        .window_title = "Clear (sokol app)",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
```
5. `zig build run`

  </p>
</details>


## zig のクロスコンパイル + emscripten で WASM にできる

まず、 `glew` や `glad` 由来の OpenGL ヘッダーを
クロスコンパイル可能にするのにがんばりが必要。
`sokol-zig` は `build.zig` をそれなりに整備する必要はあるが、
`webgl` へのクロスコンパイルもサポートされている。

`github action` wasm のビルドとデプロイまでいける。

## Sample は結構ある

- https://floooh.github.io/sokol-html5/
- https://github.com/GeertArien/learnopengl-examples

`sokol-zig` に移植中

- https://ousttrue.github.io/learnopengl-examples/

# C との相互運用性は維持されている

- ImGui
- stb
- ozz-animation

わりと簡単に組み込める。

# zig で 3D programming するのにかなりよい

glfw + OpenGL + (glad や glew) より環境整備が楽、
かつコーディングが快適。
sokol でラップされているので OpenGL 直接では無くなるが、
sokol は洗練されたまっとうな API になっています。

