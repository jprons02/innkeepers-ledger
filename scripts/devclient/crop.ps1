# Dev harness (#139): crops each tour screenshot to the frame it shows, from crops.txt
# (source|destination|x|y|w|h|screenW|screenH, written by read.lua). A box of 0 width
# keeps the whole screenshot. Windows PowerShell 5.1 (System.Drawing).
param([Parameter(Mandatory = $true)][string]$List)
Add-Type -AssemblyName System.Drawing
foreach ($line in Get-Content -LiteralPath $List) {
  if (-not $line) { continue }
  $f = $line.Split('|')
  $img = [System.Drawing.Image]::FromFile($f[0])
  try {
    $x = [int]$f[2]; $y = [int]$f[3]; $w = [int]$f[4]; $h = [int]$f[5]
    $sw = [double]$f[6]; $sh = [double]$f[7]
    if ($w -le 0 -or $h -le 0 -or $sw -le 0 -or $sh -le 0) {
      $x = 0; $y = 0; $w = $img.Width; $h = $img.Height
    } else {
      # The screenshot may be rendered at another size than the physical screen.
      $kx = $img.Width / $sw; $ky = $img.Height / $sh
      $x = [int]($x * $kx); $y = [int]($y * $ky); $w = [int]($w * $kx); $h = [int]($h * $ky)
      $x = [Math]::Max(0, [Math]::Min($x, $img.Width - 1))
      $y = [Math]::Max(0, [Math]::Min($y, $img.Height - 1))
      $w = [Math]::Min($w, $img.Width - $x); $h = [Math]::Min($h, $img.Height - $y)
    }
    if ($w -lt 1 -or $h -lt 1) {
      Write-Output ("skipped (empty box) -> {0}" -f $f[1])
      continue
    }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, $w, $h),
      (New-Object System.Drawing.Rectangle $x, $y, $w, $h), [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $bmp.Save($f[1], [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output ("cropped {0}x{1} -> {2}" -f $w, $h, $f[1])
  } finally {
    $img.Dispose()
  }
}
