/*
  The keyboard layer. An operator lives in this console, so the mouse is
  optional: / searches, j and k walk the list, Enter opens, Esc backs out or
  closes, ? lists the keys. Only the page on top answers, and a screen opts in
  by marking its rows [data-nav-row].
*/
const Keys = (() => {
  function topPage() {
    const t = App.top();
    return t ? t.el : null;
  }

  function rows(page) {
    return page ? Array.from(page.querySelectorAll('[data-nav-row]:not([hidden])')) : [];
  }

  function index(list) {
    return list.findIndex((r) => r.classList.contains('sel'));
  }

  function select(page, i) {
    const list = rows(page);
    if (!list.length) return;
    const at = Math.max(0, Math.min(list.length - 1, i));
    list.forEach((r, n) => {
      r.classList.toggle('sel', n === at);
      r.setAttribute('aria-current', n === at ? 'true' : 'false');
    });
    list[at].scrollIntoView({ block: 'nearest' });
    document.dispatchEvent(new CustomEvent('helix:keyselect', { detail: { el: list[at] } }));
  }

  function help() {
    App.sheet({
      title: 'Keyboard',
      text: 'These work on every screen of the console.',
      items: [
        { icon: 'magnifying-glass', label: '/', sub: 'Go to the search field' },
        { icon: 'arrow-down', label: 'j / k', sub: 'Move down / up the list' },
        { icon: 'enter', label: 'Enter', sub: 'Open the selected row' },
        { icon: 'arrow-left', label: 'Esc', sub: 'Close a dialog, or go back' },
        { icon: 'question', label: '?', sub: 'This list' },
        { icon: 'arrows-clockwise', label: 'r', sub: 'Reload this screen from the node' },
      ],
    });
  }

  function typing(el) {
    return el && (/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName) || el.isContentEditable);
  }

  function init() {
    document.addEventListener('keydown', (e) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.key === 'Escape') return;              // the overlays already handle it
      if (typing(document.activeElement)) {
        if (e.key === 'Enter' && document.activeElement.dataset.navRow) return;
        if (e.key === 'Enter' && App.overlayOpen()) return;
        if (e.key !== 'Escape') return;
      }
      const page = topPage();
      if (!page) return;
      const list = rows(page);
      if (e.key === '/') {
        const f = page.querySelector('input[type="search"], .searchbar input, input[type="text"]');
        if (f) { e.preventDefault(); f.focus(); f.select && f.select(); }
        return;
      }
      if (e.key === '?') { e.preventDefault(); help(); return; }
      if (e.key === 'r' && !list.length) { e.preventDefault(); document.getElementById('stripRefresh')?.click(); return; }
      if (e.key === 'j' || e.key === 'ArrowDown') {
        e.preventDefault(); select(page, index(list) < 0 ? 0 : index(list) + 1); return;
      }
      if (e.key === 'k' || e.key === 'ArrowUp') {
        e.preventDefault(); select(page, index(list) < 0 ? list.length - 1 : index(list) - 1); return;
      }
      if (e.key === 'Enter' && index(list) >= 0) {
        e.preventDefault(); list[index(list)].click();
      }
    });
  }

  return { init, help };
})();

document.addEventListener('DOMContentLoaded', () => Keys.init());
