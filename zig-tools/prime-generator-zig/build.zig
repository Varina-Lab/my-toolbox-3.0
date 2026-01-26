const std = @import("std");

pub fn build(b: *std.Build) void {
    // Xác định mục tiêu biên dịch (Windows, Linux, macOS, v.v.)
    const target = b.standardTargetOptions(.{});

    // Xác định chế độ tối ưu hóa (Debug, ReleaseSafe, ReleaseFast, ReleaseSmall)
    const optimize = b.standardOptimizeOption(.{});

    // Tạo một tệp thực thi (executable)
    const exe = b.addExecutable(.{
        .name = "hello",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Cài đặt tệp thực thi vào thư mục zig-out/bin
    b.installArtifact(exe);

    // Tạo lệnh "run" để chạy ứng dụng ngay sau khi build
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Chạy ứng dụng Hello World");
    run_step.dependOn(&run_cmd.step);
}
