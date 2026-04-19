const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Khởi tạo root module bao gồm file nguồn, target và optimize
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 2. Tạo executable và truyền root_module vào
    const exe = b.addExecutable(.{
        .name = "portable_run",
        .root_module = root_module,
    });

    // Nếu muốn ẩn cửa sổ console (chạy ngầm), bỏ comment dòng dưới:
    // exe.subsystem = .Windows;

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
