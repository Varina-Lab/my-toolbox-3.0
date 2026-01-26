import sys
import time

def main() -> None:
    print("Hello! This is a High-Performance Python Tool.")
    print("Compiled to Native Machine Code via Nuitka.")
    
    # Thử nghiệm một vòng lặp tính toán để thấy hiệu năng
    start_time = time.time()
    
    res = 0
    for i in range(1_000_000):
        res += i
        
    end_time = time.time()
    
    print(f"Calculation Result: {res}")
    print(f"Execution Time: {(end_time - start_time) * 1000:.2f} ms")

if __name__ == "__main__":
    main()
