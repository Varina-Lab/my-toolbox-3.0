import time
import sys

def sieve_of_eratosthenes(n):
    """
    Sử dụng thuật toán Sàng Eratosthenes tối ưu hóa bộ nhớ
    Trả về danh sách các số nguyên tố nhỏ hơn n
    """
    if n <= 2:
        return []
    
    # Khởi tạo mảng đánh dấu bằng bytearray để tiết kiệm bộ nhớ (True = 1)
    # Chỉ xét các số lẻ để giảm một nửa dung lượng bộ nhớ và số vòng lặp
    sieve_size = n // 2
    primes_mask = bytearray([1]) * sieve_size
    primes_mask[0] = 0 # Số 1 không phải số nguyên tố
    
    # Chỉ lặp đến căn bậc hai của n
    for i in range(1, int(n**0.5) // 2 + 1):
        if primes_mask[i]:
            # Đánh dấu các bội số của số nguyên tố hiện tại là False
            # Bắt đầu từ bình phương của số đó
            start = 2 * i * (i + 1)
            step = 2 * i + 1
            primes_mask[start:sieve_size:step] = bytearray((sieve_size - start - 1) // step + 1)
            
    # Chuyển đổi mask thành danh sách số thực tế
    primes = [2] + [2 * i + 1 for i in range(1, sieve_size) if primes_mask[i]]
    return primes

def main():
    try:
        num_str = input("Nhập vào một số nguyên dương: ")
        limit = int(num_str)
        
        print(f"Đang tính toán các số nguyên tố nhỏ hơn {limit}...")
        
        # Bắt đầu đo thời gian
        start_time = time.perf_counter()
        
        result = sieve_of_eratosthenes(limit)
        
        # Kết thúc đo thời gian
        end_time = time.perf_counter()
        execution_time = end_time - start_time
        
        # In kết quả (giới hạn in nếu danh sách quá dài để tránh treo terminal)
        if limit <= 1000:
            print(f"Các số nguyên tố: {result}")
        else:
            print(f"Tìm thấy {len(result)} số nguyên tố.")
            print(f"5 số đầu tiên: {result[:5]}")
            print(f"5 số cuối cùng: {result[-5:]}")
            
        print(f"\nThời gian thực thi: {execution_time:.6f} giây")
        
    except ValueError:
        print("Vui lòng nhập một số nguyên hợp lệ.")
    
    # Dừng màn hình
    print("\n" + "="*30)
    input("Nhấn Enter để thoát chương trình...")

if __name__ == "__main__":
    main()
