use std::io::{self, Write, BufWriter};
use std::time::Instant;

/// Hàm chuyển số nguyên thành byte không dùng định dạng (tối ưu nhất)
fn fast_itoa(mut n: usize, buf: &mut [u8]) -> usize {
    if n == 0 {
        buf[0] = b'0';
        return 1;
    }
    let mut i = 20;
    while n > 0 {
        i -= 1;
        buf[i] = (n % 10) as u8 + b'0';
        n /= 10;
    }
    20 - i
}

fn main() -> io::Result<()> {
    print!("Nhap n: ");
    io::stdout().flush()?;
    let mut input_str = String::new();
    io::stdin().read_line(&mut input_str)?;
    let n: usize = input_str.trim().parse().unwrap_or(0);

    let start = Instant::now();
    let mut count = 0;

    if n > 2 {
        // Lock stdout để tránh overhead
        let stdout = io::stdout();
        let mut handle = BufWriter::with_capacity(128 * 1024, stdout.lock());
        
        handle.write_all(b"2 ")?;
        count = 1;

        let limit = (n - 1) / 2;
        // Sử dụng Box thay vì Vec để tránh một số overhead kiểm tra của Vec
        let mut is_prime = vec![true; limit + 1].into_boxed_slice();
        let sqrt_n = (n as f64).sqrt() as usize;

        for p in (3..=sqrt_n).step_by(2) {
            if is_prime[p / 2] {
                let mut i = p * p;
                while i < n {
                    is_prime[i / 2] = false;
                    i += 2 * p;
                }
            }
        }

        let mut num_buf = [0u8; 21]; // Buffer tạm cho từng số
        for p in 1..=limit {
            if is_prime[p] {
                let val = 2 * p + 1;
                let len = fast_itoa(val, &mut num_buf);
                // Ghi trực tiếp mảng byte vào buffer
                handle.write_all(&num_buf[20-len..20])?;
                handle.write_all(b" ")?;
                count += 1;
            }
        }
        handle.flush()?;
    }

    let duration = start.elapsed();
    println!("\n\nSo luong: {}", count);
    println!("Thoi gian: {:.6}s", duration.as_secs_f64());
    println!("Nhan Enter de thoat...");
    io::stdin().read_line(&mut String::new())?;
    Ok(())
}