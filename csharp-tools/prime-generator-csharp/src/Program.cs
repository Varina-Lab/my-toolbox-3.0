using System;
using System.Collections;
using System.Collections.Generic;
using System.Text;
using System.Diagnostics;

public class PrimeGenerator
{
    public static void Main()
    {
        Console.Write("Nhap vao so N: ");
        if (int.TryParse(Console.ReadLine(), out int n))
        {
            // Bat dau do thoi gian
            Stopwatch sw = Stopwatch.StartNew();

            List<int> primes = GetPrimesUnder(n);

            sw.Stop();

            // In ket qua
            StringBuilder sb = new StringBuilder();
            foreach (int p in primes)
            {
                sb.Append(p).Append(" ");
            }
            
            Console.WriteLine("\nCac so nguyen to nho hon " + n + ":");
            Console.WriteLine(sb.ToString());
            
            Console.WriteLine("\n-------------------------------------------");
            Console.WriteLine("Thoi gian thuc thi: " + sw.Elapsed.TotalMilliseconds + " ms");
            Console.WriteLine("Tong cong co: " + primes.Count + " so nguyen to.");
        }
        else
        {
            Console.WriteLine("Du lieu nhap vao khong hop le.");
        }

        // Dung man hinh de xem ket qua
        Console.WriteLine("\nNhan phim bat ky de thoat...");
        Console.ReadKey();
    }

    public static List<int> GetPrimesUnder(int n)
    {
        if (n <= 2) return (n == 2) ? new List<int>() : new List<int>();
        if (n == 3) return new List<int> { 2 };

        // Toi uu: Chi xet cac so le
        int size = (n - 1) / 2;
        BitArray isPrime = new BitArray(size + 1, true);
        List<int> primes = new List<int>(n / 10); 
        primes.Add(2);

        int sqrtN = (int)Math.Sqrt(n);

        for (int i = 1; i <= size; i++)
        {
            if (isPrime[i])
            {
                int p = 2 * i + 1;
                if (p >= n) break;
                
                primes.Add(p);

                // Sang cac boi so cua p
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
