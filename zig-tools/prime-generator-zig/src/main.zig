const std = @import("std");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const stdin = std.io.getStdIn().reader();

    // Nhap du lieu
    try stdout.print("Nhap vao so N: ", .{});
    try bw.flush();

    var buf: [20]u8 = undefined;
    if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\n");
        const n = std.fmt.parseInt(u32, trimmed, 10) catch {
            try stdout.print("Du lieu nhap vao khong hop le.\n", .{});
            try bw.flush();
            return;
        };

        // Bat dau do thoi gian
        var timer = try std.time.Timer.start();

        // Thuat toan Sang Eratosthenes toi uu
        if (n > 2) {
            // Su dung page_allocator cho mang lon
            const allocator = std.heap.page_allocator;
            
            // Chi xet so le: size = (n-1)/2
            const size = (n - 1) / 2;
            var is_prime = try allocator.alloc(bool, size + 1);
            defer allocator.free(is_prime);
            @memset(is_prime, true);

            var count: u32 = 1; // So 2 la so nguyen to dau tien
            try stdout.print("Cac so nguyen to: 2 ", .{});

            const sqrt_n = std.math.sqrt(n);

            for (1..size + 1) |i| {
                if (is_prime[i]) {
                    const p = @as(u32, @intCast(i)) * 2 + 1;
                    if (p >= n) break;
                    
                    try stdout.print("{} ", .{p});
                    count += 1;

                    if (p <= sqrt_n) {
                        var j = 2 * i * (i + 1);
                        while (j <= size) : (j += p) {
                            is_prime[j] = false;
                        }
                    }
                }
            }

            const duration_ns = timer.read();
            const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

            try stdout.print("\n-------------------------------------------\n", .{});
            try stdout.print("Thoi gian thuc thi: {d:.4} ms\n", .{duration_ms});
            try stdout.print("Tong cong co: {} so nguyen to.\n", .{count});
        } else {
            try stdout.print("Khong co so nguyen to nao nho hon {}.\n", .{n});
        }
    }

    try stdout.print("\nNhan Enter de thoat...", .{});
    try bw.flush();
    _ = try stdin.readByte();
}
