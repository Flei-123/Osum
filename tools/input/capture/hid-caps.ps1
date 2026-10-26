$src = @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class HidDump {
  [StructLayout(LayoutKind.Sequential)] public struct SPID { public int cbSize; public Guid g; public int flags; public IntPtr r; }
  [StructLayout(LayoutKind.Sequential)] public struct ATTR { public int Size; public ushort Vid; public ushort Pid; public ushort Ver; }
  [StructLayout(LayoutKind.Sequential)] public struct CAPS {
    public ushort Usage, UsagePage, InRep, OutRep, FeatRep;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst=17)] public ushort[] Res;
    public ushort NLink, NInBtn, NInVal, NInIdx, NOutBtn, NOutVal, NOutIdx, NFeatBtn, NFeatVal, NFeatIdx;
  }
  [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
  [DllImport("hid.dll")] static extern bool HidD_GetAttributes(SafeFileHandle h, ref ATTR a);
  [DllImport("hid.dll")] static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr p);
  [DllImport("hid.dll")] static extern bool HidD_FreePreparsedData(IntPtr p);
  [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr p, ref CAPS c);
  [DllImport("hid.dll")] static extern int HidP_GetValueCaps(int t, IntPtr caps, ref ushort len, IntPtr p);
  [DllImport("hid.dll")] static extern int HidP_GetButtonCaps(int t, IntPtr caps, ref ushort len, IntPtr p);
  [DllImport("hid.dll", CharSet=CharSet.Unicode)] static extern bool HidD_GetProductString(SafeFileHandle h, StringBuilder s, int len);
  [DllImport("setupapi.dll", SetLastError=true)] static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr h, int f);
  [DllImport("setupapi.dll", SetLastError=true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g, int i, ref SPID data);
  [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref SPID data, IntPtr detail, int size, out int req, IntPtr dd);
  [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern SafeFileHandle CreateFile(string n, uint acc, uint share, IntPtr sa, uint disp, uint flags, IntPtr t);

  static void DumpCaps(StringBuilder o, string kind, int type, IntPtr pp, int n, bool val) {
    if (n == 0) return;
    ushort len = (ushort)n;
    IntPtr buf = Marshal.AllocHGlobal(72 * n);
    int st = val ? HidP_GetValueCaps(type, buf, ref len, pp) : HidP_GetButtonCaps(type, buf, ref len, pp);
    if (st == 0x110000) {
      for (int i = 0; i < len; i++) {
        IntPtr q = buf + 72 * i;
        int up = (ushort)Marshal.ReadInt16(q, 0);
        int rid = Marshal.ReadByte(q, 2);
        int link = (ushort)Marshal.ReadInt16(q, 6);
        int isr = Marshal.ReadByte(q, 12);
        int u1 = (ushort)Marshal.ReadInt16(q, 56);
        int u2 = isr != 0 ? (ushort)Marshal.ReadInt16(q, 58) : u1;
        string line = "  " + kind + (val ? " VAL" : " BTN") + " rid=" + rid + " page=0x" + up.ToString("x") + " usage=0x" + u1.ToString("x") + (u2 != u1 ? "..0x" + u2.ToString("x") : "") + " link=" + link;
        if (val) {
          line += " bits=" + (ushort)Marshal.ReadInt16(q, 18) + " count=" + (ushort)Marshal.ReadInt16(q, 20) +
            " lmin=" + Marshal.ReadInt32(q, 40) + " lmax=" + Marshal.ReadInt32(q, 44) + " pmin=" + Marshal.ReadInt32(q, 48) + " pmax=" + Marshal.ReadInt32(q, 52) +
            " unitexp=" + Marshal.ReadInt32(q, 32) + " unit=" + Marshal.ReadInt32(q, 36);
        }
        o.AppendLine(line);
      }
    } else o.AppendLine("  " + kind + " caps status=0x" + st.ToString("x"));
    Marshal.FreeHGlobal(buf);
  }

  public static string Run() {
    var o = new StringBuilder();
    Guid g; HidD_GetHidGuid(out g);
    IntPtr set = SetupDiGetClassDevs(ref g, IntPtr.Zero, IntPtr.Zero, 0x12);
    for (int idx = 0; ; idx++) {
      var d = new SPID(); d.cbSize = Marshal.SizeOf(typeof(SPID));
      if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref g, idx, ref d)) break;
      int req; SetupDiGetDeviceInterfaceDetail(set, ref d, IntPtr.Zero, 0, out req, IntPtr.Zero);
      IntPtr det = Marshal.AllocHGlobal(req);
      Marshal.WriteInt32(det, IntPtr.Size == 8 ? 8 : 6);
      string path = null;
      if (SetupDiGetDeviceInterfaceDetail(set, ref d, det, req, out req, IntPtr.Zero)) path = Marshal.PtrToStringUni(det + 4);
      Marshal.FreeHGlobal(det);
      if (path == null) continue;
      var h = CreateFile(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
      if (h.IsInvalid) continue;
      var a = new ATTR(); a.Size = Marshal.SizeOf(typeof(ATTR));
      HidD_GetAttributes(h, ref a);
      var ps = new StringBuilder(256); HidD_GetProductString(h, ps, 512);
      IntPtr pp;
      if (!HidD_GetPreparsedData(h, out pp)) continue;
      var c = new CAPS(); c.Res = new ushort[17];
      HidP_GetCaps(pp, ref c);
      o.AppendLine("DEVICE vid=" + a.Vid.ToString("x4") + " pid=" + a.Pid.ToString("x4") + " product=" + ps.ToString());
      o.AppendLine("  toplevel page=0x" + c.UsagePage.ToString("x") + " usage=0x" + c.Usage.ToString("x") + " inlen=" + c.InRep + " outlen=" + c.OutRep + " featlen=" + c.FeatRep +
        " nlink=" + c.NLink + " inbtn=" + c.NInBtn + " inval=" + c.NInVal + " featbtn=" + c.NFeatBtn + " featval=" + c.NFeatVal);
      DumpCaps(o, "IN", 0, pp, c.NInBtn, false);
      DumpCaps(o, "IN", 0, pp, c.NInVal, true);
      DumpCaps(o, "OUT", 1, pp, c.NOutBtn, false);
      DumpCaps(o, "OUT", 1, pp, c.NOutVal, true);
      DumpCaps(o, "FEAT", 2, pp, c.NFeatBtn, false);
      DumpCaps(o, "FEAT", 2, pp, c.NFeatVal, true);
      HidD_FreePreparsedData(pp);
      h.Close();
    }
    SetupDiDestroyDeviceInfoList(set);
    return o.ToString();
  }
}
"@
Add-Type -TypeDefinition $src -Language CSharp
$out = [HidDump]::Run()
$target = Join-Path $env:TEMP 'hid-caps.txt'
[IO.File]::WriteAllText($target, $out, (New-Object Text.UTF8Encoding($false)))
"wrote $target ($($out.Length) chars)"
