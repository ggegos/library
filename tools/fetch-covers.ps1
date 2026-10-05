# Αναζητά εξώφυλλα σε Open Library και Google Books και τα αποθηκεύει στο covers/<id>.jpg.
# Βιβλία που έχουν ήδη αρχείο στο covers/ παραλείπονται (έτσι οι χειροκίνητες αντικαταστάσεις διατηρούνται).
param([string]$root = (Split-Path $PSScriptRoot -Parent), [switch]$force)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Web
$books = (Get-Content -Raw -Encoding UTF8 "$root\data\books.json" | ConvertFrom-Json) | ForEach-Object { $_ }
$mapFile = "$root\data\covers.json"
$map = @{}
if (Test-Path $mapFile) { (Get-Content -Raw -Encoding UTF8 $mapFile | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $map[$_.Name] = $_.Value } }
. (Join-Path $PSScriptRoot "sources-gr.ps1")
function Enc($s) { [Web.HttpUtility]::UrlEncode($s) }
function Get-Json($url) {
  # Αποκωδικοποίηση ως UTF-8 (το PS 5.1 αλλιώς χαλάει τα ελληνικά) και επανάληψη σε 429
  for ($i = 0; $i -lt 3; $i++) {
    try {
      $r = Invoke-WebRequest -Uri $url -TimeoutSec 30 -UseBasicParsing
      $bytes = $r.RawContentStream.ToArray()
      return [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
    } catch {
      $code = $_.Exception.Response.StatusCode.value__
      if ($code -eq 429 -or $code -ge 500) { Start-Sleep -Seconds (($i + 1) * 4); continue }
      throw
    }
  }
  throw "Αποτυχία μετά από επαναλήψεις: $url"
}
function Save-Map {
  $json = $map | ConvertTo-Json -Depth 3
  [IO.File]::WriteAllText($mapFile, $json, (New-Object Text.UTF8Encoding $false))
}
function CleanTitle($t) { ($t -replace '\s*[\(\[].*?[\)\]]', '' -replace '[«»"“”]', '').Trim() }
function FirstAuthor($a) { (($a -split '[;,&]')[0] -replace '\(.*?\)', '').Trim() }

function Try-OpenLibrary($title, $author) {
  $q = "https://openlibrary.org/search.json?limit=10&fields=key,title,cover_i&title=$(Enc $title)"
  if ($author) { $q += "&author=$(Enc $author)" }
  $r = Get-Json $q
  $d = $r.docs | Where-Object { $_.cover_i -and (Title-Ok $title $_.title) } | Select-Object -First 1
  if ($d) { return @{ url = "https://covers.openlibrary.org/b/id/$($d.cover_i)-L.jpg?default=false"; source = "openlibrary:$($d.key)"; matched = $d.title } }
}
$script:googleDown = $false
function Try-Google($title, $author) {
  if ($script:googleDown) { return }
  $q = "intitle:$title"
  if ($author) { $q += " inauthor:$author" }
  try { $r = Get-Json "https://www.googleapis.com/books/v1/volumes?maxResults=5&q=$(Enc $q)" }
  catch { if ($_.Exception.Message -like "*επαναλήψεις*") { $script:googleDown = $true; Write-Warning "Google Books: όριο αιτημάτων, συνέχεια μόνο με Open Library" }; throw }
  $v = $r.items | Where-Object { $_.volumeInfo.imageLinks.thumbnail } | Select-Object -First 1
  if ($v) {
    $u = $v.volumeInfo.imageLinks.thumbnail -replace '^http:', 'https:' -replace '&edge=curl', ''
    return @{ url = $u; source = "google:$($v.id)"; matched = $v.volumeInfo.title }
  }
}

$found = 0; $missing = @()
foreach ($b in $books) {
  $file = "$root\covers\$($b.id).jpg"
  if ((Test-Path $file) -and -not $force) { continue }
  if ($b.title -like 'Μη αναγνώσιμ*') { $missing += $b.id; Write-Output "--   $($b.id)  (μη αναγνώσιμος τίτλος)"; continue }
  $author = FirstAuthor $b.author; $script:curVolume = $b.volume
  if ($author -match '^(Μη αναγνωσμένος|Συλλογικό έργο|Άγνωστος)') { $author = '' }
  # Παραλλαγές τίτλου: ολόκληρος (με το «—» ως κενό) και, αν υπάρχει, μόνο το πρώτο μέρος
  $full = CleanTitle $b.title
  $variants = @(($full -replace '\s*[—–:]\s*', ' ').Trim())
  $first = ($full -split '\s*[—–:]\s*')[0].Trim()
  if ($first -ne $variants[0] -and $first.Length -ge 4 -and $author -and $b.language -notlike 'Ελληνικά*') { $variants += $first }
  $hit = $null
  foreach ($title in $variants) {
  $order = if ($b.language -like 'Ελληνικά*') { 'Try-Biblionet', 'Try-Ianos', 'Try-Google', 'Try-OpenLibrary' } else { 'Try-OpenLibrary', 'Try-Google', 'Try-Ianos', 'Try-Biblionet' }
  foreach ($fn in $order) {
    try { $hit = & $fn $title $author } catch { Write-Warning "$($b.id) $fn : $($_.Exception.Message)" }
    if ($hit -and -not $author -and (Norm-Text $title) -ne (Norm-Text (($hit.matched -split ' / ')[0]))) { Write-Output "     $($b.id) απορρίφθηκε (χωρίς συγγραφέα, όχι ακριβής τίτλος): $($hit.matched)"; $hit = $null }
    if ($hit -and -not (Title-Ok $title $hit.matched)) { Write-Output "     $($b.id) απορρίφθηκε (άλλος τίτλος): $($hit.matched)"; $hit = $null }
    if ($hit -and -not (Volume-Ok $b $hit.matched)) { Write-Output "     $($b.id) απορρίφθηκε (άλλος τόμος): $($hit.matched)"; $hit = $null }
    if ($hit) {
      try {
        try { Invoke-WebRequest -Uri $hit.url -OutFile $file -TimeoutSec 30 -UseBasicParsing }
        catch { if ($hit.fallback) { Invoke-WebRequest -Uri $hit.fallback -OutFile $file -TimeoutSec 30 -UseBasicParsing } else { throw } }
        if ((Get-Item $file).Length -lt 2000) { Remove-Item $file; $hit = $null } else { break }
      } catch { if (Test-Path $file) { Remove-Item $file }; $hit = $null }
    }
    Start-Sleep -Milliseconds 1200
  }
  if ($hit) { break }
  }
  if ($hit) {
    $map[$b.id] = [ordered]@{ source = $hit.source; matched = $hit.matched }
    Save-Map; $found++; Write-Output "OK   $($b.id)  $($b.title)  ->  $($hit.matched) [$($hit.source)]"
  } else { $missing += $b.id; Write-Output "--   $($b.id)  $($b.title)" }
}
$json = $map | ConvertTo-Json -Depth 3
[IO.File]::WriteAllText($mapFile, $json, (New-Object Text.UTF8Encoding $false))
Write-Output "Βρέθηκαν: $found, χωρίς εξώφυλλο: $($missing.Count)"
