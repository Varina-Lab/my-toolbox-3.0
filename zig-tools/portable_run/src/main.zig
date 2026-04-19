const std = @import("std");

// --- Win32 API Bindings (Tự định nghĩa để không phụ thuộc vào std.os.windows biến động) ---
const HWND = ?*anyopaque;
const DWORD = u32;
const BOOL = i32;

extern "kernel32" fn AllocConsole() callconv(.C) BOOL;
extern "kernel32" fn GetConsoleWindow() callconv(.C) HWND;
extern "kernel32" fn GetCurrentThreadId() callconv(.C) DWORD;
extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.C) BOOL;
extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.C) BOOL;
extern "user32" fn GetForegroundWindow() callconv(.C) HWND;
extern "user32" fn GetWindowThreadProcessId(hWnd: HWND, lpdwProcessId: ?*DWORD) callconv(.C) DWORD;
extern "user32" fn AttachThreadInput(idAttach: DWORD, idAttachTo: DWORD, fAttach: BOOL) callconv(.C) BOOL;
extern "user32" fn AllowSetForegroundWindow(dwProcessId: DWORD) callconv(.C) BOOL;

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

            var attached: bool = false;
            if (foreground_thread_id != current_thread_id) {
                attached = AttachThreadInput(foreground_thread_id, current_thread_id, 1) != 0;
            }

            _ = ShowWindow(hwnd, 2); // SW_SHOWMINIMIZED
            _ = ShowWindow(hwnd, 9); // SW_RESTORE
            _ = SetForegroundWindow(hwnd);

            if (attached) {
                _ = AttachThreadInput(foreground_thread_id, current_thread_id, 0);
            }
        }
    }

    fn grant_focus() void {
        _ = AllowSetForegroundWindow(0xFFFFFFFF);
    }
};

const NOISE_KEYWORDS = [_][]const u8{
    "microsoft", "windows", "nvidia", "amd", "intel", "realtek", "cache",
    "temp", "logs", "crash", "telemetry", "onedrive", "unity", "squirrel",
};

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

    fn init(allocator: std.mem.Allocator) !Engine {
        const root = try std.fs.cwd().realpathAlloc(allocator, ".");
        const p_data = try std.fs.path.join(allocator, &[_][]const u8{ root, "Portable_Data" });
        
        var sys_roots: std.ArrayListUnmanaged(SysRoot) = .empty;
        
        if (std.process.getEnvVarOwned(allocator, "APPDATA")) |appdata| {
            try sys_roots.append(allocator, .{ .tag = "ROAM", .path = appdata });
        } else |_| {}
        
        if (std.process.getEnvVarOwned(allocator, "LOCALAPPDATA")) |localappdata| {
            try sys_roots.append(allocator, .{ .tag = "LOCAL", .path = localappdata });
        } else |_| {}

        return Engine{
            .allocator = allocator,
            .root = root,
            .p_data = p_data,
            .cfg_file = try std.fs.path.join(allocator, &[_][]const u8{ p_data, "config", "config.json" }),
            .reg_backup = try std.fs.path.join(allocator, &[_][]const u8{ p_data, "Registry", "data.reg" }),
            .sys_roots = try sys_roots.toOwnedSlice(allocator),
        };
    }

    fn bootstrap(self: Engine) !void {
        const config_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "config" });
        const reg_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "Registry" });
        try std.fs.cwd().makePath(config_dir);
        try std.fs.cwd().makePath(reg_dir);
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    _ = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "cmd", "/c", "chcp", "65001" },
    });

    const engine = try Engine.init(allocator);

    if (std.fs.cwd().openFile(engine.cfg_file, .{})) |file| {
        defer file.close();
        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        
        const parsed = try std.json.parseFromSlice(AppConfig, allocator, content, .{});
        defer parsed.deinit();

        try run_sandbox(allocator, engine, parsed.value);
        return;
    } else |_| {
        try learning_mode(allocator, engine);
    }
}

fn learning_mode(allocator: std.mem.Allocator, engine: Engine) !void {
    win_api.focus();
    std.debug.print("Entering learning mode (Zig Port)...\n", .{});
    
    try engine.bootstrap();
    win_api.hide();
    win_api.grant_focus();
    
    const empty_config = AppConfig{
        .selected_exe = "example.exe",
        .registry_keys = &[_][]const u8{},
        .stubborn_folders = &[_]StubbornFolder{},
    };
    
    // CẬP NHẬT: Thay thế stringifyAlloc bằng quy trình chuẩn mới của Zig 0.15
    var json_str = std.ArrayList(u8).init(allocator);
    defer json_str.deinit();
    try std.json.stringify(empty_config, .{ .whitespace = .indent_4 }, json_str.writer());
    
    if (std.fs.cwd().createFile(engine.cfg_file, .{ .truncate = true })) |file| {
        defer file.close();
        try file.writeAll(json_str.items); // Ghi nội dung json từ ArrayList ra file
    } else |err| {
        std.debug.print("Failed to write config: {}\n", .{err});
    }
}

fn run_sandbox(allocator: std.mem.Allocator, engine: Engine, config: AppConfig) !void {
    _ = allocator; 
    
    try engine.bootstrap();
    std.debug.print("Running sandbox for: {s}\n", .{config.selected_exe});
    win_api.hide();
}
