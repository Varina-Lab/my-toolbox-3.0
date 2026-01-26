const std = @import("std");

pub fn main() !void {
    // Lấy stdout để in ra màn hình
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Hello! This is a Zig Tool.\n", .{});
    try stdout.print("Built for Speed (ReleaseFast) & Standalone.\n", .{});

    // Ví dụ tính toán đơn giản
    var sum: u32 = 0;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        sum += i;
    }
    try stdout.print("Simple calculation check: {}\n", .{sum});
}
