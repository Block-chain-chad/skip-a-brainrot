# cursor-pos.ps1 -- print the OS cursor position and the Studio window's client origin.
# Used to locate the game viewport inside the Studio window: move the in-game mouse to
# viewport (0,0) with the MCP input tool, then read where the OS cursor landed.
Add-Type @"
using System; using System.Runtime.InteropServices;
public class CP {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[void][CP]::SetProcessDPIAware()
$p = New-Object CP+POINT
[void][CP]::GetCursorPos([ref]$p)
$studio = Get-Process -Name RobloxStudioBeta -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$o = New-Object CP+POINT; $o.X = 0; $o.Y = 0
if ($studio) { [void][CP]::ClientToScreen($studio.MainWindowHandle, [ref]$o) }
Write-Output ("cursor={0},{1} studioClientOrigin={2},{3} viewportOffsetInClient={4},{5}" -f $p.X, $p.Y, $o.X, $o.Y, ($p.X - $o.X), ($p.Y - $o.Y))
