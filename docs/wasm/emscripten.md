# emscripten

## emsdk

## template shell

- https://emscripten.org/docs/compiling/Deploying-Pages.html

> out.html
> out.wasm
> out.js

- https://github.com/emscripten-core/emscripten/blob/main/src/shell_minimal.html
- https://github.com/emscripten-core/emscripten/blob/main/src/shell.html

`{{{ SCRIPT }}}` などが置換される。

### sokol-sample

- https://github.com/floooh/sokol-samples/blob/master/webpage/shell.html

### learn-opengl

- https://github.com/GeertArien/learnopengl-examples/blob/master/webpage/shell.html

### openFrameworks

- https://github.com/openframeworks/openFrameworks/blob/0.11.2/libs/openFrameworksCompiled/project/emscripten/template.html

### articles

-[openFrameworks を Emscripten でビルドするメモ | Kazumi Inada](https://posts.nandenjin.com/2022/of-emscripten/#html-%E3%83%86%E3%83%B3%E3%83%95%E3%82%9A%E3%83%AC%E3%83%BC%E3%83%88-shell-file-%E3%82%92%E7%B7%A8%E9%9B%86%E3%81%99%E3%82%8B)

## 関数追加

- [Emscripten で C/C++ から JS の関数を呼ぶには #JavaScript - Qiita](https://qiita.com/chikoski/items/9ac019a86095cfcf2c73)
- https://stackoverflow.com/questions/60741186/can-i-printf-as-console-warn-with-emscripten

## はまり

### stack size

stack に大きい配列を置いたりするとクラッシュ。

### c++

```
/zig/0.13.0/files/lib/libcxx/include/stdlib.h:145:30: error: unknown type name 'ldiv_t'
inline _LIBCPP_HIDE_FROM_ABI ldiv_t div(long __x, long __y) _NOEXCEPT { return ::ldiv(__x, __y); }
```

```
/zig/0.13.0/files/lib/libcxx/include/cstddef:46:5: error: <cstddef> tried including <stddef.h> but didn't find libc++'s <stddef.h> header.
This usually means that your header search paths are not configured properly.
The header search paths should contain the C++ Standard Library headers before any C Standard Library, and you are probably using compiler flags that make that not be the case.
# error <cstddef> tried including <stddef.h> but didn't find libc++'s <stddef.h> header.
```

```
/zig/p/12200ba39d83227f5de08287b043b011a2eb855cdb077f4b165edce30564ba73400e/upstream/emscripten/cache/sysroot/include/c++/v1/__config_site:3:9: error: '_LIBCPP_ABI_VERSION' macro redefined
#define _LIBCPP_ABI_VERSION 2
```

```zig
const emsdk_incl_path = dep_emsdk.path(
    "upstream/emscripten/cache/sysroot/include",
);
const emsdk_cpp_incl_path = dep_emsdk.path(
    "upstream/emscripten/cache/sysroot/include/c++/v1",
);
lib.addSystemIncludePath(emsdk_incl_path);
lib.addSystemIncludePath(emsdk_cpp_incl_path);
```

コンパイルは通った。

https://emscripten.org/docs/tools_reference/settings_reference.html

https://github.com/emscripten-core/emscripten/issues/19742

```
undefined symbol std::__1::basic_string
```

### include ?

ozz-animation のビルドができない

- https://ci-en.net/creator/12702/article/1198224
