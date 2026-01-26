cmake_minimum_required(VERSION 3.20)

# Tên dự án (Mặc định lấy tên folder nếu muốn, hoặc đặt cố định)
project(ToolProject CXX)

# --- CẤU HÌNH QUAN TRỌNG: C++ Chuẩn Mới Nhất ---
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- CẤU HÌNH QUAN TRỌNG: Static Linking (Chạy không cần cài VC++ Redist) ---
# Thay vì chỉnh /MT thủ công bằng cờ, CMake bản mới hỗ trợ dòng này:
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")

# --- CẤU HÌNH TỐI ƯU HÓA (Max Performance) ---
if(MSVC)
    add_compile_options(
        /O2     # Tối ưu hóa tốc độ cao nhất
        /Ob2    # Inline function aggressively
        /Oi     # Sử dụng intrinsic functions
        /Ot     # Ưu tiên code nhanh hơn là code nhỏ
        /GL     # Whole Program Optimization (cần đi kèm /LTCG ở linker)
        /permissive- # Tuân thủ chuẩn C++ nghiêm ngặt
    )
    add_link_options(
        /LTCG   # Link Time Code Generation (Tương tự LTO của Rust)
    )
endif()

# Định nghĩa file exe đầu ra
add_executable(app_main src/main.cpp)
