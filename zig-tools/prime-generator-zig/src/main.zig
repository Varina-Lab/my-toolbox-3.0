const std = @import("std");

pub fn main() !void {
    // Nội dung chương trình của bạn
    std.debug.print("Chương trình đã chạy xong. Nhấn Enter để thoát...", .{});

    // Lấy stdin và tạo bộ đệm đọc
    const stdin = std.io.getStdIn().reader();
    
    // Đợi người dùng nhấn Enter
    var byte_buffer: [1]u8 = undefined;
    _ = try stdin.read(&byte_buffer);
}
