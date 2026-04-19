const std = @import("std");
const windows = std.os.windows;
const WINAPI = windows.WINAPI;
const HWND = windows.HWND;
const DWORD = windows.DWORD;
const BOOL = windows.BOOL;

// --- Win32 API Bindings ---
extern "kernel32" fn AllocConsole() callconv(WINAPI) BOOL;
extern "kernel32" fn GetConsoleWindow() callconv(WINAPI) HWND;
extern "kernel32" fn GetCurrentThreadId() callconv(WINAPI) DWORD;
extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(WINAPI) BOOL;
extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(WINAPI) BOOL;
extern "user32" fn GetForegroundWindow() callconv(WINAPI) HWND;
extern "user32" fn GetWindowThreadProcessId(hWnd: HWND, lpdwProcessId: ?*DWORD) callconv(WINAPI) DWORD;
extern "user32" fn AttachThreadInput(idAttach: DWORD, idAttachTo: DWORD, fAttach: BOOL) callconv(WINAPI) BOOL;
extern "user32" fn AllowSetForegroundWindow(dwProcessId: DWORD) callconv(WINAPI) BOOL;

const win_api = struct {
    fn hide() void {
        const hwnd = GetConsoleWindow();
        if (hwnd != @as(HWND, @ptrFromInt(0))) {
            _ = ShowWindow(hwnd, 0); // SW_HIDE
        }
    }

    fn focus() void {
        _ = AllocConsole();
        const hwnd = GetConsoleWindow();
        if (hwnd != @as(HWND, @ptrFromInt(0))) {
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
        
        // CẬP NHẬT: Sử dụng ArrayListUnmanaged thay thế cho ArrayList để tương thích Zig 0.15
        var sys_roots: std.ArrayListUnmanaged(SysRoot) = .empty;
        
        if (std.process.getEnvVarOwned(allocator, "APPDATA")) |appdata| {
            // Unmanaged yêu cầu truyền allocator vào mỗi thao tác thay đổi dữ liệu
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
    
    const config_str = try std.json.stringifyAlloc(allocator, empty_config, .{ .whitespace = .indent_4 });
    
    if (std.fs.cwd().createFile(engine.cfg_file, .{ .truncate = true })) |file| {
        defer file.close();
        try file.writeAll(config_str);
    } else |err| {
        std.debug.print("Failed to write config: {}\n", .{err});
    }
}

fn run_sandbox(allocator: std.mem.Allocator, engine: Engine, config: AppConfig) !void {
    // CẬP NHẬT: Đánh dấu `allocator` là đã sử dụng để tránh lỗi strict của Zig
    _ = allocator; 
    
    try engine.bootstrap();
    std.debug.print("Running sandbox for: {s}\n", .{config.selected_exe});
    win_api.hide();
}
