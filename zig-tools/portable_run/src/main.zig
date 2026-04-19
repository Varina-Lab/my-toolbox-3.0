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

// WinAPI declarations (SỬA LỖI: dùng win.WINAPI thay vì .C)
extern "kernel32" fn GetConsoleWindow() callconv(win.WINAPI) ?*anyopaque;
extern "user32" fn ShowWindow(hWnd: ?*anyopaque, nCmdShow: i32) callconv(win.WINAPI) win.BOOL;
extern "kernel32" fn AllocConsole() callconv(win.WINAPI) win.BOOL;
extern "kernel32" fn GetModuleFileNameW(hModule: ?*anyopaque, lpFilename: [*]u16, nSize: u32) callconv(win.WINAPI) u32;

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

    // 1. Gọi thẳng Win32 API để lấy đường dẫn tuyệt đối của file EXE hiện tại một cách an toàn
    var exe_path_w: [4096]u16 = undefined;
    const len = GetModuleFileNameW(null, &exe_path_w, 4096);
    if (len == 0) return error.GetModuleFileNameFailed;

    const exe_path = try std.unicode.utf16LeToUtf8Alloc(alloc, exe_path_w[0..len]);
    
    // 2. Lấy thư mục chứa file EXE làm thư mục gốc (Base Directory)
    const base_dir_path = std.fs.path.dirname(exe_path) orelse return error.NoExeDir;

    // 3. Mở quyền truy cập dựa trên thư mục gốc này (Cho phép lặp file bên trong)
    var base_dir = try std.fs.openDirAbsolute(base_dir_path, .{ .iterate = true });
    defer base_dir.close();

    const p_data = try std.fs.path.join(alloc, &.{ base_dir_path, "Portable_Data" });

    // Đảm bảo tạo thư mục nền
    try base_dir.makePath("Portable_Data/config");
    try base_dir.makePath("Portable_Data/Registry");

    // Thử load cấu hình
    var has_config = false;
    if (base_dir.openFile("Portable_Data/config/config.json", .{})) |file| {
        defer file.close();
        const content = try file.readToEndAlloc(alloc, 1024 * 1024);
        
        const parsed = std.json.parseFromSlice(AppConfig, alloc, content, .{ .ignore_unknown_fields = true }) catch null;
        if (parsed != null) {
            has_config = true;
            try runSandbox(alloc, base_dir_path, p_data, base_dir, parsed.?.value);
        }
    } else |_| {}

    if (!has_config) {
        try learningMode(alloc, base_dir_path, p_data, base_dir);
    }
}

fn setupEnvMap(alloc: std.mem.Allocator, p_data: []const u8, base_dir: std.fs.Dir) !std.process.EnvMap {
    var env_map = try std.process.getEnvMap(alloc);
    const roam = try std.fs.path.join(alloc, &.{ p_data, "AppData", "Roaming" });
    const local = try std.fs.path.join(alloc, &.{ p_data, "AppData", "Local" });
    const docs = try std.fs.path.join(alloc, &.{ p_data, "Documents" });

    try base_dir.makePath("Portable_Data/AppData/Roaming");
    try base_dir.makePath("Portable_Data/AppData/Local");
    try base_dir.makePath("Portable_Data/Documents");

    try env_map.put("APPDATA", roam);
    try env_map.put("LOCALAPPDATA", local);
    try env_map.put("USERPROFILE", p_data);
    try env_map.put("DOCUMENTS", docs);

    return env_map;
}

fn learningMode(alloc: std.mem.Allocator, base_dir_path: []const u8, p_data: []const u8, base_dir: std.fs.Dir) !void {
    showConsole();
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    var exe_list = std.ArrayList([]const u8).init(alloc);
    var it = base_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".exe")) {
            // Loại trừ bản thân launcher ra khỏi danh sách list
            if (!std.mem.eql(u8, entry.name, "portable_run.exe")) {
                try exe_list.append(try alloc.dupe(u8, entry.name));
            }
        }
    }

    if (exe_list.items.len == 0) {
        try stdout.print("[ERROR] No executable found in {s}.\n", .{base_dir_path});
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

    try stdout.print("\n[INFO] Starting {s} in learning mode...\n", .{selected_exe});
    
    var env_map = try setupEnvMap(alloc, p_data, base_dir);
    defer env_map.deinit();

    // Chạy với đường dẫn exe tuyệt đối đảm bảo khởi chạy thành công bất chấp CMD đang ở đâu
    const exe_abs = try std.fs.path.join(alloc, &.{ base_dir_path, selected_exe });
    var child = std.process.Child.init(&.{ exe_abs }, alloc);
    child.env_map = &env_map;
    _ = try child.spawnAndWait();

    var reg_keys = std.ArrayList([]const u8).init(alloc);
    var stubborn_folders = std.ArrayList(StubbornFolder).init(alloc);

    const cfg = AppConfig{
        .selected_exe = selected_exe,
        .registry_keys = try reg_keys.toOwnedSlice(),
        .stubborn_folders = try stubborn_folders.toOwnedSlice(),
    };

    var out_file = try base_dir.createFile("Portable_Data/config/config.json", .{});
    defer out_file.close();

    try std.json.stringify(cfg, .{ .whitespace = .indent_4 }, out_file.writer());

    try stdout.print("[INFO] Config saved to Portable_Data/config/config.json\n", .{});
    std.time.sleep(2 * std.time.ns_per_s);
}

fn runSandbox(alloc: std.mem.Allocator, base_dir_path: []const u8, p_data: []const u8, base_dir: std.fs.Dir, config: AppConfig) !void {
    // hideConsole();
    
    // Import registry nếu file backup có tồn tại
    const reg_backup_abs = try std.fs.path.join(alloc, &.{ p_data, "Registry", "data.reg" });
    if (base_dir.openFile("Portable_Data/Registry/data.reg", .{})) |f| {
        f.close();
        var import_cmd = std.process.Child.init(&.{ "reg", "import", reg_backup_abs }, alloc);
        _ = try import_cmd.spawnAndWait();
    } else |_| {}

    // Setup Env
    var env_map = try setupEnvMap(alloc, p_data, base_dir);
    defer env_map.deinit();

    // Make junctions (mklink /J)
    for (config.stubborn_folders) |folder| {
        _ = folder; // Logic mklink có thể triển khai ở đây
    }

    // Run Exe với đường dẫn tuyệt đối
    const exe_abs = try std.fs.path.join(alloc, &.{ base_dir_path, config.selected_exe });
    var child = std.process.Child.init(&.{ exe_abs }, alloc);
    child.env_map = &env_map;
    _ = try child.spawnAndWait();

    // Export Registry (Đồng bộ sau khi tiến trình thoát)
    for (config.registry_keys) |key| {
        var export_cmd = std.process.Child.init(&.{ "reg", "export", key, reg_backup_abs, "/y" }, alloc);
        _ = try export_cmd.spawnAndWait();
        
        var del_cmd = std.process.Child.init(&.{ "reg", "delete", key, "/f" }, alloc);
        _ = try del_cmd.spawnAndWait();
    }
}
