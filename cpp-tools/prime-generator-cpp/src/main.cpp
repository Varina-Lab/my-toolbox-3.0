#include <iostream>
#include <vector>
#include <cmath>
#include <chrono>
#include <charconv> // Yêu cầu C++17
#include <cstdio>   // Để dùng fwrite và stdout

using namespace std;

// Buffer 1MB để tối ưu I/O
const size_t BUF_SIZE = 1024 * 1024;
char out_buf[BUF_SIZE];
size_t buf_pos = 0;

// Hàm đẩy dữ liệu từ buffer ra màn hình
inline void flush_out() {
    if (buf_pos > 0) {
        std::fwrite(out_buf, 1, buf_pos, stdout);
        buf_pos = 0;
    }
}

// Hàm convert số thành text cực nhanh không dùng printf/cout
inline void write_int(int n) {
    if (buf_pos + 15 > BUF_SIZE) flush_out(); // Dự phòng 15 ký tự cho số nguyên lớn
    auto [ptr, ec] = std::to_chars(out_buf + buf_pos, out_buf + BUF_SIZE, n);
    if (ec == std::errc()) {
        buf_pos = ptr - out_buf;
        out_buf[buf_pos++] = ' ';
    }
}

int main() {
    int n;
    // Dùng printf/scanf để tránh overhead của iostream trong MSVC
    std::printf("Nhap n: ");
    if (std::scanf("%d", &n) != 1) return 0;

    auto start = chrono::high_resolution_clock::now();

    int count = 0;
    if (n > 2) {
        write_int(2);
        count = 1;
        
        // Sàng số lẻ (Odd-only Sieve)
        int limit_idx = (n - 1) / 2;
        // vector<uint8_t> nhanh hơn vector<bool> vì truy cập byte trực tiếp
        vector<uint8_t> is_prime(limit_idx + 1, 1);
        int sqrt_n = static_cast<int>(sqrt(n));

        for (int p = 3; p <= sqrt_n; p += 2) {
            if (is_prime[p >> 1]) {
                // Bước nhảy 2*p để bỏ qua các số chẵn
                for (int i = p * p; i < n; i += (p << 1))
                    is_prime[i >> 1] = 0;
            }
        }

        for (int i = 1; i <= limit_idx; ++i) {
            if (is_prime[i]) {
                int val = (i << 1) + 1;
                if (val < n) {
                    write_int(val);
                    count++;
                }
            }
        }
        flush_out(); // Đẩy nốt buffer còn lại
    } else if (n == 2) {
        // Không có số nguyên tố nào nhỏ hơn 2
    }

    auto end = chrono::high_resolution_clock::now();
    chrono::duration<double> diff = end - start;

    std::printf("\n\n--------------------------------");
    std::printf("\nSo luong: %d", count);
    std::printf("\nThoi gian: %.6f giay", diff.count());
    std::printf("\n--------------------------------");
    
    std::printf("\nNhan Enter de thoat...");
    std::fflush(stdout);
    // Xử lý dừng màn hình trên Windows
    int c;
    while ((c = getchar()) != '\n' && c != EOF); 
    getchar(); 
    
    return 0;
}