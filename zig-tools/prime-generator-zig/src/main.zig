const std = @import("std");

pub fn main() !void {
    // 1. Khởi tạo một buffer (vùng đệm) cho stdout.
    // Trong Zig 0.15+, Writer thường yêu cầu một buffer do người dùng quản lý.
    var buffer: [1024]u8 = undefined;

    // 2. Lấy handle của stdout từ std.fs.File
    const stdout_file = std.fs.File.stdout();

    // 3. Tạo một writer gắn với buffer đã khai báo
    // Nếu không muốn dùng buffer, bạn có thể truyền &.{}.
    var stdout_writer = stdout_file.writer(&buffer);

    // 4. Lấy interface của writer để sử dụng các hàm như print
    const stdout = &stdout_writer.interface;

    // 5. In nội dung
    try stdout.print("Hello, World! (Zig 0.15.2 Standard)\n", .{});

    // 6. QUAN TRỌNG: Phải gọi flush() để đẩy dữ liệu từ buffer ra màn hình
    try stdout.flush();
}
