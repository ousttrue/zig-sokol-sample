# sokol-tools

## sokol はビルドに shader 変換が必要

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

## build.zig に組み込む例

```sh
# add dependency to build.zon
zig fetch --save=sokol-tools-bin git+https://github.com/floooh/sokol-tools-bin.git
```

```zig
// a separate step to compile shaders, expects the shader compiler in ../sokol-tools-bin/
fn buildShader(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    comptime shader: []const u8,
) *std.Build.Step {
    const optional_shdc = comptime switch (builtin.os.tag) {
        .windows => "win32/sokol-shdc.exe",
        .linux => "linux/sokol-shdc",
        .macos => if (builtin.cpu.arch.isX86()) "osx/sokol-shdc" else "osx_arm64/sokol-shdc",
        else => @panic("unsupported host platform, skipping shader compiler step"),
    };
    const tools = b.dependency("sokol-tools-bin", .{});
    const shdc_path = tools.path(b.pathJoin(&.{ "bin", optional_shdc })).getPath(b);
    const glsl = if (target.result.isDarwin()) "glsl410" else "glsl430";
    const slang = glsl ++ ":metal_macos:hlsl5:glsl300es:wgsl";
    return &b.addSystemCommand(&.{
        shdc_path,
        "-i",
        shader,
        "-o",
        shader ++ ".zig",
        "-l",
        slang,
        "-f",
        "sokol_zig",
    }).step;
}
```
