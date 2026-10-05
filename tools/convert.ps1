# Μετατρέπει το JSON που εξήχθη από το xlsx σε data/books.json
param([string]$in, [string]$out)
$b = (Get-Content -Raw -Encoding UTF8 $in | ConvertFrom-Json) | ForEach-Object { $_ } | Where-Object { $_.'Κωδικός' -and $_.'Τίτλος' }
function S($v) { if ($null -eq $v) { return '' } ; return ([string]$v).Trim() }
$res = foreach ($x in $b) {
  $series = S $x.'Σειρά / συλλογή'
  if ($series -eq 'Δεν έχει καταγραφεί') { $series = '' }
  [ordered]@{
    id        = S $x.'Κωδικός'
    title     = S $x.'Τίτλος'
    author    = S $x.'Συγγραφέας'
    coauthors = S $x.'Συνδημιουργοί'
    series    = $series
    subseries = S $x.'Υποσειρά'
    volume    = S $x.'Τόμος / μέρος'
    language  = S $x.'Γλώσσα'
    category  = S $x.'Κατηγορία'
    publisher = S $x.'Εκδότης'
    identification = S $x.'Αναγνώριση τίτλου'
    photos    = @((S $x.'Φωτογραφία') -split '\s*/\s*' | Where-Object { $_ })
    notes     = S $x.'Παρατηρήσεις'
  }
}
$json = $res | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText($out, $json, (New-Object Text.UTF8Encoding $false))
"wrote $($res.Count) books"
