package main

import (
	"fmt"
	"os"
	"time"
)

func main() {
	// Tối ưu hóa: Go Routine mặc định đã xử lý concurrency rất tốt.
	// Đây là chương trình mẫu.
	fmt.Println("Hello! This is a High-Performance Go Tool.")
	fmt.Println("Running as a static binary.")

	start := time.Now()

	// Ví dụ logic xử lý
	doWork()

	elapsed := time.Since(start)
	fmt.Printf("Execution time: %s\n", elapsed)

	// Giữ màn hình console (nếu cần)
	// fmt.Println("Press Enter to exit...")
	// fmt.Scanln()
}

func doWork() {
	// Giả lập công việc
	_ = os.Getpid()
}
