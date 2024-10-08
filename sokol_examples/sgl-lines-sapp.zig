//------------------------------------------------------------------------------
//  sgl-lines-sapp.c
//  Line rendering with sokol_gl.h
//------------------------------------------------------------------------------
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const dbgui = @import("dbgui");

const state = struct {
    var pass_action = sg.PassAction{};
    var depth_test_pip = sokol.gl.Pipeline{};
};

export fn init() void {
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    dbgui.setup(sokol.app.sampleCount());

    // setup sokol-gl
    sokol.gl.setup(.{
        .logger = .{ .func = sokol.log.func },
    });

    // a pipeline object with less-equal depth-testing
    state.depth_test_pip = sokol.gl.makePipeline(.{
        .depth = .{
            .write_enabled = true,
            .compare = .LESS_EQUAL,
        },
    });

    // a default pass action
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    };
}

fn grid(y: f32, frame_count: f32) void {
    const num = 64;
    const dist = 4.0;
    const z_offset = @divTrunc(@as(i32, @intFromFloat(dist)), 8) * (@as(i32, @intFromFloat(frame_count)) & 7);
    sokol.gl.beginLines();
    for (0..num) |i| {
        const x = @as(f32, @floatFromInt(i)) * dist - num * dist * 0.5;
        sokol.gl.v3f(x, y, -num * dist);
        sokol.gl.v3f(x, y, 0.0);
    }
    for (0..num) |i| {
        const z = z_offset + @as(f32, @floatFromInt(i)) * dist - num * dist;
        sokol.gl.v3f(-num * dist * 0.5, y, z);
        sokol.gl.v3f(num * dist * 0.5, y, z);
    }
    sokol.gl.end();
}

const num_segs = 32;
fn floaty_thingy(frame_count: u32) void {
    var start = frame_count % (num_segs * 2);
    if (start < num_segs) {
        start = 0;
    } else {
        start -= num_segs;
    }
    var end = frame_count % (num_segs * 2);
    if (end > num_segs) {
        end = num_segs;
    }
    const dx = 0.25;
    const dy = 0.25;
    const x0 = -(num_segs * dx * 0.5);
    const x1 = -x0;
    const y0 = -(num_segs * dy * 0.5);
    const y1 = -y0;
    sokol.gl.beginLines();
    for (start..end) |i| {
        const x = @as(f32, @floatFromInt(i)) * dx;
        const y = @as(f32, @floatFromInt(i)) * dy;
        sokol.gl.v2f(x0 + x, y0);
        sokol.gl.v2f(x1, y0 + y);
        sokol.gl.v2f(x1 - x, y1);
        sokol.gl.v2f(x0, y1 - y);
        sokol.gl.v2f(x0 + x, y1);
        sokol.gl.v2f(x1, y1 - y);
        sokol.gl.v2f(x1 - x, y0);
        sokol.gl.v2f(x0, y0 + y);
    }
    sokol.gl.end();
}

fn xorshift32() u32 {
    const tmp = struct {
        var x: u32 = 0x12345678;
    };
    tmp.x ^= tmp.x << 13;
    tmp.x ^= tmp.x >> 17;
    tmp.x ^= tmp.x << 5;
    return tmp.x;
}

fn rnd() f32 {
    return (@as(f32, @floatFromInt(xorshift32() & 0xFFFF)) / 0x10000) * 2.0 - 1.0;
}

const RING_NUM = 1024;
const RING_MASK = RING_NUM - 1;
var ring: [RING_NUM][6]f32 = undefined;
fn hairball() void {
    var head: usize = 0;

    const vx = rnd();
    const vy = rnd();
    const vz = rnd();
    const r = (rnd() + 1.0) * 0.5;
    const g = (rnd() + 1.0) * 0.5;
    const b = (rnd() + 1.0) * 0.5;
    const x = ring[head][0];
    const y = ring[head][1];
    const z = ring[head][2];
    head = (head + 1) & RING_MASK;
    ring[head][0] = x * 0.9 + vx;
    ring[head][1] = y * 0.9 + vy;
    ring[head][2] = z * 0.9 + vz;
    ring[head][3] = r;
    ring[head][4] = g;
    ring[head][5] = b;

    sokol.gl.beginLineStrip();
    var i = (head + 1) & RING_MASK;
    while (i != head) : (i = (i + 1) & RING_MASK) {
        sokol.gl.c3f(ring[i][3], ring[i][4], ring[i][5]);
        sokol.gl.v3f(ring[i][0], ring[i][1], ring[i][2]);
    }
    sokol.gl.end();
}

var g_frame_count: u32 = 0;
export fn frame() void {
    const aspect = sokol.app.widthf() / sokol.app.heightf();
    g_frame_count += 1;

    sokol.gl.defaults();
    sokol.gl.pushPipeline();
    sokol.gl.loadPipeline(state.depth_test_pip);
    sokol.gl.matrixModeProjection();
    sokol.gl.perspective(std.math.degreesToRadians(45.0), aspect, 0.1, 1000.0);
    sokol.gl.matrixModeModelview();
    sokol.gl.translate(
        std.math.sin(@as(f32, @floatFromInt(g_frame_count)) * 0.02) * 16.0,
        std.math.sin(@as(f32, @floatFromInt(g_frame_count)) * 0.01) * 4.0,
        0.0,
    );
    sokol.gl.c3f(1.0, 0.0, 1.0);
    grid(-7.0, @floatFromInt(g_frame_count));
    grid(7.0, @floatFromInt(g_frame_count));
    sokol.gl.pushMatrix();
    sokol.gl.translate(0.0, 0.0, -30.0);
    sokol.gl.rotate(@as(f32, @floatFromInt(g_frame_count)) * 0.05, 0.0, 1.0, 1.0);
    sokol.gl.c3f(1.0, 1.0, 0.0);
    floaty_thingy(g_frame_count);
    sokol.gl.popMatrix();
    sokol.gl.pushMatrix();
    sokol.gl.translate(
        -std.math.sin(@as(f32, @floatFromInt(g_frame_count)) * 0.02) * 32.0,
        0.0,
        -70.0 + std.math.cos(@as(f32, @floatFromInt(g_frame_count)) * 0.01) * 50.0,
    );
    sokol.gl.rotate(@as(f32, @floatFromInt(g_frame_count)) * 0.05, 0.0, -1.0, 1.0);
    sokol.gl.c3f(0.0, 1.0, 0.0);
    floaty_thingy(g_frame_count + 32);
    sokol.gl.popMatrix();
    sokol.gl.pushMatrix();
    sokol.gl.translate(-std.math.sin(@as(f32, @floatFromInt(g_frame_count)) * 0.02) * 16.0, 0.0, -30.0);
    sokol.gl.rotate(@as(f32, @floatFromInt(g_frame_count)) * 0.01, std.math.sin(@as(f32, @floatFromInt(g_frame_count)) * 0.005), 0.0, 1.0);
    sokol.gl.c3f(0.5, 1.0, 0.0);
    hairball();
    sokol.gl.popMatrix();
    sokol.gl.popPipeline();

    // sokol-gfx default pass with the actual sokol-gl drawing
    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });
    sokol.gl.draw();
    dbgui.draw();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    dbgui.shutdown();
    sokol.gl.shutdown();
    sg.shutdown();
}

pub fn main() void {
    sokol.app.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = dbgui.event,
        .width = 512,
        .height = 512,
        .sample_count = 4,
        .window_title = "sokol_gl.h lines (sokol-app)",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
