const sokol = @import("sokol");
const Camera = @import("camera.zig").Camera;

pub fn begin(camera: Camera) void {
    sokol.gl.defaults();
    sokol.gl.matrixModeProjection();
    sokol.gl.sgl_mult_matrix(&camera.projection.m[0]);
    sokol.gl.matrixModeModelview();
    sokol.gl.sgl_mult_matrix(&camera.view.m[0]);
}

pub fn end() void {
    sokol.gl.draw();
}

pub fn grid() void {
    const n = 5.0;
    sokol.gl.beginLines();
    {
        var x: f32 = -n;
        while (x <= n) : (x += 1) {
            sokol.gl.v3f(x, 0, -n);
            sokol.gl.v3f(x, 0, n);
        }
    }
    {
        var z: f32 = -n;
        while (z <= n) : (z += 1) {
            sokol.gl.v3f(-n, 0, z);
            sokol.gl.v3f(n, 0, z);
        }
    }
    sokol.gl.end();
}
