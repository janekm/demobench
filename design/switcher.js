// Small floating control for flipping between the design directions.
(() => {
  const pages = [
    ['control-room.html', 'Control Room'],
    ['teletext.html', 'Teletext'],
    ['contact-sheet.html', 'Contact Sheet'],
    ['byte-plates.html', 'Byte Plates'],
    ['console.html', 'Cartridges'],
  ];
  const here = location.pathname.split('/').pop();
  const i = pages.findIndex(([file]) => file === here);
  if (i < 0) return;
  const prev = pages[(i + pages.length - 1) % pages.length], next = pages[(i + 1) % pages.length];
  const nav = document.createElement('nav');
  nav.className = 'dx-switcher';
  nav.setAttribute('aria-label', 'Design directions');
  nav.innerHTML = `<a href="${prev[0]}" title="${prev[1]}" aria-label="Previous direction: ${prev[1]}">‹</a>`
    + `<a href="index.html" class="dx-label">${i + 1}/${pages.length} · ${pages[i][1]}</a>`
    + `<a href="${next[0]}" title="${next[1]}" aria-label="Next direction: ${next[1]}">›</a>`;
  const style = document.createElement('style');
  style.textContent = `.dx-switcher{position:fixed;left:12px;bottom:12px;z-index:9999;display:flex;align-items:stretch;background:#111;color:#fff;font:600 11px/1 ui-sans-serif,system-ui,sans-serif;letter-spacing:.02em;box-shadow:0 4px 18px #0005;border:1px solid #fff3}
.dx-switcher a{color:inherit;text-decoration:none;padding:9px 11px;display:flex;align-items:center}
.dx-switcher a:hover{background:#fff;color:#111}.dx-switcher .dx-label{border-inline:1px solid #fff3}
@media print{.dx-switcher{display:none}}`;
  document.head.append(style);
  document.body.append(nav);
})();
