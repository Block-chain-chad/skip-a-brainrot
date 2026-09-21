# burst-capture.ps1 -- PrintWindow the Studio window every -IntervalMs for -Seconds, cropped.
#   -OutDir <dir>   frames land as <OutDir>\f_<index>_<ms-since-start>.png
#   -Seconds N      how long to keep capturing
#   -IntervalMs N   spacing between frames (a PrintWindow of a 1920x1000 client costs ~60-120 ms)
#   -Left/-Top/-Width/-Height   crop rect in Studio-window CLIENT pixels (default: whole client)
# Works while Studio sits behind other windows (PrintWindow + PW_RENDERFULLCONTENT); only a
# MINIMISED window fails. Never activates or moves the window.
param(
  [Parameter(Mandatory=$true)][string]$OutDir,
  [double]$Seconds = 6,
  [int]$IntervalMs = 150,
  [int]$Left = -1, [int]$Top = -1, [int]$Width = -1, [int]$Height = -1,
  [string]$Format = "png"
)
Add-Type @"
using System; using System.Runtime.InteropServices;
public class SCB {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[void][SCB]::SetProcessDPIAware()
Add-Type -AssemblyName System.Drawing
$studio = Get-Process -Name RobloxStudioBeta -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $studio) { Write-Output "NO STUDIO WINDOW"; exit 4 }
$h = $studio.MainWindowHandle
$rc = New-Object SCB+RECT
[void][SCB]::GetClientRect($h, [ref]$rc)
$cw = $rc.R - $rc.L; $ch = $rc.B - $rc.T
if ($Left -lt 0) { $Left = 0 }; if ($Top -lt 0) { $Top = 0 }
if ($Width -le 0) { $Width = $cw - $Left }; if ($Height -le 0) { $Height = $ch - $Top }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$i = 0
$full = New-Object System.Drawing.Bitmap($cw, $ch)
$fg = [System.Drawing.Graphics]::FromImage($full)
$src = New-Object System.Drawing.Rectangle($Left, $Top, $Width, $Height)
$dst = New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
  $t = $sw.ElapsedMilliseconds
  $hdc = $fg.GetHdc()
  [void][SCB]::PrintWindow($h, $hdc, 2)
  $fg.ReleaseHdc($hdc)
  $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.DrawImage($full, $dst, $src, [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose()
  if ($Format -eq "jpg") {
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
    $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]93)
    $bmp.Save((Join-Path $OutDir ("f_{0:d4}_{1:d5}.jpg" -f $i, $t)), $codec, $ep)
  } else {
    $bmp.Save((Join-Path $OutDir ("f_{0:d4}_{1:d5}.png" -f $i, $t)), [System.Drawing.Imaging.ImageFormat]::Png)
  }
  $bmp.Dispose()
  $i++
  $rest = $IntervalMs - ($sw.ElapsedMilliseconds - $t)
  if ($rest -gt 0) { Start-Sleep -Milliseconds $rest }
}
$fg.Dispose(); $full.Dispose()
Write-Output ("captured {0} frames over {1:n1}s into {2} (client {3}x{4}, crop {5},{6} {7}x{8})" -f $i, $sw.Elapsed.TotalSeconds, $OutDir, $cw, $ch, $Left, $Top, $Width, $Height)
