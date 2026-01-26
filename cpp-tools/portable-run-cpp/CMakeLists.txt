cmake_minimum_required(VERSION 3.20)

project(ToolProject CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Static Runtime (Chạy độc lập không cần cài VC++ Redist)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")

# Tự động tìm thư viện json nếu dùng vcpkg, hoặc bạn tự trỏ đường dẫn
find_package(nlohmann_json CONFIG)

if(MSVC)
    add_compile_options(
        /O2 /Ob2 /Oi /Ot /GL /permissive- /utf-8
    )
    add_link_options(/LTCG)
endif()

add_executable(app_main src/main.cpp)

if(TARGET nlohmann_json::nlohmann_json)
    target_link_libraries(app_main PRIVATE nlohmann_json::nlohmann_json)
else()
    # Nếu không dùng vcpkg, hãy đảm bảo folder chứa json.hpp nằm ở đây
    target_include_directories(app_main PRIVATE ${CMAKE_SOURCE_DIR}/src/include)
endif()