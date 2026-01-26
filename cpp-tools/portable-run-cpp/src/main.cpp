#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <conio.h>
#include <fcntl.h>
#include <io.h>

#include <iostream>
#include <filesystem>
#include <fstream>
#include <vector>
#include <string>
#include <set>
#include <algorithm>
#include <thread>
#include <chrono>

// Đảm bảo bạn đã có file này (xem hướng dẫn trên)
#include <nlohmann/json.hpp>

namespace fs = std::filesystem;
using json = nlohmann::json;
using namespace std::chrono_literals;

// --- CONSTANTS ---
const std::vector<std::wstring> NOISE_KEYWORDS = {
    L"microsoft", L"windows", L"nvidia", L"amd", L"intel", L"realtek", 
    L"cache", L"temp", L"logs", L"crash", L"telemetry", L"onedrive", L"unity", L"squirrel"
};

const DWORD CREATE_NO_WINDOW_FLAG = 0x08000000;

// --- CONFIG STRUCTURES ---
struct StubbornFolder {
    std::string tag;
    std::string name;
};

struct AppConfig {
    std::string selected_exe;
    std::vector<std::string> registry_keys;
    std::vector<StubbornFolder> stubborn_folders;

    NLOHMANN_DEFINE_TYPE_INTRUSIVE(StubbornFolder, tag, name)
    NLOHMANN_DEFINE_TYPE_INTRUSIVE(AppConfig, selected_exe, registry_keys, stubborn_folders)
};

// --- WIN API & UTILS ---
class WinUtils {
public:
    static void HideConsole() {
        HWND hwnd = GetConsoleWindow();
        if (hwnd) {
            // SW_HIDE = 0: Ẩn hoàn toàn khỏi Taskbar
            ShowWindow(hwnd, SW_HIDE);
        }
    }

    static void FocusConsole() {
        if (!GetConsoleWindow()) AllocConsole();
        HWND hwnd = GetConsoleWindow();
        if (!hwnd) return;

        // --- KỸ THUẬT FORCE FOCUS + ANIMATION (Fix #3) ---
        HWND hForeground = GetForegroundWindow();
        DWORD curThreadId = GetCurrentThreadId();
        DWORD foreThreadId = GetWindowThreadProcessId(hForeground, nullptr);
        bool attached = false;

        if (foreThreadId != curThreadId) {
            attached = AttachThreadInput(foreThreadId, curThreadId, TRUE);
        }

        // Bước 1: Minimize trước để đưa về trạng thái "dưới taskbar"
        ShowWindow(hwnd, SW_SHOWMINIMIZED);
        
        // Bước 2: Restore để kích hoạt hiệu ứng Zoom-in của Windows
        ShowWindow(hwnd, SW_RESTORE);

        // Bước 3: Set Focus
        SetForegroundWindow(hwnd);

        if (attached) {
            AttachThreadInput(foreThreadId, curThreadId, FALSE);
        }
    }

    static void GrantFocus() {
        AllowSetForegroundWindow(ASFW_ANY);
    }

    static std::wstring GetCurrentExeName() {
        wchar_t buffer[MAX_PATH];
        GetModuleFileNameW(NULL, buffer, MAX_PATH);
        return fs::path(buffer).filename().wstring();
    }

    // Chạy lệnh CMD ẩn
    static void RunCmdSilent(const std::wstring& cmdArgs) {
        STARTUPINFOW si = { sizeof(si) };
        PROCESS_INFORMATION pi = { 0 };
        si.dwFlags = STARTF_USESHOWWINDOW;
        si.wShowWindow = SW_HIDE;

        // Cần copy string vì CreateProcess có thể thay đổi buffer
        std::wstring cmd = L"cmd.exe /C " + cmdArgs;
        
        if (CreateProcessW(nullptr, &cmd[0], nullptr, nullptr, FALSE, CREATE_NO_WINDOW_FLAG, nullptr, nullptr, &si, &pi)) {
            WaitForSingleObject(pi.hProcess, INFINITE);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
        }
    }

    static std::wstring ToWString(const std::string& s) {
        if (s.empty()) return L"";
        int size_needed = MultiByteToWideChar(CP_UTF8, 0, &s[0], (int)s.size(), NULL, 0);
        std::wstring wstrTo(size_needed, 0);
        MultiByteToWideChar(CP_UTF8, 0, &s[0], (int)s.size(), &wstrTo[0], size_needed);
        return wstrTo;
    }
};

// --- ENGINE CLASS ---
class Engine {
public:
    fs::path root;
    fs::path p_data;
    fs::path cfg_file;
    fs::path reg_backup;
    std::vector<std::pair<std::string, fs::path>> sys_roots;

    Engine() {
        // Tối ưu hóa: Dùng wpath để handle Unicode chính xác
        root = fs::current_path();
        p_data = root / "Portable_Data";
        cfg_file = p_data / "config" / "config.json";
        reg_backup = p_data / "Registry" / "data.reg";

        sys_roots = {
            {"ROAM", GetEnvPath(L"APPDATA")},
            {"LOCAL", GetEnvPath(L"LOCALAPPDATA")},
            // Giả định UserProfile/AppData/LocalLow
            {"LOW",  GetEnvPath(L"USERPROFILE") / "AppData" / "LocalLow"}, 
            {"DOCS", GetDocsPath()}
        };
    }

    void Bootstrap() {
        fs::create_directories(p_data / "config");
        fs::create_directories(p_data / "Registry");
    }

    fs::path MapPortPath(const std::string& tag, const std::string& name) {
        fs::path base = p_data;
        if (tag == "ROAM") return base / "AppData" / "Roaming" / name;
        if (tag == "LOCAL") return base / "AppData" / "Local" / name;
        if (tag == "LOW")  return base / "AppData" / "LocalLow" / name;
        return base / "Documents" / name;
    }

    void SetupEnv() {
        fs::path roam = p_data / "AppData" / "Roaming";
        fs::path local = p_data / "AppData" / "Local";
        fs::path docs = p_data / "Documents";

        if (!fs::exists(roam)) fs::create_directories(roam);
        if (!fs::exists(local)) fs::create_directories(local);
        if (!fs::exists(docs)) fs::create_directories(docs);

        SetEnv(L"APPDATA", roam);
        SetEnv(L"LOCALAPPDATA", local);
        SetEnv(L"USERPROFILE", p_data);
        SetEnv(L"DOCUMENTS", docs);
    }

    std::set<std::wstring> SnapshotFolders() {
        std::set<std::wstring> s;
        for (const auto& [tag, root_path] : sys_roots) {
            if (fs::exists(root_path)) {
                for (const auto& entry : fs::directory_iterator(root_path)) {
                    if (entry.is_directory()) {
                        std::wstring key = WinUtils::ToWString(tag) + L"|" + entry.path().filename().wstring();
                        s.insert(key);
                    }
                }
            }
        }
        return s;
    }

    std::set<std::wstring> SnapshotRegistry() {
        std::set<std::wstring> s;
        HKEY hKey;
        if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software", 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
            wchar_t achKey[255]; 
            DWORD cbName; 
            DWORD cSubKeys = 0;
            RegQueryInfoKey(hKey, NULL, NULL, NULL, &cSubKeys, NULL, NULL, NULL, NULL, NULL, NULL, NULL);

            for (DWORD i = 0; i < cSubKeys; i++) {
                cbName = 255;
                if (RegEnumKeyExW(hKey, i, achKey, &cbName, NULL, NULL, NULL, NULL) == ERROR_SUCCESS) {
                    s.insert(std::wstring(L"HKEY_CURRENT_USER\\Software\\") + achKey);
                }
            }
            RegCloseKey(hKey);
        }
        return s;
    }

    void SyncRegistry(const std::vector<std::string>& keys) {
        if (keys.empty()) return;
        
        fs::remove(reg_backup); // Xóa cũ
        fs::path temp_reg = fs::temp_directory_path() / "port_tmp.reg";

        // Export và Gộp file
        // Tối ưu: Mở file stream một lần để append
        std::ofstream final_out(reg_backup, std::ios::binary | std::ios::app);
        
        for (const auto& k : keys) {
            std::wstring wk = WinUtils::ToWString(k);
            std::wstring cmd = L"reg export \"" + wk + L"\" \"" + temp_reg.wstring() + L"\" /y";
            WinUtils::RunCmdSilent(cmd);

            if (fs::exists(temp_reg)) {
                std::ifstream tmp_in(temp_reg, std::ios::binary);
                final_out << tmp_in.rdbuf();
                tmp_in.close();
                fs::remove(temp_reg);
            }
            
            // Xóa khỏi máy thật
            WinUtils::RunCmdSilent(L"reg delete \"" + wk + L"\" /f");
        }
    }

private:
    fs::path GetEnvPath(const wchar_t* var) {
        wchar_t buf[32767];
        GetEnvironmentVariableW(var, buf, 32767);
        return fs::path(buf);
    }

    fs::path GetDocsPath() {
        wchar_t path[MAX_PATH];
        if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_MYDOCUMENTS, NULL, 0, path))) {
            return fs::path(path);
        }
        return GetEnvPath(L"USERPROFILE") / "Documents";
    }

    void SetEnv(const wchar_t* name, const fs::path& val) {
        SetEnvironmentVariableW(name, val.c_str());
    }
};

// --- UI HELPERS (Minimal TUI) ---
size_t SelectMenu(const std::string& prompt, const std::vector<std::wstring>& items) {
    size_t selected = 0;
    while (true) {
        system("cls");
        std::cout << prompt << "\n\n";
        for (size_t i = 0; i < items.size(); ++i) {
            if (i == selected) std::cout << " > "; else std::cout << "   ";
            std::wcout << items[i] << L"\n";
        }
        
        int c = _getch();
        if (c == 224) { // Arrow keys
            switch (_getch()) {
                case 72: if (selected > 0) selected--; else selected = items.size()-1; break; // Up
                case 80: if (selected < items.size()-1) selected++; else selected = 0; break; // Down
            }
        } else if (c == 13) { // Enter
            return selected;
        }
    }
}

std::vector<size_t> MultiSelectMenu(const std::string& prompt, const std::vector<std::wstring>& items) {
    std::vector<bool> checked(items.size(), false);
    size_t cursor = 0;
    while (true) {
        system("cls");
        std::cout << prompt << " (Space: Toggle, Enter: Confirm)\n\n";
        for (size_t i = 0; i < items.size(); ++i) {
            if (i == cursor) std::cout << " > ["; else std::cout << "   [";
            std::cout << (checked[i] ? "X" : " ") << "] ";
            std::wcout << items[i] << L"\n";
        }

        int c = _getch();
        if (c == 224) {
            switch (_getch()) {
                case 72: if (cursor > 0) cursor--; else cursor = items.size()-1; break;
                case 80: if (cursor < items.size()-1) cursor++; else cursor = 0; break;
            }
        } else if (c == 32) { // Space
            checked[cursor] = !checked[cursor];
        } else if (c == 13) { // Enter
            std::vector<size_t> result;
            for (size_t i = 0; i < items.size(); ++i) if (checked[i]) result.push_back(i);
            return result;
        }
    }
}

// --- MODES ---
void RunSandbox(Engine& engine, const AppConfig& config) {
    // SỬA ĐỔI 1.C: Chỉ bootstrap khi chạy sandbox
    engine.Bootstrap();

    if (!config.registry_keys.empty() && fs::exists(engine.reg_backup)) {
        WinUtils::RunCmdSilent(L"reg import \"" + engine.reg_backup.wstring() + L"\"");
    }

    std::vector<fs::path> junctions;
    for (const auto& f : config.stubborn_folders) {
        // Tìm path gốc
        fs::path origin;
        for (auto& [t, p] : engine.sys_roots) {
            if (t == f.tag) { origin = p / f.name; break; }
        }
        fs::path dest = engine.MapPortPath(f.tag, f.name);

        if (!fs::exists(origin)) {
            // Tạo Junction bằng mklink (Tương thích tốt nhất mà không cần lib ngoài)
            // Lệnh: mklink /J "Link" "Target"
            std::wstring cmd = L"mklink /J \"" + origin.wstring() + L"\" \"" + dest.wstring() + L"\"";
            WinUtils::RunCmdSilent(cmd);
            junctions.push_back(origin);
        }
    }

    engine.SetupEnv();
    WinUtils::GrantFocus();
    WinUtils::HideConsole();

    std::wstring exeW = WinUtils::ToWString(config.selected_exe);
    
    // Chạy EXE
    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi = { 0 };
    wchar_t cmdLine[32767];
    wcscpy_s(cmdLine, exeW.c_str());

    if (CreateProcessW(nullptr, cmdLine, nullptr, nullptr, FALSE, 0, nullptr, nullptr, &si, &pi)) {
        WaitForSingleObject(pi.hProcess, INFINITE);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
    }

    // Cleanup
    for (const auto& j : junctions) fs::remove(j); // Remove junction point
    engine.SyncRegistry(config.registry_keys);
}

void LearningMode(Engine& engine) {
    // SỬA ĐỔI 2: Tự động detect tên file exe hiện tại để loại trừ
    std::wstring selfName = WinUtils::GetCurrentExeName();
    std::transform(selfName.begin(), selfName.end(), selfName.begin(), ::towlower);

    std::vector<std::wstring> exes;
    for (const auto& entry : fs::directory_iterator(".")) {
        if (entry.path().extension() == ".exe") {
            std::wstring name = entry.path().filename().wstring();
            std::wstring lower = name;
            std::transform(lower.begin(), lower.end(), lower.begin(), ::towlower);
            
            // Lọc chính mình
            if (lower != selfName) {
                exes.push_back(name);
            }
        }
    }

    if (exes.empty()) {
        WinUtils::FocusConsole();
        std::cout << "[ERROR] No executable found.\n";
        std::this_thread::sleep_for(3s);
        return; // SỬA ĐỔI 1.A: Thoát ngay, không tạo folder rác
    }

    // SỬA ĐỔI 1.B: Có file rồi mới tạo folder
    engine.Bootstrap();

    std::wstring selected_exe;
    if (exes.size() == 1) {
        WinUtils::HideConsole();
        selected_exe = exes[0];
    } else {
        WinUtils::FocusConsole();
        size_t idx = SelectMenu("Select target:", exes);
        WinUtils::HideConsole(); // Sửa đổi 3: Ẩn ngay sau khi chọn
        selected_exe = exes[idx];
    }

    // Snapshot
    auto reg_before = engine.SnapshotRegistry();
    auto folders_before = engine.SnapshotFolders();

    engine.SetupEnv();
    WinUtils::GrantFocus();
    WinUtils::HideConsole(); // Đảm bảo ẩn

    // Chạy EXE
    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi = { 0 };
    wchar_t cmdLine[32767];
    wcscpy_s(cmdLine, selected_exe.c_str());

    if (CreateProcessW(nullptr, cmdLine, nullptr, nullptr, FALSE, 0, nullptr, nullptr, &si, &pi)) {
        WaitForSingleObject(pi.hProcess, INFINITE);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
    }

    std::this_thread::sleep_for(1s);
    auto reg_after = engine.SnapshotRegistry();
    auto folders_after = engine.SnapshotFolders();

    // Diff
    std::vector<std::wstring> reg_candidates;
    for (const auto& k : reg_after) {
        if (reg_before.find(k) == reg_before.end()) {
            std::wstring lower = k;
            std::transform(lower.begin(), lower.end(), lower.begin(), ::towlower);
            bool noise = false;
            for (const auto& n : NOISE_KEYWORDS) if (lower.find(n) != std::wstring::npos) { noise = true; break; }
            if (!noise) reg_candidates.push_back(k);
        }
    }

    std::vector<StubbornFolder> folder_candidates;
    for (const auto& [tag, root_path] : engine.sys_roots) {
        if (fs::exists(root_path)) {
            for (const auto& entry : fs::directory_iterator(root_path)) {
                if (entry.is_directory()) {
                    std::wstring nameW = entry.path().filename().wstring();
                    std::wstring key = WinUtils::ToWString(tag) + L"|" + nameW;
                    
                    if (folders_before.find(key) == folders_before.end() && 
                        folders_after.find(key) != folders_after.end()) {
                        
                        std::wstring lower = nameW;
                        std::transform(lower.begin(), lower.end(), lower.begin(), ::towlower);
                        bool noise = false;
                        for (const auto& n : NOISE_KEYWORDS) if (lower.find(n) != std::wstring::npos) { noise = true; break; }
                        
                        if (!noise) {
                            folder_candidates.push_back({ tag, entry.path().filename().string() });
                        }
                    }
                }
            }
        }
    }

    // Nếu không có gì thay đổi -> Lưu config rỗng & Thoát
    if (reg_candidates.empty() && folder_candidates.empty()) {
        AppConfig cfg;
        cfg.selected_exe = fs::path(selected_exe).string();
        std::ofstream o(engine.cfg_file);
        json j = cfg;
        o << j.dump(4);
        return;
    }

    // Hỏi người dùng
    WinUtils::FocusConsole();
    
    std::vector<std::string> chosen_reg_keys;
    if (!reg_candidates.empty()) {
        auto idxs = MultiSelectMenu("Select Registry Keys to Keep?", reg_candidates);
        for (auto i : idxs) chosen_reg_keys.push_back(fs::path(reg_candidates[i]).string()); // Lưu string UTF8
    }

    std::vector<StubbornFolder> chosen_folders;
    if (!folder_candidates.empty()) {
        std::vector<std::wstring> display_names;
        for (const auto& f : folder_candidates) {
            display_names.push_back(L"[" + WinUtils::ToWString(f.tag) + L"] " + WinUtils::ToWString(f.name));
        }
        auto idxs = MultiSelectMenu("Select Stubborn Folders to Move?", display_names);
        
        for (auto i : idxs) {
            StubbornFolder f = folder_candidates[i];
            chosen_folders.push_back(f);
            
            // Move Folder bằng Robocopy (Reliable nhất)
            fs::path origin;
            for (auto& [t, p] : engine.sys_roots) if (t == f.tag) origin = p / f.name;
            fs::path dest = engine.MapPortPath(f.tag, f.name);
            fs::create_directories(dest.parent_path());

            // Lệnh Robocopy /MOVE /E
            std::wstring cmd = L"robocopy \"" + origin.wstring() + L"\" \"" + dest.wstring() + L"\" /E /MOVE /NFL /NDL /NJH /NJS /R:3 /W:1";
            WinUtils::RunCmdSilent(cmd);
        }
    }

    // Save Config
    AppConfig cfg;
    cfg.selected_exe = fs::path(selected_exe).string();
    cfg.registry_keys = chosen_reg_keys;
    cfg.stubborn_folders = chosen_folders;

    std::ofstream o(engine.cfg_file);
    json j = cfg;
    o << j.dump(4);

    engine.SyncRegistry(chosen_reg_keys);
}

int main() {
    // Hỗ trợ Unicode cho Console output (wcout)
    _setmode(_fileno(stdout), _O_U16TEXT);
    WinUtils::RunCmdSilent(L"chcp 65001");

    Engine engine;

    if (fs::exists(engine.cfg_file)) {
        std::ifstream i(engine.cfg_file);
        json j;
        if (i >> j) {
            AppConfig config = j.get<AppConfig>();
            RunSandbox(engine, config);
            return 0;
        }
    }

    LearningMode(engine);
    return 0;
}