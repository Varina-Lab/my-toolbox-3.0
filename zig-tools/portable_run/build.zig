const std = @import("std");

pub fn build(b: *std.Build) void {
    // Cho phép người dùng chọn target và optimize từ dòng lệnh
    // Mặc định chúng ta sẽ truyền ReleaseFast từ GitHub Actions
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "portable_run", // Tên file tạm, GH Actions sẽ đổi tên sau
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Cấu hình để loại bỏ symbol thừa (strip) nếu là Release
    if (optimize == .ReleaseFast or optimize == .ReleaseSmall) {
        exe.root_module.strip = true;
    }

    // Cài đặt artifact vào thư mục zig-out/bin
    b.installArtifact(exe);
}