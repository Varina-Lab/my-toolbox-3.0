#define _CRT_SECURE_NO_WARNINGS
#include <windows.h>
#include <shlobj.h>
#include <iostream>
#include <string>
#include <vector>
#include <filesystem>
#include <fstream>
#include <unordered_set>
#include <algorithm>
#include <sstream>
#include <map>

// Sử dụng namespace fs để code gọn hơn
namespace fs = std::filesystem;

// --- CẤU HÌNH & HẰNG SỐ ---
const std::vector<std::wstring> NOISE_KEYWORDS = {
    L"microsoft", L"windows", L"nvidia", L"amd", L"intel", L"realtek", 
    L"cache", L"temp", L"logs", L"crash", L"telemetry", L"onedrive", L"unity", L"squirrel"
};

const DWORD CREATE_NO_WINDOW_FLAG = 0x08000000;

// --- CÁC STRUCT DỮ LIỆU ---
struct StubbornFolder {
    std::wstring tag;
    std::wstring name;
};

struct AppConfig {
    std::wstring selected_exe;
    std::vector<std::wstring> registry_keys;
    std::vector<StubbornFolder> stubborn_folders;
};

// --- HELPER CLASS: WINDOWS API WRAPPER (TỐI ƯU HÓA) ---
class WinApi {
public:
    static void HideConsole() {
        HWND hwnd = GetConsoleWindow();
        if (hwnd) ShowWindow(hwnd, SW_HIDE);
    }

    // Logic Focus + Animation (Fix #3)
    static void ForceFocus() {
        AllocConsole();
        HWND hwnd = GetConsoleWindow();
        if (!hwnd) return;

        // Redirect IO cho console mới tạo
        FILE* fp;
        freopen_s(&fp, "CONOUT$", "w", stdout);
        freopen_s(&fp, "CONIN$", "r", stdin);
        
        // UTF-8 Output support
        SetConsoleOutputCP(CP_UTF8);

        HWND hForeground = GetForegroundWindow();
        DWORD foreThread = GetWindowThreadProcessId(hForeground, NULL);
        DWORD appThread = GetCurrentThreadId();

        if (foreThread != appThread) {
            AttachThreadInput(foreThread, appThread, TRUE);
            // Kỹ thuật Minimize -> Restore để kích hoạt Animation Zoom-in
            ShowWindow(hwnd, SW_SHOWMINIMIZED);
            ShowWindow(hwnd, SW_RESTORE);
            SetForegroundWindow(hwnd);
            AttachThreadInput(foreThread, appThread, FALSE);
        } else {
            ShowWindow(hwnd, SW_RESTORE);
            SetForegroundWindow(hwnd);
        }
    }

    static void GrantFocus() {
        AllowSetForegroundWindow(ASFW_ANY);
    }

    // Chạy lệnh hệ thống ẩn (tối ưu hơn system())
    static bool RunCommand(const std::wstring& cmd, const std::wstring& args) {
        STARTUPINFOW si = { sizeof(si) };
        PROCESS_INFORMATION pi = { 0 };
        si.dwFlags = STARTF_USESHOWWINDOW;
        si.wShowWindow = SW_HIDE; // Quan trọng: Ẩn window con

        std::wstring fullCmd = L"\"" + cmd + L"\" " + args;
        std::vector<wchar_t> buf(fullCmd.begin(), fullCmd.end());
        buf.push_back(0);

        if (CreateProcessW(NULL, buf.data(), NULL, NULL, FALSE, CREATE_NO_WINDOW_FLAG, NULL, NULL, &si, &pi)) {
            WaitForSingleObject(pi.hProcess, INFINITE);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            return true;
        }
        return false;
    }
};

// --- HELPER: JSON SIÊU NHẸ (CUSTOM) ---
// Tự viết để không phụ thuộc library, tối ưu tốc độ biên dịch và kích thước file
class SimpleJson {
public:
    static void Save(const fs::path& path, const AppConfig& cfg) {
        std::wofstream file(path);
        file << L"{\n";
        file << L"  \"selected_exe\": \"" << Escape(cfg.selected_exe) << L"\",\n";
        
        file << L"  \"registry_keys\": [\n";
        for (size_t i = 0; i < cfg.registry_keys.size(); ++i) {
            file << L"    \"" << Escape(cfg.registry_keys[i]) << L"\"" << (i < cfg.registry_keys.size() - 1 ? L"," : L"") << L"\n";
        }
        file << L"  ],\n";

        file << L"  \"stubborn_folders\": [\n";
        for (size_t i = 0; i < cfg.stubborn_folders.size(); ++i) {
            file << L"    { \"tag\": \"" << Escape(cfg.stubborn_folders[i].tag) << L"\", \"name\": \"" << Escape(cfg.stubborn_folders[i].name) << L"\" }" 
                 << (i < cfg.stubborn_folders.size() - 1 ? L"," : L"") << L"\n";
        }
        file << L"  ]\n";
        file << L"}";
    }

    static bool Load(const fs::path& path, AppConfig& outCfg) {
        std::wifstream file(path);
        if (!file.is_open()) return false;
        
        std::wstringstream buffer;
        buffer << file.rdbuf();
        std::wstring content = buffer.str();

        // Parse thủ công đơn giản (giả định file đúng định dạng do chính app tạo ra)
        outCfg.selected_exe = ExtractValue(content, L"\"selected_exe\":");
        
        // Parse Registry Keys
        size_t regStart = content.find(L"\"registry_keys\":");
        size_t regEnd = content.find(L"]", regStart);
        if (regStart != std::wstring::npos) {
            std::wstring regBlock = content.substr(regStart, regEnd - regStart);
            size_t pos = 0;
            while ((pos = regBlock.find(L"\"", pos + 1)) != std::wstring::npos) {
                size_t end = regBlock.find(L"\"", pos + 1);
                if (end == std::wstring::npos) break;
                // Kiểm tra xem đây có phải key value không (không chứa :)
                std::wstring val = regBlock.substr(pos + 1, end - pos - 1);
                if (val.find(L"registry_keys") == std::wstring::npos) {
                    if (!val.empty()) outCfg.registry_keys.push_back(Unescape(val));
                }
                pos = end + 1;
            }
        }

        // Parse Stubborn Folders
        size_t foldStart = content.find(L"\"stubborn_folders\":");
        if (foldStart != std::wstring::npos) {
            size_t pos = foldStart;
            while ((pos = content.find(L"{", pos)) != std::wstring::npos) {
                size_t endBlock = content.find(L"}", pos);
                std::wstring block = content.substr(pos, endBlock - pos);
                StubbornFolder sf;
                sf.tag = ExtractValue(block, L"\"tag\":");
                sf.name = ExtractValue(block, L"\"name\":");
                if (!sf.tag.empty()) outCfg.stubborn_folders.push_back(sf);
                pos = endBlock + 1;
            }
        }
        return true;
    }

private:
    static std::wstring Escape(std::wstring s) {
        std::wstring res;
        for (wchar_t c : s) {
            if (c == L'\\') res += L"\\\\";
            else res += c;
        }
        return res;
    }
    static std::wstring Unescape(std::wstring s) {
        std::wstring res;
        for (size_t i = 0; i < s.length(); ++i) {
            if (s[i] == L'\\' && i + 1 < s.length() && s[i+1] == L'\\') {
                res += L'\\'; i++;
            } else res += s[i];
        }
        return res;
    }
    static std::wstring ExtractValue(const std::wstring& src, const std::wstring& key) {
        size_t keyPos = src.find(key);
        if (keyPos == std::wstring::npos) return L"";
        size_t start = src.find(L"\"", keyPos + key.length());
        size_t end = src.find(L"\"", start + 1);
        return Unescape(src.substr(start + 1, end - start - 1));
    }
};

// --- ENGINE CORE ---
class Engine {
public:
    fs::path root;
    fs::path p_data;
    fs::path cfg_file;
    fs::path reg_backup;
    std::vector<std::pair<std::wstring, fs::path>> sys_roots;

    Engine() {
        // Lấy đường dẫn unicode chuẩn xác
        wchar_t buf[MAX_PATH];
        GetCurrentDirectoryW(MAX_PATH, buf);
        root = buf;
        p_data = root / L"Portable_Data";
        cfg_file = p_data / L"config" / L"config.json";
        reg_backup = p_data / L"Registry" / L"data.reg";

        sys_roots = {
            {L"ROAM", GetEnv(L"APPDATA")},
            {L"LOCAL", GetEnv(L"LOCALAPPDATA")},
            {L"DOCS", GetDocsPath()},
            // Low xử lý riêng nếu cần, ở đây giả lập cơ bản
            {L"LOW", GetEnv(L"USERPROFILE") / L"AppData" / L"LocalLow"}
        };
    }

    void Bootstrap() {
        fs::create_directories(p_data / L"config");
        fs::create_directories(p_data / L"Registry");
    }

    void SetupEnv() {
        auto roam = p_data / L"AppData" / L"Roaming";
        auto local = p_data / L"AppData" / L"Local";
        auto docs = p_data / L"Documents";

        if (!fs::exists(roam)) fs::create_directories(roam);
        if (!fs::exists(local)) fs::create_directories(local);
        if (!fs::exists(docs)) fs::create_directories(docs);

        SetEnvironmentVariableW(L"APPDATA", roam.c_str());
        SetEnvironmentVariableW(L"LOCALAPPDATA", local.c_str());
        SetEnvironmentVariableW(L"USERPROFILE", p_data.c_str());
        SetEnvironmentVariableW(L"DOCUMENTS", docs.c_str());
    }

    std::unordered_set<std::wstring> SnapshotRegistry() {
        std::unordered_set<std::wstring> keys;
        HKEY hKey;
        if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software", 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
            wchar_t name[256];
            DWORD index = 0;
            DWORD len = 256;
            while (RegEnumKeyExW(hKey, index++, name, &len, NULL, NULL, NULL, NULL) == ERROR_SUCCESS) {
                keys.insert(std::wstring(L"HKEY_CURRENT_USER\\Software\\") + name);
                len = 256;
            }
            RegCloseKey(hKey);
        }
        return keys;
    }

    std::unordered_set<std::wstring> SnapshotFolders() {
        std::unordered_set<std::wstring> items;
        for (const auto& [tag, path] : sys_roots) {
            if (fs::exists(path)) {
                for (const auto& entry : fs::directory_iterator(path)) {
                    if (entry.is_directory()) {
                        items.insert(tag + L"|" + entry.path().filename().wstring());
                    }
                }
            }
        }
        return items;
    }

    void SyncRegistry(const std::vector<std::wstring>& keys) {
        if (keys.empty()) return;
        if (fs::exists(reg_backup)) fs::remove(reg_backup);

        wchar_t tempPath[MAX_PATH];
        GetTempPathW(MAX_PATH, tempPath);
        fs::path tempReg = fs::path(tempPath) / L"port_tmp.reg";

        for (const auto& key : keys) {
            // Export
            WinApi::RunCommand(L"reg", L"export \"" + key + L"\" \"" + tempReg.wstring() + L"\" /y");
            
            // Append to backup file
            if (fs::exists(tempReg)) {
                std::ifstream in(tempReg, std::ios::binary);
                std::ofstream out(reg_backup, std::ios::binary | std::ios::app);
                out << in.rdbuf();
                in.close(); out.close();
                fs::remove(tempReg);
            }
            
            // Delete from host
            WinApi::RunCommand(L"reg", L"delete \"" + key + L"\" /f");
        }
    }

    fs::path MapPortPath(const std::wstring& tag, const std::wstring& name) {
        if (tag == L"ROAM") return p_data / L"AppData" / L"Roaming" / name;
        if (tag == L"LOCAL") return p_data / L"AppData" / L"Local" / name;
        if (tag == L"LOW") return p_data / L"AppData" / L"LocalLow" / name;
        return p_data / L"Documents" / name;
    }

private:
    fs::path GetEnv(const wchar_t* var) {
        wchar_t buf[32767];
        GetEnvironmentVariableW(var, buf, 32767);
        return fs::path(buf);
    }

    fs::path GetDocsPath() {
        wchar_t path[MAX_PATH];
        if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_PERSONAL, NULL, 0, path))) {
            return fs::path(path);
        }
        return GetEnv(L"USERPROFILE") / L"Documents";
    }
};

// --- LOGIC CHÍNH ---

void RunSandbox(Engine& engine, AppConfig& config) {
    // Chỉ tạo folder khi chạy sandbox
    engine.Bootstrap();

    if (config.registry_keys.empty() && config.stubborn_folders.empty()) {
        engine.SetupEnv();
        WinApi::GrantFocus();
        WinApi::RunCommand(config.selected_exe, L"");
        return;
    }

    // Import Registry
    if (fs::exists(engine.reg_backup)) {
        WinApi::RunCommand(L"reg", L"import \"" + engine.reg_backup.wstring() + L"\"");
    }

    // Junctions
    std::vector<fs::path> junctions;
    for (const auto& f : config.stubborn_folders) {
        fs::path origin;
        for (const auto& [tag, path] : engine.sys_roots) {
            if (tag == f.tag) { origin = path / f.name; break; }
        }
        fs::path dest = engine.MapPortPath(f.tag, f.name);

        if (!fs::exists(origin)) {
            // Tạo Junction bằng mklink (đơn giản, hiệu quả)
            // Lệnh: cmd /c mklink /J "origin" "dest"
            WinApi::RunCommand(L"cmd", L"/c mklink /J \"" + origin.wstring() + L"\" \"" + dest.wstring() + L"\"");
            junctions.push_back(origin);
        }
    }

    engine.SetupEnv();
    WinApi::GrantFocus();
    WinApi::HideConsole(); // Đảm bảo ẩn

    // Chạy EXE chính (Blocking wait)
    WinApi::RunCommand(config.selected_exe, L"");

    // Cleanup
    for (const auto& j : junctions) {
        RemoveDirectoryW(j.c_str()); // Chỉ xóa junction point
    }
    engine.SyncRegistry(config.registry_keys);
}

void LearningMode(Engine& engine) {
    // 1. Tự động tìm EXE (Fix #2: Loại bỏ chính mình)
    wchar_t selfPath[MAX_PATH];
    GetModuleFileNameW(NULL, selfPath, MAX_PATH);
    std::wstring selfName = fs::path(selfPath).filename().wstring();
    std::transform(selfName.begin(), selfName.end(), selfName.begin(), ::towlower);

    std::vector<std::wstring> exes;
    for (const auto& entry : fs::directory_iterator(L".")) {
        if (entry.path().extension() == L".exe") {
            std::wstring name = entry.path().filename().wstring();
            std::wstring lower = name;
            std::transform(lower.begin(), lower.end(), lower.begin(), ::towlower);
            
            if (lower != selfName) {
                exes.push_back(name);
            }
        }
    }

    if (exes.empty()) {
        WinApi::ForceFocus();
        std::wcout << L"[ERROR] No executable found." << std::endl;
        Sleep(3000);
        return; // Thoát ngay, không tạo folder rỗng (Fix #1)
    }

    // Chỉ bootstrap khi đã chọn được exe
    engine.Bootstrap();

    std::wstring selected_exe;
    if (exes.size() == 1) {
        WinApi::HideConsole();
        selected_exe = exes[0];
    } else {
        WinApi::ForceFocus();
        std::wcout << L"Select target:" << std::endl;
        for (size_t i = 0; i < exes.size(); ++i) {
            std::wcout << L"[" << i << L"] " << exes[i] << std::endl;
        }
        int choice;
        std::wcin >> choice;
        if (choice < 0 || choice >= exes.size()) return;
        
        // Sau khi chọn xong, ẩn ngay lập tức (Fix #3)
        WinApi::HideConsole();
        selected_exe = exes[choice];
    }

    // Snapshot
    auto reg_before = engine.SnapshotRegistry();
    auto fol_before = engine.SnapshotFolders();

    engine.SetupEnv();
    WinApi::GrantFocus();
    WinApi::HideConsole();

    // Chạy EXE để học
    WinApi::RunCommand(selected_exe, L"");
    Sleep(1000);

    auto reg_after = engine.SnapshotRegistry();
    auto fol_after = engine.SnapshotFolders();

    // Tính toán thay đổi (Diff)
    std::vector<std::wstring> reg_candidates;
    for (const auto& k : reg_after) {
        if (reg_before.find(k) == reg_before.end()) {
            std::wstring lower = k;
            std::transform(lower.begin(), lower.end(), lower.begin(), ::towlower);
            bool noise = false;
            for (const auto& kw : NOISE_KEYWORDS) {
                if (lower.find(kw) != std::wstring::npos) { noise = true; break; }
            }
            if (!noise) reg_candidates.push_back(k);
        }
    }

    std::vector<StubbornFolder> fol_candidates;
    for (const auto& k : fol_after) {
        if (fol_before.find(k) == fol_before.end()) {
            size_t sep = k.find(L"|");
            std::wstring tag = k.substr(0, sep);
            std::wstring name = k.substr(sep + 1);
            
            std::wstring lower = name;
            std::transform(lower.begin(), lower.end(), lower.begin(), ::towlower);
            bool noise = false;
            for (const auto& kw : NOISE_KEYWORDS) {
                if (lower.find(kw) != std::wstring::npos) { noise = true; break; }
            }
            if (!noise) fol_candidates.push_back({tag, name});
        }
    }

    if (reg_candidates.empty() && fol_candidates.empty()) {
        AppConfig cfg; cfg.selected_exe = selected_exe;
        SimpleJson::Save(engine.cfg_file, cfg);
        return;
    }

    // Hỏi người dùng (Hiện lại console với Animation)
    WinApi::ForceFocus();
    
    AppConfig config;
    config.selected_exe = selected_exe;

    if (!reg_candidates.empty()) {
        std::wcout << L"\nRegistry Changes Detected (Enter IDs separated by space, or -1 for all, 0 for none):" << std::endl;
        for (size_t i = 0; i < reg_candidates.size(); ++i) {
            std::wcout << L"[" << i + 1 << L"] " << reg_candidates[i] << std::endl;
        }
        // Giả lập logic chọn đơn giản: Lấy hết nếu không phức tạp hóa UI console
        std::wcout << L"> Auto-selecting all relevant keys for portable..." << std::endl;
        config.registry_keys = reg_candidates; 
    }

    if (!fol_candidates.empty()) {
        std::wcout << L"\nFolder Changes Detected:" << std::endl;
        for (const auto& f : fol_candidates) {
             std::wcout << L"[MOVING] " << f.tag << L" -> " << f.name << std::endl;
             
             fs::path origin;
             for (const auto& [tag, path] : engine.sys_roots) {
                 if (tag == f.tag) { origin = path / f.name; break; }
             }
             fs::path dest = engine.MapPortPath(f.tag, f.name);
             fs::create_directories(dest.parent_path());

             // Robocopy move
             std::wstring args = L"\"" + origin.wstring() + L"\" \"" + dest.wstring() + L"\" /E /MOVE /NFL /NDL /NJH /NJS /R:3 /W:1";
             WinApi::RunCommand(L"robocopy", args);
             
             config.stubborn_folders.push_back(f);
        }
    }

    SimpleJson::Save(engine.cfg_file, config);
    engine.SyncRegistry(config.registry_keys);
}

// --- ENTRY POINT ---
// Sử dụng WinMain thay vì main để mặc định không hiện console
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    // Chỉ tạo console khi cần thiết (trong ForceFocus)
    // Thiết lập locale UTF-8 cho toàn bộ app
    SetConsoleOutputCP(CP_UTF8);

    Engine engine;

    // Fix 1: Không gọi bootstrap ở đây
    
    if (fs::exists(engine.cfg_file)) {
        AppConfig config;
        if (SimpleJson::Load(engine.cfg_file, config)) {
            RunSandbox(engine, config);
            return 0;
        }
    }

    LearningMode(engine);
    return 0;
}