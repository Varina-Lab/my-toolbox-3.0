const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "portable_run",
        // CÚ PHÁP MỚI DÀNH CHO ZIG 0.14 / 0.15+
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Ẩn cửa sổ console trên Windows
    exe.subsystem = .Windows;

    b.installArtifact(exe);
}
