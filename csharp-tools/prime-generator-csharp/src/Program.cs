using System;
using System.Collections;
using System.Collections.Generic;
using System.Text;

public class PrimeGenerator
{
    public static void Main()
    {
        Console.Write("Nhập số N: ");
        if (int.TryParse(Console.ReadLine(), out int n) && n > 2)
        {
            var primes = GetPrimesUnder(n);
            
            // Sử dụng StringBuilder để tối ưu việc in dữ liệu lớn ra Console
            StringBuilder sb = new StringBuilder();
            foreach (int p in primes)
            {
                sb.Append(p).Append(" ");
            }
            Console.WriteLine(sb.ToString());
        }
        else
        {
            Console.WriteLine("Vui lòng nhập số nguyên lớn hơn 2.");
        }
    }

    /// <summary>
    /// Tìm tất cả các số nguyên tố nhỏ hơn n bằng thuật toán Sàng Eratosthenes tối ưu.
    /// </summary>
    public static List<int> GetPrimesUnder(int n)
    {
        if (n <= 2) return new List<int>();

        // BitArray giúp tiết kiệm bộ nhớ (1 bit/phần tử thay vì 1-4 bytes)
        // Chỉ lưu trữ các số lẻ để giảm một nửa dung lượng bộ nhớ
        int size = (n - 1) / 2;
        BitArray isPrime = new BitArray(size + 1, true);
        List<int> primes = new List<int>(n / 10) { 2 }; // Khởi tạo với số 2

        int sqrtN = (int)Math.Sqrt(n);

        for (int i = 1; i <= size; i++)
        {
            if (isPrime[i])
            {
                int p = 2 * i + 1;
                primes.Add(p);

                // Loại bỏ các bội số của p, bắt đầu từ p*p để tránh trùng lặp
                if (p <= sqrtN)
                {
                    for (int j = 2 * i * (i + 1); j <= size; j += p)
                    {
                        isPrime[j] = false;
                    }
                }
            }
        }

        return primes;
    }
}
