import time
import sys

def sieve_optimized(n):
    """Sàng Eratosthenes tối ưu: chỉ sàng số lẻ, dùng bytearray"""
    if n < 2: return []
    if n == 2: return [2]
    
    # Chỉ quản lý các số lẻ: 3, 5, 7... (n-1 nếu n chẵn)
    size = (n - 1) // 2
    sieve = bytearray([1]) * (size + 1)
    
    for i in range(1, int(n**0.5) // 2 + 1):
        if sieve[i]:
            # Chỉ số k tương ứng với số 2i + 1
            # Bắt đầu đánh dấu từ (2i+1)^2
            start = 2 * i * (i + 1)
            step = 2 * i + 1
            sieve[start::step] = bytearray((size - start) // step + 1)
            
    return [2] + [2 * i + 1 for i in range(1, size + 1) if sieve[i]]

def main():
    try:
        limit = int(input("Nhập giới hạn n: "))
        
        print(f"--- Đang tính toán số nguyên tố < {limit} ---")
        start_time = time.perf_counter()
        
        primes = sieve_optimized(limit)
        
        end_time = time.perf_counter()
        duration = end_time - start_time
        
        # Chiến lược in tối ưu
        count = len(primes)
        if count > 100000:
            print(f"CẢNH BÁO: Tìm thấy {count} số. Việc in trực tiếp sẽ làm chậm máy.")
            confirm = input("Bạn có thực sự muốn in tất cả không? (y/n): ")
            if confirm.lower() != 'y':
                print(f"5 số đầu: {primes[:5]} ... 5 số cuối: {primes[-5:]}")
            else:
                # In tối ưu bằng cách join chuỗi để giảm số lần gọi hệ thống
                print(", ".join(map(str, primes)))
        else:
            print(", ".join(map(str, primes)))

        print(f"\n{'='*40}")
        print(f"Tổng cộng: {count} số nguyên tố.")
        print(f"Thời gian tính toán: {duration:.6f} giây")
        
    except ValueError:
        print("Lỗi: Vui lòng nhập một số nguyên.")
    except MemoryError:
        print("Lỗi: Số quá lớn vượt quá bộ nhớ RAM cho phép.")
    
    input("\nNhấn Enter để kết thúc...")

if __name__ == "__main__":
    main()
