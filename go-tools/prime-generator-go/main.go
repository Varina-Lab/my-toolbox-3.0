package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"strconv"
	"time"
)

func main() {
	fmt.Print("Nhap n: ")
	var n int
	fmt.Scan(&n)

	start := time.Now()
	
	// Sử dụng BufWriter để tăng tốc in
	out := bufio.NewWriterSize(os.Stdout, 1024*1024)
	count := 0

	if n > 2 {
		out.WriteString("2 ")
		count = 1
		limit := (n - 1) / 2
		// Dùng []byte thay vì []bool để tiết kiệm và nhanh hơn trong Go
		isPrime := make([]byte, limit+1)
		for i := range isPrime {
			isPrime[i] = 1
		}

		sqrtN := int(math.Sqrt(float64(n)))
		for p := 3; p <= sqrtN; p += 2 {
			if isPrime[p/2] == 1 {
				for i := p * p; i < n; i += 2 * p {
					isPrime[i/2] = 0
				}
			}
		}

		// Buffer để convert số nhanh
		var b []byte
		for p := 1; p <= limit; p++ {
			if isPrime[p] == 1 {
				b = strconv.AppendInt(b[:0], int64(2*p+1), 10)
				b = append(b, ' ')
				out.Write(b)
				count++
			}
		}
	}
	out.Flush()

	duration := time.Since(start)
	fmt.Printf("\n\nSo luong: %d\n", count)
	fmt.Printf("Thoi gian: %.6fs\n", duration.Seconds())
	fmt.Println("Nhan Enter de thoat...")
	bufio.NewReader(os.Stdin).ReadBytes('\n')
	bufio.NewReader(os.Stdin).ReadBytes('\n')
}