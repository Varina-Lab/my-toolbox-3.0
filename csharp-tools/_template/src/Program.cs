using System.Runtime.InteropServices;

namespace TemplateTool;

class Program
{
    // Cấu hình để code chạy tối ưu trên Windows
    [DllImport("kernel32.dll")]
    static extern IntPtr GetConsoleWindow();

    static void Main(string[] args)
    {
        Console.WriteLine("Hello! This is a C# Native AOT Tool.");
        Console.WriteLine("Running standalone without .NET Runtime.");
        Console.WriteLine($"OS Version: {Environment.OSVersion}");

        // Ví dụ logic tính toán
        var data = Enumerable.Range(1, 10).Select(x => x * x).ToArray();
        Console.WriteLine($"Calculation check: {string.Join(", ", data)}");

        // Giữ màn hình (nếu cần)
        // Console.WriteLine("Press any key to exit...");
        // Console.ReadKey();
    }
}
