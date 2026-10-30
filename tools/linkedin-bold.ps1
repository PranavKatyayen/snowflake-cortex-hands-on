# LinkedIn has no formatting, so **bold** is turned into Unicode bold letters that survive copy-paste.
#   .\tools\linkedin-bold.ps1 -Markdown drafts\series-launch\linkedin.md
# Writes linkedin-ready.txt next to the input and copies it to the clipboard.
param([Parameter(Mandatory = $true)][string]$Markdown)

function ConvertTo-Bold([string]$s) {
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if     ($c -ge 65 -and $c -le 90)  { [void]$sb.Append([char]::ConvertFromUtf32(0x1D5D4 + $c - 65)) }
        elseif ($c -ge 97 -and $c -le 122) { [void]$sb.Append([char]::ConvertFromUtf32(0x1D5EE + $c - 97)) }
        elseif ($c -ge 48 -and $c -le 57)  { [void]$sb.Append([char]::ConvertFromUtf32(0x1D7EC + $c - 48)) }
        else                               { [void]$sb.Append($ch) }
    }
    $sb.ToString()
}

$mdPath  = (Resolve-Path $Markdown).Path
$text    = [IO.File]::ReadAllText($mdPath, [Text.Encoding]::UTF8)
$out     = [regex]::Replace($text, '\*\*(.+?)\*\*', { param($m) ConvertTo-Bold $m.Groups[1].Value })
$outPath = Join-Path (Split-Path -Parent $mdPath) 'linkedin-ready.txt'
[IO.File]::WriteAllText($outPath, $out, (New-Object Text.UTF8Encoding $false))
Set-Clipboard -Value $out
Write-Host "Wrote $outPath and copied it to the clipboard ($($out.Length) chars)"
