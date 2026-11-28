param([int]$VmPid = 7224, [double]$Sec = 3)
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Thr {
  [DllImport("kernel32.dll")] public static extern IntPtr OpenThread(uint a, bool i, uint id);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll")] public static extern int GetThreadDescription(IntPtr h, out IntPtr d);
  [DllImport("kernel32.dll")] public static extern bool GetThreadTimes(IntPtr h, out long c, out long e, out long k, out long u);
  [DllImport("kernel32.dll")] public static extern IntPtr LocalFree(IntPtr p);
  public static string Desc(uint id) {
    IntPtr h = OpenThread(0x0840, false, id); if (h == IntPtr.Zero) return "?";
    IntPtr d; string s = "?";
    if (GetThreadDescription(h, out d) == 0) { s = Marshal.PtrToStringUni(d); LocalFree(d); }
    CloseHandle(h); return s;
  }
  public static long[] Times(uint id) {
    IntPtr h = OpenThread(0x0840, false, id); if (h == IntPtr.Zero) return new long[] { -1, -1 };
    long c, e, k, u; GetThreadTimes(h, out c, out e, out k, out u); CloseHandle(h);
    return new long[] { k, u };
  }
}
"@
$p = Get-Process -Id $VmPid
$a = @{}
foreach ($t in $p.Threads) { $a[$t.Id] = [Thr]::Times([uint32]$t.Id) }
$t0 = Get-Date
Start-Sleep -Milliseconds ([int]($Sec * 1000))
$dt = ((Get-Date) - $t0).TotalSeconds
$rows = @()
foreach ($t in (Get-Process -Id $VmPid).Threads) {
  $x = [Thr]::Times([uint32]$t.Id); $b = $a[$t.Id]
  if ($b -and $x[0] -ge 0 -and $b[0] -ge 0) {
    $k = 100 * (($x[0] - $b[0]) / 1e7) / $dt; $u = 100 * (($x[1] - $b[1]) / 1e7) / $dt
    $rows += [pscustomobject]@{ Id = $t.Id; Name = [Thr]::Desc([uint32]$t.Id); KernelPct = [math]::Round($k, 1); UserPct = [math]::Round($u, 1); State = $t.ThreadState; Wait = $t.WaitReason }
  }
}
$rows | Where-Object { ($_.KernelPct + $_.UserPct) -gt 0.4 } | Sort-Object { -($_.KernelPct + $_.UserPct) } | Format-Table -AutoSize | Out-String -Width 200
"threads total: " + $rows.Count + "  window=" + [math]::Round($dt, 2) + "s"
