const std = @import("std");
const w32 = std.os.windows;

const CREATE_NO_WINDOW: u32 = 0x08000000;
const NOISE_KEYWORDS = [_][]const u8{
    "microsoft", "windows", "nvidia", "amd", "intel", "realtek", "cache",
    "temp", "logs", "crash", "telemetry", "onedrive", "unity", "squirrel",
};

// --- Windows API Externs ---
extern "kernel32" fn AllocConsole() callconv(.C) w32.BOOL;
extern "kernel32" fn GetConsoleWindow() callconv(.C) w32.HWND;
extern "kernel32" fn GetCurrentThreadId() callconv(.C) w32.DWORD;

extern "user32" fn ShowWindow(hwnd: w32.HWND, nCmdShow: i32) callconv(.C) w32.BOOL;
extern "user32" fn SetForegroundWindow(hwnd: w32.HWND) callconv(.C) w32.BOOL;
extern "user32" fn GetForegroundWindow() callconv(.C) w32.HWND;
extern "user32" fn GetWindowThreadProcessId(hwnd: w32.HWND, lpdwProcessId: ?*w32.DWORD) callconv(.C) w32.DWORD;
extern "user32" fn AttachThreadInput(idAttach: w32.DWORD, idAttachTo: w32.DWORD, fAttach: w32.BOOL) callconv(.C) w32.BOOL;
extern "user32" fn AllowSetForegroundWindow(dwProcessId: w32.DWORD) callconv(.C) w32.BOOL;

extern "advapi32" fn RegOpenKeyExA(hKey: w32.HKEY, lpSubKey: [*:0]const u8, ulOptions: w32.DWORD, samDesired: w32.DWORD, phkResult: *w32.HKEY) callconv(.C) w32.LONG;
extern "advapi32" fn RegEnumKeyExA(hKey: w32.HKEY, dwIndex: w32.DWORD, lpName: [*]u8, lpcchName: *w32.DWORD, lpReserved: ?*w32.DWORD, lpClass: ?[*]u8, lpcchClass: ?*w32.DWORD, lpftLastWriteTime: ?*anyopaque) callconv(.C) w32.LONG;
extern "advapi32" fn RegCloseKey(hKey: w32.HKEY) callconv(.C) w32.LONG;

const win_api = struct {
    fn hide() void {
        const hwnd = GetConsoleWindow();
        if (hwnd != null) {
            _ = ShowWindow(hwnd, 0); // SW_HIDE
        }
    }

    fn focus() void {
        _ = AllocConsole();
        const hwnd = GetConsoleWindow();
        if (hwnd != null) {
            const foreground_hwnd = GetForegroundWindow();
            const current_thread_id = GetCurrentThreadId();
            const foreground_thread_id = GetWindowThreadProcessId(foreground_hwnd, null);

            var attached: w32.BOOL = 0;
            if (foreground_thread_id != current_thread_id) {
                attached = AttachThreadInput(foreground_thread_id, current_thread_id, 1);
            }
            _ = ShowWindow(hwnd, 2); // SW_SHOWMINIMIZED
            _ = ShowWindow(hwnd, 9); // SW_RESTORE
            _ = SetForegroundWindow(hwnd);
            if (attached != 0) {
                _ = AttachThreadInput(foreground_thread_id, current_thread_id, 0);
            }
        }
    }

    fn grant_focus() void {
        _ = AllowSetForegroundWindow(0xFFFFFFFF);
    }
};

// --- Models ---
const StubbornFolder = struct {
    tag: []const u8,
    name: []const u8,
};

const AppConfig = struct {
    selected_exe: []const u8,
    registry_keys: [][]const u8,
    stubborn_folders: []StubbornFolder,
};

const SysRoot = struct {
    tag: []const u8,
    path: []const u8,
};

const Engine = struct {
    allocator: std.mem.Allocator,
    root: []const u8,
    p_data: []const u8,
    cfg_file: []const u8,
    reg_backup: []const u8,
    sys_roots: []SysRoot,

    fn init(alloc: std.mem.Allocator) !Engine {
        var env_map = try alloc.create(std.process.EnvMap);
        env_map.* = try std.process.getEnvMap(alloc);

        const root = try std.fs.cwd().realpathAlloc(alloc, ".");
        const p_data = try std.fs.path.join(alloc, &[_][]const u8{ root, "Portable_Data" });

        var sys_roots = std.ArrayList(SysRoot).init(alloc);
        if (env_map.get("APPDATA")) |appdata| {
            try sys_roots.append(.{ .tag = "ROAM", .path = try alloc.dupe(u8, appdata) });
        }
        if (env_map.get("LOCALAPPDATA")) |local| {
            try sys_roots.append(.{ .tag = "LOCAL", .path = try alloc.dupe(u8, local) });
        }
        if (env_map.get("USERPROFILE")) |user| {
            const low = try std.fs.path.join(alloc, &[_][]const u8{ user, "AppData", "LocalLow" });
            try sys_roots.append(.{ .tag = "LOW", .path = low });
            const docs = try std.fs.path.join(alloc, &[_][]const u8{ user, "Documents" });
            try sys_roots.append(.{ .tag = "DOCS", .path = docs });
        }

        return Engine{
            .allocator = alloc,
            .root = root,
            .p_data = p_data,
            .cfg_file = try std.fs.path.join(alloc, &[_][]const u8{ p_data, "config", "config.json" }),
            .reg_backup = try std.fs.path.join(alloc, &[_][]const u8{ p_data, "Registry", "data.reg" }),
            .sys_roots = try sys_roots.toOwnedSlice(),
        };
    }

    fn bootstrap(self: *const Engine) !void {
        try std.fs.cwd().makePath(try std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "config" }));
        try std.fs.cwd().makePath(try std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "Registry" }));
    }

    fn mapPortPath(self: *const Engine, tag: []const u8, folder_name: []const u8) ![]const u8 {
        if (std.mem.eql(u8, tag, "ROAM")) return std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "AppData", "Roaming", folder_name });
        if (std.mem.eql(u8, tag, "LOCAL")) return std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "AppData", "Local", folder_name });
        if (std.mem.eql(u8, tag, "LOW")) return std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "AppData", "LocalLow", folder_name });
        return std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "Documents", folder_name });
    }

    fn getEnvMap(self: *const Engine) !std.process.EnvMap {
        var env = try std.process.getEnvMap(self.allocator);
        
        const roam = try std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "AppData", "Roaming" });
        const local = try std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "AppData", "Local" });
        const docs = try std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "Documents" });

        try std.fs.cwd().makePath(roam);
        try std.fs.cwd().makePath(local);
        try std.fs.cwd().makePath(docs);

        try env.put("APPDATA", roam);
        try env.put("LOCALAPPDATA", local);
        try env.put("USERPROFILE", self.p_data);
        try env.put("DOCUMENTS", docs);

        return env;
    }

    fn snapshotFolders(self: *const Engine) !std.StringHashMap(void) {
        var set = std.StringHashMap(void).init(self.allocator);
        for (self.sys_roots) |root| {
            var dir = std.fs.openDirAbsolute(root.path, .{ .iterate = true }) catch continue;
            defer dir.close();
            var it = dir.iterate();
            while (try it.next()) |entry| {
                if (entry.kind == .directory) {
                    const key = try std.fmt.allocPrint(self.allocator, "{s}|{s}", .{ root.tag, entry.name });
                    try set.put(key, {});
                }
            }
        }
        return set;
    }

    fn snapshotRegistry(self: *const Engine) !std.StringHashMap(void) {
        var set = std.StringHashMap(void).init(self.allocator);
        var hKey: w32.HKEY = undefined;
        // HKEY_CURRENT_USER = 0x80000001
        const hkcu: w32.HKEY = @ptrFromInt(0x80000001);
        if (RegOpenKeyExA(hkcu, "Software", 0, 0x20019, &hKey) == 0) { // KEY_READ = 0x20019
            defer _ = RegCloseKey(hKey);
            var index: w32.DWORD = 0;
            var nameBuf: [256]u8 = undefined;
            while (true) {
                var nameLen: w32.DWORD = 256;
                const res = RegEnumKeyExA(hKey, index, &nameBuf, &nameLen, null, null, null, null);
                if (res != 0) break; // ERROR_NO_MORE_ITEMS hoặc lỗi khác
                
                const name = nameBuf[0..nameLen];
                const key = try std.fmt.allocPrint(self.allocator, "HKEY_CURRENT_USER\\Software\\{s}", .{name});
                try set.put(key, {});
                index += 1;
            }
        }
        return set;
    }

    fn syncRegistry(self: *const Engine, keys: [][]const u8) !void {
        if (keys.len == 0) return;
        
        std.fs.deleteFileAbsolute(self.reg_backup) catch {};
        
        const tmp_dir = std.os.windows.GetTempPathAlloc(self.allocator) catch "C:\\Temp";
        const temp_reg = try std.fs.path.join(self.allocator, &[_][]const u8{ tmp_dir, "port_tmp.reg" });

        for (keys) |key| {
            var exp_cmd = try std.process.Child.init(&[_][]const u8{ "reg", "export", key, temp_reg, "/y" }, self.allocator);
            exp_cmd.spawn_flags = std.process.Child.SpawnFlags{ .creation_flags = CREATE_NO_WINDOW };
            _ = exp_cmd.spawnAndWait() catch {};

            if (std.fs.openFileAbsolute(temp_reg, .{})) |tmp_file| {
                const content = try tmp_file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
                tmp_file.close();

                var out_file = std.fs.cwd().openFile(self.reg_backup, .{ .mode = .read_write }) catch blk: {
                    break :blk try std.fs.cwd().createFile(self.reg_backup, .{});
                };
                try out_file.seekFromEnd(0);
                try out_file.writer().writeAll(content);
                out_file.close();

                std.fs.deleteFileAbsolute(temp_reg) catch {};
            }

            var del_cmd = try std.process.Child.init(&[_][]const u8{ "reg", "delete", key, "/f" }, self.allocator);
            del_cmd.spawn_flags = std.process.Child.SpawnFlags{ .creation_flags = CREATE_NO_WINDOW };
            _ = del_cmd.spawnAndWait() catch {};
        }
    }
};

// --- Helpers ---
fn isNoise(name: []const u8) bool {
    var lower_buf: [256]u8 = undefined;
    const len = @min(name.len, 256);
    const lower = std.ascii.lowerString(&lower_buf, name[0..len]);
    for (NOISE_KEYWORDS) |kw| {
        if (std.mem.indexOf(u8, lower, kw) != null) return true;
    }
    return false;
}

fn promptSelect(alloc: std.mem.Allocator, items: [][]const u8, prompt: []const u8) !usize {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    
    try stdout.print("{s}:\n", .{prompt});
    for (items, 0..) |item, i| {
        try stdout.print("[{d}] {s}\n", .{ i, item });
    }
    
    var buf: [32]u8 = undefined;
    while (true) {
        try stdout.print("Enter choice (0-{d}): ", .{items.len - 1});
        if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            const trimmed = std.mem.trim(u8, line, " \r");
            if (std.fmt.parseInt(usize, trimmed, 10)) |val| {
                if (val < items.len) return val;
            } else |_| {}
        }
    }
}

fn promptMultiSelect(alloc: std.mem.Allocator, items: [][]const u8, prompt: []const u8) ![]usize {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    
    try stdout.print("{s}:\n", .{prompt});
    for (items, 0..) |item, i| {
        try stdout.print("[{d}] {s}\n", .{ i, item });
    }
    
    var selected = std.ArrayList(usize).init(alloc);
    var buf: [256]u8 = undefined;
    try stdout.print("Enter indices separated by space (e.g. '0 2'): ", .{});
    
    if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        var it = std.mem.splitAny(u8, trimmed, " ,");
        while (it.next()) |part| {
            if (part.len == 0) continue;
            if (std.fmt.parseInt(usize, part, 10)) |val| {
                if (val < items.len) try selected.append(val);
            } else |_| {}
        }
    }
    return selected.toOwnedSlice();
}

pub fn main() !void {
    // Setup memory arena for easy cleanup
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    _ = std.process.Child.spawnAndWait(&std.process.Child.init(&[_][]const u8{"cmd", "/c", "chcp 65001"}, alloc)) catch {};

    var engine = try Engine.init(alloc);
    
    if (std.fs.cwd().openFile(engine.cfg_file, .{})) |file| {
        const content = try file.readToEndAlloc(alloc, 1024 * 1024);
        file.close();
        
        if (std.json.parseFromSlice(AppConfig, alloc, content, .{ .ignore_unknown_fields = true })) |parsed| {
            try run_sandbox(&engine, parsed.value);
            return;
        } else |_| {
            // Failed to parse config, fallback to learning mode
        }
    } else |_| {}

    try learning_mode(&engine, alloc);
}

fn learning_mode(engine: *const Engine, alloc: std.mem.Allocator) !void {
    const cur_exe_path = try std.fs.selfExePathAlloc(alloc);
    const cur_exe_name = std.fs.path.basename(cur_exe_path);
    
    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    var exes = std.ArrayList([]const u8).init(alloc);
    var it = dir.iterate();
    
    while (try it.next()) |entry| {
        if (entry.kind == .file and std.ascii.endsWithIgnoreCase(entry.name, ".exe")) {
            if (!std.ascii.eqlIgnoreCase(entry.name, cur_exe_name)) {
                try exes.append(try alloc.dupe(u8, entry.name));
            }
        }
    }

    if (exes.items.len == 0) {
        win_api.focus();
        std.debug.print("[ERROR] No executable found.\n", .{});
        std.time.sleep(3 * std.time.ns_per_s);
        return;
    }

    try engine.bootstrap();

    var selected_exe: []const u8 = undefined;
    if (exes.items.len == 1) {
        win_api.hide();
        selected_exe = exes.items[0];
    } else {
        win_api.focus();
        const choice = try promptSelect(alloc, exes.items, "Select target");
        win_api.hide();
        selected_exe = exes.items[choice];
    }

    var reg_before = try engine.snapshotRegistry();
    var folders_before = try engine.snapshotFolders();

    const new_env = try engine.getEnvMap();
    win_api.grant_focus();
    win_api.hide();

    // Spawn child
    var child = std.process.Child.init(&[_][]const u8{selected_exe}, alloc);
    child.env_map = &new_env;
    _ = try child.spawnAndWait();
    
    std.time.sleep(1 * std.time.ns_per_s);

    var reg_after = try engine.snapshotRegistry();
    var folders_after = try engine.snapshotFolders();

    var reg_candidates = std.ArrayList([]const u8).init(alloc);
    var reg_it = reg_after.keyIterator();
    while (reg_it.next()) |k| {
        if (!reg_before.contains(k.*) and !isNoise(k.*)) {
            try reg_candidates.append(k.*);
        }
    }

    var stubborn_candidates = std.ArrayList(StubbornFolder).init(alloc);
    for (engine.sys_roots) |root| {
        var s_dir = std.fs.openDirAbsolute(root.path, .{ .iterate = true }) catch continue;
        var s_it = s_dir.iterate();
        while (try s_it.next()) |entry| {
            if (entry.kind != .directory) continue;
            if (isNoise(entry.name)) continue;
            
            const key = try std.fmt.allocPrint(alloc, "{s}|{s}", .{ root.tag, entry.name });
            if (!folders_before.contains(key) and folders_after.contains(key)) {
                try stubborn_candidates.append(.{ .tag = root.tag, .name = try alloc.dupe(u8, entry.name) });
            }
        }
    }

    if (reg_candidates.items.len == 0 and stubborn_candidates.items.len == 0) {
        try saveConfig(alloc, engine.cfg_file, selected_exe, &[_][]const u8{}, &[_]StubbornFolder{});
        return;
    }

    win_api.focus();
    var selected_reg = std.ArrayList([]const u8).init(alloc);
    if (reg_candidates.items.len > 0) {
        const indices = try promptMultiSelect(alloc, reg_candidates.items, "Select Registry?");
        for (indices) |i| try selected_reg.append(reg_candidates.items[i]);
    }

    var selected_folders = std.ArrayList(StubbornFolder).init(alloc);
    if (stubborn_candidates.items.len > 0) {
        var names = std.ArrayList([]const u8).init(alloc);
        for (stubborn_candidates.items) |f| {
            try names.append(try std.fmt.allocPrint(alloc, "[{s}] {s}", .{ f.tag, f.name }));
        }
        const indices = try promptMultiSelect(alloc, names.items, "Select Folders?");
        for (indices) |i| {
            const f = stubborn_candidates.items[i];
            
            var origin: []const u8 = undefined;
            for (engine.sys_roots) |r| {
                if (std.mem.eql(u8, r.tag, f.tag)) {
                    origin = try std.fs.path.join(alloc, &[_][]const u8{ r.path, f.name });
                    break;
                }
            }
            const dest = try engine.mapPortPath(f.tag, f.name);
            
            if (std.fs.path.dirname(dest)) |parent| try std.fs.cwd().makePath(parent);
            
            var robo = std.process.Child.init(&[_][]const u8{ "robocopy", origin, dest, "/E", "/MOVE", "/NFL", "/NDL", "/NJH", "/NJS", "/R:3", "/W:1" }, alloc);
            robo.spawn_flags = std.process.Child.SpawnFlags{ .creation_flags = CREATE_NO_WINDOW };
            _ = robo.spawnAndWait() catch {};
            
            try selected_folders.append(f);
        }
    }

    try saveConfig(alloc, engine.cfg_file, selected_exe, selected_reg.items, selected_folders.items);
    try engine.syncRegistry(selected_reg.items);
}

fn run_sandbox(engine: *const Engine, config: AppConfig) !void {
    const alloc = engine.allocator;
    try engine.bootstrap();

    if (config.registry_keys.len == 0 and config.stubborn_folders.len == 0) {
        const new_env = try engine.getEnvMap();
        win_api.grant_focus();
        var child = std.process.Child.init(&[_][]const u8{config.selected_exe}, alloc);
        child.env_map = &new_env;
        _ = try child.spawnAndWait();
        return;
    }

    if (std.fs.cwd().access(engine.reg_backup, .{})) |_| {
        var imp = std.process.Child.init(&[_][]const u8{ "reg", "import", engine.reg_backup }, alloc);
        imp.spawn_flags = std.process.Child.SpawnFlags{ .creation_flags = CREATE_NO_WINDOW };
        _ = imp.spawnAndWait() catch {};
    } else |_| {}

    var junctions = std.ArrayList([]const u8).init(alloc);
    for (config.stubborn_folders) |f| {
        var origin: []const u8 = undefined;
        for (engine.sys_roots) |r| {
            if (std.mem.eql(u8, r.tag, f.tag)) {
                origin = try std.fs.path.join(alloc, &[_][]const u8{ r.path, f.name });
                break;
            }
        }
        const dest = try engine.mapPortPath(f.tag, f.name);
        
        if (std.fs.cwd().access(origin, .{})) |_| {} else |_| {
            // Create junction using cmd mklink /J
            var mklink = std.process.Child.init(&[_][]const u8{ "cmd", "/c", "mklink", "/J", origin, dest }, alloc);
            mklink.spawn_flags = std.process.Child.SpawnFlags{ .creation_flags = CREATE_NO_WINDOW };
            _ = mklink.spawnAndWait() catch {};
            try junctions.append(origin);
        }
    }

    const new_env = try engine.getEnvMap();
    win_api.grant_focus();
    win_api.hide();

    var child = std.process.Child.init(&[_][]const u8{config.selected_exe}, alloc);
    child.env_map = &new_env;
    _ = try child.spawnAndWait();

    for (junctions.items) |j| {
        std.fs.deleteDirAbsolute(j) catch {};
    }

    try engine.syncRegistry(config.registry_keys);
}

fn saveConfig(alloc: std.mem.Allocator, path: []const u8, exe: []const u8, reg: [][]const u8, folders: []const StubbornFolder) !void {
    const config = AppConfig{
        .selected_exe = exe,
        .registry_keys = reg,
        .stubborn_folders = folders,
    };
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try std.json.stringify(config, .{ .whitespace = .indent_4 }, file.writer());
}
