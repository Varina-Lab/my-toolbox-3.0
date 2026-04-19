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

// --- WIN32 API DECLARATIONS (Không phụ thuộc vào std.fs của Zig) ---
extern "kernel32" fn GetConsoleWindow() ?*anyopaque;
extern "user32" fn ShowWindow(hWnd: ?*anyopaque, nCmdShow: i32) win.BOOL;
extern "kernel32" fn AllocConsole() win.BOOL;
extern "kernel32" fn GetModuleFileNameW(hModule: ?*anyopaque, lpFilename: [*]u16, nSize: u32) u32;
extern "kernel32" fn SetCurrentDirectoryW(lpPathName: [*:0]const u16) win.BOOL;

extern "kernel32" fn CreateDirectoryW(lpPathName: [*:0]const u16, lpSecurityAttributes: ?*anyopaque) win.BOOL;
extern "kernel32" fn CreateFileW(lpFileName: [*:0]const u16, dwDesiredAccess: u32, dwShareMode: u32, lpSecurityAttributes: ?*anyopaque, dwCreationDisposition: u32, dwFlagsAndAttributes: u32, hTemplateFile: ?*anyopaque) win.HANDLE;
extern "kernel32" fn ReadFile(hFile: win.HANDLE, lpBuffer: [*]u8, nNumberOfBytesToRead: u32, lpNumberOfBytesRead: ?*u32, lpOverlapped: ?*anyopaque) win.BOOL;
extern "kernel32" fn WriteFile(hFile: win.HANDLE, lpBuffer: [*]const u8, nNumberOfBytesToWrite: u32, lpNumberOfBytesWritten: ?*u32, lpOverlapped: ?*anyopaque) win.BOOL;
extern "kernel32" fn CloseHandle(hObject: win.HANDLE) win.BOOL;
extern "kernel32" fn GetFileSize(hFile: win.HANDLE, lpFileSizeHigh: ?*u32) u32;
extern "kernel32" fn GetFileAttributesW(lpFileName: [*:0]const u16) u32;

const GENERIC_READ = 0x80000000;
const GENERIC_WRITE = 0x40000000;
const OPEN_EXISTING = 3;
const CREATE_ALWAYS = 2;
const FILE_ATTRIBUTE_NORMAL = 128;
const FILE_ATTRIBUTE_DIRECTORY = 16;
const INVALID_HANDLE_VALUE = @as(win.HANDLE, @ptrFromInt(~@as(usize, 0)));
const MAX_PATH = 260;

const WIN32_FIND_DATAW = extern struct {
    dwFileAttributes: u32,
    ftCreationTime: win.FILETIME,
    ftLastAccessTime: win.FILETIME,
    ftLastWriteTime: win.FILETIME,
    nFileSizeHigh: u32,
    nFileSizeLow: u32,
    dwReserved0: u32,
    dwReserved1: u32,
    cFileName: [MAX_PATH]u16,
    cAlternateFileName: [14]u16,
};
extern "kernel32" fn FindFirstFileW(lpFileName: [*:0]const u16, lpFindFileData: *WIN32_FIND_DATAW) win.HANDLE;
extern "kernel32" fn FindNextFileW(hFindFile: win.HANDLE, lpFindFileData: *WIN32_FIND_DATAW) win.BOOL;
extern "kernel32" fn FindClose(hFindFile: win.HANDLE) win.BOOL;

// --- WIN32 HELPER FUNCTIONS ---
fn hideConsole() void {
    if (GetConsoleWindow()) |hwnd| {
        _ = ShowWindow(hwnd, 0);
    }
}

fn showConsole() void {
    _ = AllocConsole();
    if (GetConsoleWindow()) |hwnd| {
        _ = ShowWindow(hwnd, 5); // SW_SHOW
    }
}

fn createDir(alloc: std.mem.Allocator, path: []const u8) void {
    if (std.unicode.utf8ToUtf16LeAllocZ(alloc, path)) |path_w| {
        defer alloc.free(path_w);
        _ = CreateDirectoryW(path_w.ptr, null);
    } else |_| {}
}

fn readFileAlloc(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    const path_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, path);
    defer alloc.free(path_w);
    
    const handle = CreateFileW(path_w.ptr, GENERIC_READ, 1, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null);
    if (handle == INVALID_HANDLE_VALUE) return error.FileNotFound;
    defer _ = CloseHandle(handle);
    
    const size = GetFileSize(handle, null);
    if (size == 0xFFFFFFFF) return error.GetFileSizeFailed;
    
    const buf = try alloc.alloc(u8, size);
    var bytesRead: u32 = 0;
    if (ReadFile(handle, buf.ptr, size, &bytesRead, null) == 0) return error.ReadFailed;
    return buf[0..bytesRead];
}

fn writeFile(alloc: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    const path_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, path);
    defer alloc.free(path_w);
    
    const handle = CreateFileW(path_w.ptr, GENERIC_WRITE, 0, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
    if (handle == INVALID_HANDLE_VALUE) return error.CreateFileFailed;
    defer _ = CloseHandle(handle);
    
    var bytesWritten: u32 = 0;
    if (WriteFile(handle, data.ptr, @intCast(data.len), &bytesWritten, null) == 0) return error.WriteFailed;
}

fn fileExists(alloc: std.mem.Allocator, path: []const u8) bool {
    const path_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, path) catch return false;
    defer alloc.free(path_w);
    const attr = GetFileAttributesW(path_w.ptr);
    return attr != 0xFFFFFFFF;
}

// --- MAIN LOGIC ---
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // 1. Get exact path of this executable
    var exe_path_w: [4096]u16 = undefined;
    const len = GetModuleFileNameW(null, &exe_path_w, 4096);
    if (len == 0) return error.GetModuleFileNameFailed;

    const exe_path = try std.unicode.utf16LeToUtf8Alloc(alloc, exe_path_w[0..len]);
    const base_dir_path = std.fs.path.dirname(exe_path) orelse return error.NoExeDir;

    // 2. Set Current Directory to base_dir_path (Đồng bộ tuyệt đối đường dẫn hiện tại)
    const base_dir_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, base_dir_path);
    _ = SetCurrentDirectoryW(base_dir_w.ptr);

    const p_data = try std.fs.path.join(alloc, &.{ base_dir_path, "Portable_Data" });

    // 3. Ensure base directories exist (Gọi API Windows tạo file/thư mục nền)
    createDir(alloc, "Portable_Data");
    createDir(alloc, "Portable_Data\\config");
    createDir(alloc, "Portable_Data\\Registry");

    // 4. Try loading config
    var has_config = false;
    if (readFileAlloc(alloc, "Portable_Data\\config\\config.json")) |content| {
        const parsed = std.json.parseFromSlice(AppConfig, alloc, content, .{ .ignore_unknown_fields = true }) catch null;
        if (parsed != null) {
            has_config = true;
            try runSandbox(alloc, base_dir_path, p_data, parsed.?.value);
        }
    } else |_| {}

    if (!has_config) {
        try learningMode(alloc, base_dir_path, p_data);
    }
}

fn setupEnvMap(alloc: std.mem.Allocator, p_data: []const u8) !std.process.EnvMap {
    var env_map = try std.process.getEnvMap(alloc);
    const roam = try std.fs.path.join(alloc, &.{ p_data, "AppData", "Roaming" });
    const local = try std.fs.path.join(alloc, &.{ p_data, "AppData", "Local" });
    const docs = try std.fs.path.join(alloc, &.{ p_data, "Documents" });

    createDir(alloc, "Portable_Data\\AppData");
    createDir(alloc, "Portable_Data\\AppData\\Roaming");
    createDir(alloc, "Portable_Data\\AppData\\Local");
    createDir(alloc, "Portable_Data\\Documents");

    try env_map.put("APPDATA", roam);
    try env_map.put("LOCALAPPDATA", local);
    try env_map.put("USERPROFILE", p_data);
    try env_map.put("DOCUMENTS", docs);

    return env_map;
}

fn learningMode(alloc: std.mem.Allocator, base_dir_path: []const u8, p_data: []const u8) !void {
    showConsole();
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    // Lặp tìm File EXE hoàn toàn qua API FindFirstFileW của Windows (bất tử với lỗi fs)
    var exe_list = std.ArrayList([]const u8).init(alloc);
    var findData: WIN32_FIND_DATAW = undefined;
    const search_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, "*.exe");
    const handle = FindFirstFileW(search_w.ptr, &findData);
    
    if (handle != INVALID_HANDLE_VALUE) {
        defer _ = FindClose(handle);
        while (true) {
            if ((findData.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
                var flen: usize = 0;
                while (findData.cFileName[flen] != 0) flen += 1;
                const name = try std.unicode.utf16LeToUtf8Alloc(alloc, findData.cFileName[0..flen]);
                
                if (!std.mem.eql(u8, name, "portable_run.exe")) {
                    try exe_list.append(name);
                }
            }
            if (FindNextFileW(handle, &findData) == 0) break;
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
    
    var env_map = try setupEnvMap(alloc, p_data);
    defer env_map.deinit();

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

    var json_str = std.ArrayList(u8).init(alloc);
    try std.json.stringify(cfg, .{ .whitespace = .indent_4 }, json_str.writer());
    try writeFile(alloc, "Portable_Data\\config\\config.json", json_str.items);

    try stdout.print("[INFO] Config saved to Portable_Data\\config\\config.json\n", .{});
    std.time.sleep(2 * std.time.ns_per_s);
}

fn runSandbox(alloc: std.mem.Allocator, base_dir_path: []const u8, p_data: []const u8, config: AppConfig) !void {
    // hideConsole();
    
    const reg_backup_abs = try std.fs.path.join(alloc, &.{ p_data, "Registry", "data.reg" });
    if (fileExists(alloc, "Portable_Data\\Registry\\data.reg")) {
        var import_cmd = std.process.Child.init(&.{ "reg", "import", reg_backup_abs }, alloc);
        _ = try import_cmd.spawnAndWait();
    }

    var env_map = try setupEnvMap(alloc, p_data);
    defer env_map.deinit();

    for (config.stubborn_folders) |folder| {
        _ = folder; 
    }

    const exe_abs = try std.fs.path.join(alloc, &.{ base_dir_path, config.selected_exe });
    var child = std.process.Child.init(&.{ exe_abs }, alloc);
    child.env_map = &env_map;
    _ = try child.spawnAndWait();

    for (config.registry_keys) |key| {
        var export_cmd = std.process.Child.init(&.{ "reg", "export", key, reg_backup_abs, "/y" }, alloc);
        _ = try export_cmd.spawnAndWait();
        
        var del_cmd = std.process.Child.init(&.{ "reg", "delete", key, "/f" }, alloc);
        _ = try del_cmd.spawnAndWait();
    }
}
