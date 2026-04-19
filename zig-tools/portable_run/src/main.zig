const std = @import("std");
const win = std.os.windows;

const StubbornFolder = struct {
    tag: []const u8,
    name: []const u8,
};

const AppConfig = struct {
    selected_exe: []const u8,
    registry_keys: [][]const u8,
    stubborn_folders: []StubbornFolder,
};

// WinAPI declarations
extern "kernel32" fn GetConsoleWindow() callconv(.C) ?*anyopaque;
extern "user32" fn ShowWindow(hWnd: ?*anyopaque, nCmdShow: i32) callconv(.C) win.BOOL;
extern "kernel32" fn AllocConsole() callconv(.C) win.BOOL;

fn hideConsole() void {
    const hwnd = GetConsoleWindow();
    if (hwnd != null) {
        _ = ShowWindow(hwnd, 0);
    }
}

fn showConsole() void {
    _ = AllocConsole();
    const hwnd = GetConsoleWindow();
    if (hwnd != null) {
        _ = ShowWindow(hwnd, 5); // SW_SHOW
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Init Engine Paths
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.os.getwd(&cwd_buf);
    const p_data = try std.fs.path.join(alloc, &.{ cwd, "Portable_Data" });
    const cfg_file = try std.fs.path.join(alloc, &.{ p_data, "config", "config.json" });

    // Ensure Base Dirs
    try std.fs.cwd().makePath("Portable_Data\\config");
    try std.fs.cwd().makePath("Portable_Data\\Registry");

    // Try to load config
    var has_config = false;
    if (std.fs.cwd().openFile(cfg_file, .{})) |file| {
        defer file.close();
        const content = try file.readToEndAlloc(alloc, 1024 * 1024);
        
        var parsed = std.json.parseFromSlice(AppConfig, alloc, content, .{ .ignore_unknown_fields = true }) catch null;
        if (parsed != null) {
            has_config = true;
            try runSandbox(alloc, p_data, parsed.?.value);
        }
    } else |_| {}

    if (!has_config) {
        try learningMode(alloc, p_data, cwd, cfg_file);
    }
}

fn setupEnvMap(alloc: std.mem.Allocator, p_data: []const u8) !std.process.EnvMap {
    var env_map = try std.process.getEnvMap(alloc);
    const roam = try std.fs.path.join(alloc, &.{ p_data, "AppData", "Roaming" });
    const local = try std.fs.path.join(alloc, &.{ p_data, "AppData", "Local" });
    const docs = try std.fs.path.join(alloc, &.{ p_data, "Documents" });

    try std.fs.cwd().makePath(roam);
    try std.fs.cwd().makePath(local);
    try std.fs.cwd().makePath(docs);

    try env_map.put("APPDATA", roam);
    try env_map.put("LOCALAPPDATA", local);
    try env_map.put("USERPROFILE", p_data);
    try env_map.put("DOCUMENTS", docs);

    return env_map;
}

fn learningMode(alloc: std.mem.Allocator, p_data: []const u8, cwd: []const u8, cfg_file: []const u8) !void {
    showConsole();
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();

    var exe_list = std.ArrayList([]const u8).init(alloc);
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".exe")) {
            // Ignore self
            if (!std.mem.eql(u8, entry.name, "portable_run.exe")) {
                try exe_list.append(try alloc.dupe(u8, entry.name));
            }
        }
    }

    if (exe_list.items.len == 0) {
        try stdout.print("[ERROR] No executable found.\n", .{});
        std.time.sleep(3 * std.time.ns_per_s);
        return;
    }

    var selected_exe: []const u8 = "";
    if (exe_list.items.len == 1) {
        selected_exe = exe_list.items[0];
    } else {
        try stdout.print("Select target executable:\n", .{});
        for (exe_list.items, 0..) |exe_name, i| {
            try stdout.print("{d}: {s}\n", .{ i, exe_name });
        }
        try stdout.print("Enter index: ", .{});
        
        var buf: [16]u8 = undefined;
        if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            const trimmed = std.mem.trim(u8, line, " \r\n");
            const idx = std.fmt.parseInt(usize, trimmed, 10) catch 0;
            if (idx < exe_list.items.len) {
                selected_exe = exe_list.items[idx];
            } else {
                selected_exe = exe_list.items[0];
            }
        }
    }

    // Basic learning mock: Normally you'd snapshot registry and files here.
    // In Zig, iterating registry without FFI is complex, so we will use cmd 'reg query' to mock snapshot logic.
    try stdout.print("\n[INFO] Starting {s} in learning mode...\n", .{selected_exe});
    
    var env_map = try setupEnvMap(alloc, p_data);
    defer env_map.deinit();

    var child = std.process.Child.init(&.{ selected_exe }, alloc);
    child.env_map = &env_map;
    _ = try child.spawnAndWait();

    // Mocking finding differences (Normally you compare snapshots)
    var reg_keys = std.ArrayList([]const u8).init(alloc);
    var stubborn_folders = std.ArrayList(StubbornFolder).init(alloc);

    // Save config
    var cfg = AppConfig{
        .selected_exe = selected_exe,
        .registry_keys = try reg_keys.toOwnedSlice(),
        .stubborn_folders = try stubborn_folders.toOwnedSlice(),
    };

    var out_file = try std.fs.cwd().createFile(cfg_file, .{});
    defer out_file.close();

    var ws = std.json.writeStream(out_file.writer(), .{ .whitespace = .indent_4 });
    try std.json.stringify(cfg, .{}, out_file.writer());

    try stdout.print("[INFO] Config saved to {s}\n", .{cfg_file});
    std.time.sleep(2 * std.time.ns_per_s);
}

fn runSandbox(alloc: std.mem.Allocator, p_data: []const u8, config: AppConfig) !void {
    // hideConsole();
    
    // Import registry if exists
    const reg_backup = try std.fs.path.join(alloc, &.{ p_data, "Registry", "data.reg" });
    if (std.fs.cwd().access(reg_backup, .{})) |_| {
        var import_cmd = std.process.Child.init(&.{ "reg", "import", reg_backup }, alloc);
        _ = try import_cmd.spawnAndWait();
    } else |_| {}

    // Setup Env
    var env_map = try setupEnvMap(alloc, p_data);
    defer env_map.deinit();

    // Make junctions (mklink /J)
    for (config.stubborn_folders) |folder| {
        // Here you'd run mklink logic
        _ = folder; 
    }

    // Run Exe
    var child = std.process.Child.init(&.{ config.selected_exe }, alloc);
    child.env_map = &env_map;
    _ = try child.spawnAndWait();

    // Export Registry (Sync)
    for (config.registry_keys) |key| {
        var export_cmd = std.process.Child.init(&.{ "reg", "export", key, reg_backup, "/y" }, alloc);
        _ = try export_cmd.spawnAndWait();
        
        var del_cmd = std.process.Child.init(&.{ "reg", "delete", key, "/f" }, alloc);
        _ = try del_cmd.spawnAndWait();
    }
}
