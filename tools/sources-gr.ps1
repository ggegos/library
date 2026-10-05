# Ελληνικές πηγές εξωφύλλων (ianos.gr, biblionet.gr) με έλεγχο ταύτισης τίτλου/συγγραφέα
Add-Type -AssemblyName System.Web
function Norm-Text($s) {
  $s = [Web.HttpUtility]::HtmlDecode([string]$s).Normalize([Text.NormalizationForm]::FormD)
  $s = -join ($s.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
  $s = $s.ToUpperInvariant() -replace 'Σ', 'Σ' -replace '[^\p{L}\p{N} ]', ' ' -replace '\s+', ' '
  $s.Trim()
}
# Φωνητικός «σκελετός» ονόματος σε λατινικά σύμφωνα, για σύγκριση π.χ. Neville ↔ ΝΕΒΙΛ, Brown ↔ ΜΠΡΑΟΥΝ
function Skeleton($s) {
  $s = (Norm-Text $s)
  $gr = [ordered]@{ 'ΜΠ'='B'; 'ΝΤ'='D'; 'ΓΚ'='G'; 'ΓΓ'='G'; 'ΤΣ'='TS'; 'ΤΖ'='TZ'; 'ΟΥ'='U'; 'Α'='A'; 'Β'='V'; 'Γ'='G'; 'Δ'='D'; 'Ε'='E'; 'Ζ'='Z'; 'Η'='I'; 'Θ'='T'; 'Ι'='I'; 'Κ'='K'; 'Λ'='L'; 'Μ'='M'; 'Ν'='N'; 'Ξ'='KS'; 'Ο'='O'; 'Π'='P'; 'Ρ'='R'; 'Σ'='S'; 'Τ'='T'; 'Υ'='I'; 'Φ'='F'; 'Χ'='K'; 'Ψ'='PS'; 'Ω'='O' }
  foreach ($k in $gr.Keys) { $s = $s.Replace($k, $gr[$k]) }
  $s = $s -replace 'Ø', 'O' -replace 'PH', 'F' -replace 'TH', 'T' -replace 'CH', 'K' -replace 'SH', 'S' -replace 'C', 'K' -replace 'Q', 'K' -replace 'W', 'U' -replace 'X', 'KS' -replace 'J', 'TZ' -replace 'Y', 'I'
  $s = $s -replace '(.)\1+', '$1'
  ($s -replace '[AEIOU ]', '')
}
function Similar([string]$a, [string]$b) {
  if (-not $a -or -not $b) { return 0 }
  $prev = 0..$b.Length
  for ($i = 1; $i -le $a.Length; $i++) {
    $cur = @($i) + (1..$b.Length | ForEach-Object { 0 })
    for ($j = 1; $j -le $b.Length; $j++) {
      $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
      $cur[$j] = [math]::Min([math]::Min($prev[$j] + 1, $cur[$j - 1] + 1), $prev[$j - 1] + $cost)
    }
    $prev = $cur
  }
  1 - $prev[$b.Length] / [math]::Max($a.Length, $b.Length)
}
function Author-Match($ours, $theirs) {
  # Ταιριάζει αν κάποια λέξη του δικού μας ονόματος (≥3 γράμματα) μοιάζει με κάποια λέξη του δικού τους
  foreach ($w in (Norm-Text $ours).Split(' ')) { if ($w.Length -lt 3) { continue }
    $sw = Skeleton $w
    foreach ($t in (Norm-Text $theirs).Split(' ')) { if ($t.Length -lt 3) { continue }
      if ((Norm-Text $w) -eq $t) { return $true }
      if ($sw.Length -ge 2 -and (Similar $sw (Skeleton $t)) -ge 0.75) { return $true } } }
  $false
}
function Try-Ianos($title, $author) {
  $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/128 Safari/537.36'
  $url = 'https://www.ianos.gr/catalogsearch/result/?q=' + [uri]::EscapeDataString($title)
  $r = Invoke-WebRequest -Uri $url -UserAgent $ua -TimeoutSec 40 -UseBasicParsing
  $html = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
  $nt = Norm-Text $title
  $surname = if ($author) { (Norm-Text $author).Split(' ') | Sort-Object Length -Descending | Select-Object -First 1 } else { '' }
  $best = $null; $bestScore = 0
  $blocks = $html -split 'class="product-item-info"' | Select-Object -Skip 1
  foreach ($blk in $blocks) {
    $m = [regex]::Match($blk, 'class="product-image-photo"\s+src="([^"]+)"[\s\S]*?alt="([^"]*)"')
    if (-not $m.Success) { continue }
    $img = $m.Groups[1].Value; $pt = Norm-Text $m.Groups[2].Value
    $w = [regex]::Match($blk, 'data-gtm-brand="([^"]*)"').Groups[1].Value
    $score = 0
    if ($pt -eq $nt) { $score = 3 } elseif ($pt.StartsWith($nt + ' ') -or $nt.StartsWith($pt + ' ')) { $score = 2 } elseif ($pt.Contains($nt) -and $nt.Length -ge 8) { $score = 1 }
    if ($score -eq 0) { continue }
    $nw = Norm-Text $w
    # Συγγραφέας: τα ξένα ονόματα στο ianos είναι μεταγραμμένα, οπότε μετράει ως μπόνους, όχι ως προϋπόθεση
    if ($author) { if (Author-Match $author $w) { $score += 2 } else { continue } }
    if ($script:curVolume -match '^\d+$' -and $pt -match "\b$($script:curVolume)\b") { $score += 1 }
    if ($score -gt $bestScore) { $bestScore = $score; $best = @{ url = ($img -replace '/cache/[0-9a-f]+/', '/'); fallback = $img; source = 'ianos:' + ($blk | Select-String -Pattern 'href="(https://www\.ianos\.gr/[^"]+)"').Matches[0].Groups[1].Value; matched = "$([Web.HttpUtility]::HtmlDecode($m.Groups[2].Value)) / $w" } }
  }
  # Χωρίς ταύτιση συγγραφέα δεχόμαστε μόνο ακριβή τίτλο
  if ($best -and ($bestScore -ge 3)) { return $best }
}

# Biblionet (επίσημη βάση ελληνικών βιβλίων): συγγραφείς σε ελληνική γραφή, άρα πολύ αξιόπιστη ταύτιση
function Try-Biblionet($title, $author) {
  $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/128 Safari/537.36'
  $url = 'https://www.biblionet.gr/' + [uri]::EscapeDataString('συνθετη-αναζητηση') + '?q=' + [uri]::EscapeDataString($title)
  $r = Invoke-WebRequest -Uri $url -UserAgent $ua -TimeoutSec 60 -UseBasicParsing
  $html = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
  $nt = Norm-Text $title
  $best = $null; $bestScore = 0
  foreach ($blk in ($html -split 'class="image_cover_a' | Select-Object -Skip 1)) {
    $img = [regex]::Match($blk, 'sb_img"\s+src="([^"]+)"').Groups[1].Value
    if (-not $img -or $img -match 'no_?image|default') { continue }
    $t = [regex]::Match($blk, 'class="book-title text-color-hover-secondary">([^<]+)<').Groups[1].Value
    $w = [regex]::Match($blk, '</h3>\s*<a role="link" aria-label="([^"]+)"').Groups[1].Value
    $href = [regex]::Match($blk, 'href="([^"]+)"').Groups[1].Value
    $pt = Norm-Text $t
    $score = 0
    if ($pt -eq $nt) { $score = 3 } elseif ($pt.StartsWith($nt + ' ') -or $nt.StartsWith($pt + ' ')) { $score = 2 }
    if ($score -eq 0) { continue }
    if ($author) { if (Author-Match $author $w) { $score += 2 } else { continue } }
    if ($script:curVolume -match '^\d+$' -and $pt -match "\b$($script:curVolume)\b") { $score += 1 }
    if ($score -gt $bestScore) { $bestScore = $score; $best = @{ url = "https://www.biblionet.gr$img"; source = "biblionet:$href"; matched = "$t / $w" } }
  }
  if ($best -and ($bestScore -ge 3)) { return $best }
}

# Σε σειρές με ίδιο τίτλο ανά τόμο: αν το αποτέλεσμα έχει αριθμό που δεν υπάρχει στον δικό μας τίτλο,
# πρέπει να είναι ο δικός μας τόμος (αλλιώς, π.χ. τόμος «Μη αναγνώσιμος», απορρίπτεται)
function Volume-Ok($b, $matched) {
  $mt = ($matched -split ' / ')[0] -replace '[\(\[].*?[\)\]]', ''
  $extra = [regex]::Matches($mt, '\d+') | ForEach-Object { $_.Value } | Where-Object { $b.title -notmatch "\b$_\b" }
  if (-not $extra) { return $true }
  return ($b.volume -match '^\d+$') -and (@($extra) -contains $b.volume)
}
# Ο τίτλος του αποτελέσματος πρέπει να αρχίζει με τον δικό μας ή το αντίστροφο (π.χ. υπότιτλοι)
function Title-Ok($title, $matched) {
  $a = Norm-Text (($title -split " / ")[0]); $m = Norm-Text ((($matched -split ' / ')[0]) -replace '[\(\[].*?[\)\]]', '')
  $a -and $m -and (($m -eq $a) -or $m.StartsWith("$a ") -or $a.StartsWith("$m "))
}

