# capture-studio.ps1 -- save the Roblox Studio window (or a sub-rect of it) to a PNG.
#   -Out <path>            PNG to write (required)
#   -Left/-Top/-Width/-Height   optional crop rect in Studio-window CLIENT pixels
#   -Mode screen|print     screen = copy the pixels from the screen (window must be visible and in
#                          front); print = PrintWindow(PW_RENDERFULLCONTENT), which can grab a
#                          window that is behind other windows (GPU views may come out black).
param(
  [Parameter(Mandatory=$true)][string]$Out,
  [int]$Left = -1, [int]$Top = -1, [int]$Width = -1, [int]$Height = -1,
  [string]$Mode = "screen"
)
Add-Type @"
using System; using System.Runtime.InteropServices;
public class SC {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[void][SC]::SetProcessDPIAware()
Add-Type -AssemblyName System.Drawing
$studio = Get-Process -Name RobloxStudioBeta -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $studio) { Write-Output "NO STUDIO WINDOW"; exit 4 }
$h = $studio.MainWindowHandle
$rc = New-Object SC+RECT
[void][SC]::GetClientRect($h, [ref]$rc)
$pt = New-Object SC+POINT; $pt.X = 0; $pt.Y = 0
[void][SC]::ClientToScreen($h, [ref]$pt)
$cw = $rc.R - $rc.L; $ch = $rc.B - $rc.T
if ($Left -lt 0) { $Left = 0 }; if ($Top -lt 0) { $Top = 0 }
if ($Width -le 0) { $Width = $cw - $Left }; if ($Height -le 0) { $Height = $ch - $Top }
$bmp = New-Object System.Drawing.Bitmap($Width, $Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
if ($Mode -eq "print") {
  $full = New-Object System.Drawing.Bitmap($cw, $ch)
  $fg = [System.Drawing.Graphics]::FromImage($full)
  $hdc = $fg.GetHdc()
  [void][SC]::PrintWindow($h, $hdc, 2)
  $fg.ReleaseHdc($hdc); $fg.Dispose()
  $g.DrawImage($full, (New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)), (New-Object System.Drawing.Rectangle($Left, $Top, $Width, $Height)), [System.Drawing.GraphicsUnit]::Pixel)
  $full.Dispose()
} else {
  $g.CopyFromScreen(($pt.X + $Left), ($pt.Y + $Top), 0, 0, (New-Object System.Drawing.Size($Width, $Height)))
}
$g.Dispose()
$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$fgh = [SC]::GetForegroundWindow()
Write-Output ("saved {0} ({1}x{2}) client={3}x{4} at screen {5},{6} studioForeground={7}" -f $Out, $Width, $Height, $cw, $ch, $pt.X, $pt.Y, ($fgh -eq $h))
