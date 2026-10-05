# Ελέγχει τα υπάρχοντα εξώφυλλα (τίτλος/τόμος) και σβήνει όσα δεν ταιριάζουν, ώστε να ξαναψαχτούν
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'sources-gr.ps1')
$books = (Get-Content -Raw -Encoding UTF8 "$root\data\books.json" | ConvertFrom-Json) | ForEach-Object { $_ }
$map = Get-Content -Raw -Encoding UTF8 "$root\data\covers.json" | ConvertFrom-Json
foreach ($b in $books) {
  $m = $map.($b.id); if (-not $m) { continue }
  $t = ($b.title -replace '\s*[\(\[].*?[\)\]]', '' -replace '[«»"“”]', '').Trim()
  $why = if (-not (Title-Ok $t $m.matched)) { 'τίτλος' } elseif (-not (Volume-Ok $b $m.matched)) { 'τόμος' }
  if ($why) {
    Write-Output "$($b.id) ($why) [$($b.title) τόμ. $($b.volume)] <- $($m.matched)"
    $f = Join-Path $root "covers\$($b.id).jpg"
    if (Test-Path $f) { [IO.File]::Delete($f) }
    $map.PSObject.Properties.Remove($b.id)
  }
}
[IO.File]::WriteAllText("$root\data\covers.json", ($map | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding $false))
