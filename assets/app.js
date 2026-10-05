(() => {
  'use strict';

  const $ = (s) => document.querySelector(s);
  const els = {
    q: $('#q'), categories: $('#categories'), language: $('#language'), series: $('#series'),
    author: $('#author'), group: $('#group'), sort: $('#sort'), reset: $('#reset'),
    results: $('#results'), count: $('#count'), subtitle: $('#subtitle'),
    dialog: $('#detail'), detailBody: $('#detail-body'),
  };

  // Χρώματα «υφάσματος» για τα τυπογραφικά εξώφυλλα, ανά κατηγορία
  const CLOTH = ['#6b2a26', '#2f4a3a', '#25395a', '#7a5a22', '#4d2f4f', '#3d4a52', '#5c3a1e', '#1f4f4f', '#6a3b52', '#44502a'];
  const collator = new Intl.Collator('el', { sensitivity: 'base', numeric: true });

  // Αναζήτηση χωρίς τόνους/πεζά-κεφαλαία
  const norm = (s) => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/ς/g, 'σ');
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  let books = [];
  let categoryColor = {};
  const state = { q: '', cat: '', lang: '', series: '', author: '', group: '', sort: 'title' };

  const NO = {
    category: 'Χωρίς κατηγορία', series: 'Εκτός σειράς', author: 'Άγνωστος συγγραφέας', language: 'Άγνωστη γλώσσα',
  };

  async function init() {
    try {
      const res = await fetch('data/books.json', { cache: 'no-cache' });
      books = await res.json();
    } catch (e) {
      els.results.innerHTML = '<p class="empty">Δεν ήταν δυνατή η φόρτωση του καταλόγου.</p>';
      return;
    }
    for (const b of books) {
      b._search = norm([b.title, b.author, b.coauthors, b.series, b.subseries, b.publisher, b.category, b.notes, b.id].join(' | '));
      b._lang = (b.language || '').replace(/\s*\[\?\]$/, '');
    }
    const cats = countBy(books, (b) => b.category || NO.category);
    Object.keys(cats).sort(collator.compare).forEach((c, i) => { categoryColor[c] = CLOTH[i % CLOTH.length]; });

    els.subtitle.textContent = `${books.length} βιβλία · ${Object.keys(countBy(books, (b) => b.author)).length} συγγραφείς · ${Object.keys(cats).length} κατηγορίες`;
    buildChips(cats);
    fillSelect(els.language, countBy(books, (b) => b._lang || NO.language));
    fillSelect(els.series, countBy(books.filter((b) => b.series), (b) => b.series));
    fillSelect(els.author, countBy(books.filter((b) => b.author), (b) => b.author));

    readHash();
    bind();
    render();
    // Άνοιγμα βιβλίου από το URL (#book=B012)
    const open = new URLSearchParams(location.hash.slice(1)).get('book');
    if (open) openBook(open);
  }

  function countBy(list, fn) {
    const m = {};
    for (const x of list) { const k = fn(x); if (k) m[k] = (m[k] || 0) + 1; }
    return m;
  }

  function buildChips(cats) {
    const all = [['', 'Όλα', books.length], ...Object.entries(cats).sort((a, b) => b[1] - a[1] || collator.compare(a[0], b[0])).map(([k, n]) => [k, k, n])];
    els.categories.innerHTML = all.map(([v, label, n]) =>
      `<button type="button" class="chip" data-cat="${esc(v)}" aria-pressed="false">${esc(label)}<span class="n">${n}</span></button>`).join('');
  }

  function fillSelect(sel, counts) {
    const opts = Object.entries(counts).sort((a, b) => collator.compare(a[0], b[0]))
      .map(([k, n]) => `<option value="${esc(k)}">${esc(k)} (${n})</option>`).join('');
    sel.insertAdjacentHTML('beforeend', opts);
  }

  function bind() {
    let t;
    els.q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => { state.q = els.q.value; update(); }, 120); });
    els.categories.addEventListener('click', (e) => {
      const btn = e.target.closest('.chip'); if (!btn) return;
      state.cat = btn.dataset.cat; update();
    });
    for (const [key, el] of [['lang', els.language], ['series', els.series], ['author', els.author], ['group', els.group], ['sort', els.sort]]) {
      el.addEventListener('change', () => { state[key] = el.value; update(); });
    }
    els.reset.addEventListener('click', () => {
      Object.assign(state, { q: '', cat: '', lang: '', series: '', author: '', group: '', sort: 'title' });
      syncControls(); update();
    });
    els.results.addEventListener('click', (e) => {
      const b = e.target.closest('.book'); if (b) openBook(b.dataset.id);
    });
    els.dialog.addEventListener('click', (e) => {
      if (e.target === els.dialog || e.target.closest('[data-close]')) els.dialog.close();
      const f = e.target.closest('[data-filter]');
      if (f) { e.preventDefault(); const [k, v] = f.dataset.filter.split(':'); resetFilters(); state[k] = decodeURIComponent(v); syncControls(); els.dialog.close(); update(); }
    });
    els.dialog.addEventListener('close', () => writeHash());
    // Το replaceState δεν προκαλεί hashchange, άρα εδώ φτάνουν μόνο εξωτερικές αλλαγές (επικόλληση link, back)
    window.addEventListener('hashchange', () => {
      resetFilters(); Object.assign(state, { group: '', sort: 'title' });
      readHash(); render();
      const id = new URLSearchParams(location.hash.slice(1)).get('book');
      if (id) openBook(id); else if (els.dialog.open) els.dialog.close();
    });
  }

  function resetFilters() { Object.assign(state, { q: '', cat: '', lang: '', series: '', author: '' }); }

  function syncControls() {
    els.q.value = state.q; els.language.value = state.lang; els.series.value = state.series;
    els.author.value = state.author; els.group.value = state.group; els.sort.value = state.sort;
  }

  function update() { writeHash(); render(); }

  const HASH_KEYS = ['q', 'cat', 'lang', 'series', 'author', 'group', 'sort'];
  function writeHash(bookId) {
    const p = new URLSearchParams();
    for (const k of HASH_KEYS) if (state[k] && !(k === 'sort' && state[k] === 'title')) p.set(k, state[k]);
    if (bookId) p.set('book', bookId);
    const h = p.toString();
    history.replaceState(null, '', h ? '#' + h : location.pathname + location.search);
  }
  function readHash() {
    const p = new URLSearchParams(location.hash.slice(1));
    for (const k of HASH_KEYS) if (p.has(k)) state[k] = p.get(k);
    syncControls();
  }

  function filtered() {
    const terms = norm(state.q).split(/\s+/).filter(Boolean);
    return books.filter((b) =>
      (!state.cat || (b.category || NO.category) === state.cat) &&
      (!state.lang || (b._lang || NO.language) === state.lang) &&
      (!state.series || b.series === state.series) &&
      (!state.author || b.author === state.author) &&
      terms.every((t) => b._search.includes(t)));
  }

  const vol = (b) => parseFloat(b.volume) || 0;
  const SORTS = {
    title: (a, b) => collator.compare(a.title, b.title),
    author: (a, b) => collator.compare(a.author || '￿', b.author || '￿') || SORTS.series(a, b),
    series: (a, b) => collator.compare(a.series || '￿', b.series || '￿') || vol(a) - vol(b) || collator.compare(a.title, b.title),
    id: (a, b) => collator.compare(a.id, b.id),
  };

  function render() {
    els.categories.querySelectorAll('.chip').forEach((c) => c.setAttribute('aria-pressed', String(c.dataset.cat === state.cat)));
    const list = filtered().sort(SORTS[state.sort] || SORTS.title);
    els.count.textContent = list.length === books.length ? `Όλα τα ${books.length} βιβλία` : `${list.length} από ${books.length} βιβλία`;
    if (!list.length) { els.results.innerHTML = '<p class="empty">Κανένα βιβλίο δεν ταιριάζει με την αναζήτηση.</p>'; return; }

    if (!state.group) { els.results.innerHTML = `<div class="grid">${list.map(card).join('')}</div>`; }
    else {
      const key = { category: (b) => b.category || NO.category, series: (b) => b.series || NO.series, author: (b) => b.author || NO.author, language: (b) => b._lang || NO.language }[state.group];
      const groups = new Map();
      for (const b of list) { const k = key(b); if (!groups.has(k)) groups.set(k, []); groups.get(k).push(b); }
      const fallback = NO[state.group];
      const names = [...groups.keys()].sort((a, b) => (a === fallback) - (b === fallback) || collator.compare(a, b));
      els.results.innerHTML = names.map((n) => `<section class="group"><h2>${esc(n)} <span class="n">${groups.get(n).length}</span></h2><div class="grid">${groups.get(n).map(card).join('')}</div></section>`).join('');
    }
    hookImages(els.results);
  }

  function genCover(b) {
    return `<div class="gen" style="--c:${categoryColor[b.category || NO.category] || CLOTH[0]}" aria-hidden="true">
      <span class="go">❦</span><span class="gt">${esc(b.title)}</span><span class="ga">${esc(b.author)}</span></div>`;
  }
  function coverHtml(b, eager) {
    return `<div class="cover">${genCover(b)}<img data-src="covers/${esc(b.id)}.jpg" alt="Εξώφυλλο: ${esc(b.title)}" ${eager ? '' : 'loading="lazy"'} decoding="async"></div>`;
  }
  function seriesLine(b) {
    if (!b.series) return '';
    if (!b.volume) return esc(b.series);
    return esc(b.series) + ' · ' + (/^(\d+([.,]\d+)?|[IVXLC]+)$/.test(b.volume) ? `#${esc(b.volume)}` : /^Μη αναγνώσιμ/.test(b.volume) ? 'τόμος ;' : esc(b.volume));
  }
  function card(b) {
    return `<button type="button" class="book" data-id="${esc(b.id)}">
      ${coverHtml(b)}
      <span class="t">${esc(b.title)}</span>
      ${b.author ? `<span class="a">${esc(b.author)}</span>` : ''}
      ${b.series ? `<span class="s">${seriesLine(b)}</span>` : ''}
    </button>`;
  }

  // Οι εικόνες εμφανίζονται μόνο αν υπάρχουν· αλλιώς μένει το τυπογραφικό εξώφυλλο
  function hookImages(root) {
    root.querySelectorAll('img[data-src]').forEach((img) => {
      img.addEventListener('load', () => img.classList.add('loaded'), { once: true });
      img.addEventListener('error', () => img.remove(), { once: true });
      img.src = img.dataset.src; img.removeAttribute('data-src');
    });
  }

  function openBook(id) {
    const b = books.find((x) => x.id === id); if (!b) return;
    const link = (k, v, text) => `<a href="#" data-filter="${k}:${encodeURIComponent(v)}">${esc(text ?? v)}</a>`;
    const rows = [
      ['Συγγραφέας', b.author && link('author', b.author)],
      ['Συνδημιουργοί', esc(b.coauthors)],
      ['Σειρά', b.series && link('series', b.series)],
      ['Υποσειρά', esc(b.subseries)],
      ['Τόμος', esc(b.volume)],
      ['Κατηγορία', b.category && link('cat', b.category)],
      ['Γλώσσα', b._lang && link('lang', b._lang, b.language)],
      ['Εκδότης', esc(b.publisher)],
      ['Κωδικός', `<span class="tag">${esc(b.id)}</span>`],
      ['Αναγνώριση', esc(b.identification)],
      ['Ράφι', b.photos?.length ? `<div class="photos">${b.photos.map((p) =>
        `<a href="photos/${esc(p)}.jpg" target="_blank" rel="noopener"><img data-src="photos/${esc(p)}.jpg" alt="Φωτογραφία ${esc(p)}"><span>${esc(p)}</span></a>`).join('')}</div>` : ''],
    ].filter(([, v]) => v);
    els.detailBody.innerHTML = `
      <div class="large">${coverHtml(b, true)}</div>
      <div>
        <h2 id="d-title">${esc(b.title)}</h2>
        ${b.author ? `<p class="by">${esc(b.author)}</p>` : ''}
        <dl class="meta">${rows.map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join('')}</dl>
        ${b.notes ? `<p class="notes">${esc(b.notes)}</p>` : ''}
      </div>`;
    // Φωτογραφίες ραφιού που λείπουν: κρατάμε μόνο την ετικέτα
    els.detailBody.querySelectorAll('.photos img[data-src]').forEach((img) => {
      img.addEventListener('error', () => img.remove(), { once: true });
      img.src = img.dataset.src; img.removeAttribute('data-src');
    });
    hookImages(els.detailBody);
    if (!els.dialog.open) els.dialog.showModal();
    writeHash(b.id);
  }

  init();
})();
