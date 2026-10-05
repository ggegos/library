# Η Βιβλιοθήκη μου

Στατικό site παρουσίασης της προσωπικής βιβλιοθήκης, με εξώφυλλα, αναζήτηση και φίλτρα.
Δεν χρειάζεται build· αρκεί οποιοσδήποτε στατικός server (π.χ. GitHub Pages).

## Δομή

| Αρχείο / φάκελος | Περιεχόμενο |
|---|---|
| `index.html`, `assets/` | Το site |
| `data/books.json` | Ο κατάλογος (παράγεται από το xlsx) |
| `data/covers.json` | Από πού βρέθηκε κάθε εξώφυλλο, για έλεγχο |
| `covers/<κωδικός>.jpg` | Εξώφυλλα (π.χ. `covers/B012.jpg`) |
| `photos/<IMG_xxxx>.jpg` | Προαιρετικά: φωτογραφίες ραφιών, εμφανίζονται στις λεπτομέρειες |
| `tools/` | Scripts ενημέρωσης και τοπικής προεπισκόπησης |

## Ενημέρωση καταλόγου από νέο xlsx

1. Αποσυμπίεσε το xlsx και εξήγαγε JSON (βλ. `tools/convert.ps1`), ή ζήτα από τον Claude να το κάνει.
2. Τρέξε `powershell -ExecutionPolicy Bypass -File tools/fetch-covers.ps1` για να βρεθούν εξώφυλλα για τα νέα βιβλία.

## Εξώφυλλα

- Βρίσκονται αυτόματα από Open Library / Google Books με βάση τίτλο και συγγραφέα, οπότε κάποια μπορεί να είναι άλλης έκδοσης ή λάθος.
- **Αντικατάσταση:** βάλε τη δική σου εικόνα ως `covers/B012.jpg`. Το script δεν πειράζει υπάρχοντα αρχεία.
- **Αφαίρεση λάθος εξωφύλλου:** σβήσε το αρχείο· θα εμφανίζεται το τυπογραφικό εξώφυλλο.
- Βιβλία χωρίς εξώφυλλο εμφανίζονται με τυπογραφικό εξώφυλλο στο χρώμα της κατηγορίας.

## Τοπική προεπισκόπηση

```
powershell -ExecutionPolicy Bypass -File tools/serve.ps1
```
και άνοιξε http://localhost:8080

## Δημοσίευση σε GitHub Pages

1. Φτιάξε repository στο GitHub (π.χ. `library`), δημόσιο.
2. Από τον φάκελο αυτό:
   ```
   git remote add origin https://github.com/<user>/library.git
   git push -u origin main
   ```
3. Στο GitHub: **Settings → Pages → Source: Deploy from a branch → main / (root)** → Save.
4. Σε 1–2 λεπτά το site είναι στο `https://<user>.github.io/library/`.
