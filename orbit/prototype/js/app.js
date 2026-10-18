/*
  Prototype engine: page stacks (like go_router pushes), overlays (sheets,
  menus, dialogs, snackbars), the screen index and the tweaks panel.
  Screens register themselves with App.register({...}).

  Two layouts:
  - Phone: one page stack.
  - Window (840 px and wider, the app's HelixBreakpoints.medium): a list pane
    on the left, a detail pane on the right, an info pane beside the chat from
    1200 px (HelixBreakpoints.expanded), and a full-window layer for calls,
    the media viewer and the sign-in box. PLACEMENT says where each screen
    goes; screens themselves do not know which layout they are in.
*/
const App = (() => {
  const screens = new Map();
  const entries = []; // index rows: { key, group, label, screen, params, base }
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  let currentKey = null;

  // ---------------------------------------------------------------- layout
  const DEVICES = {
    phone: { w: 412, h: 866, label: 'Phone' },
    'window-m': { w: 960, h: 720, label: 'Window 960' },
    'window-l': { w: 1280, h: 800, label: 'Window 1280' },
  };
  let device = 'phone';
  const isWide = () => device !== 'phone';
  const hasInfoPane = () => DEVICES[device].w >= 1200;
  const LIST_W = 380; // the list pane's width (the app's ChatsTab._listWidth)

  // Where a screen opens on a wide window:
  //   list    replaces the left pane; back returns to what was there
  //   detail  replaces what the right pane shows (picking a chat or a call)
  //   info    beside the chat from 1200 px; over the chat on narrower windows
  //   full    covers the window: calls, the media viewer, the sign-in box
  // Anything not listed opens in the pane it was opened from, or on the right
  // when it was opened from the list.
  const PLACEMENT = {
    home: 'list', archived: 'list', 'settings-page': 'list', 'group-new': 'list', 'group-join': 'list',
    chat: 'detail', 'call-detail': 'detail',
    contact: 'info', 'group-info': 'info', shared: 'info', 'chat-settings': 'info', 'message-info': 'info',
    call: 'full', 'media-viewer': 'full', signin: 'full', reset: 'full', lock: 'full',
  };
  const placement = (id, params) => (id === 'restore' && params.afterSignIn ? 'full' : PLACEMENT[id] || 'inherit');
  const UNBOXED = ['call', 'media-viewer']; // full-window screens that are not drawn as the centred box

  // The right pane remembers what it showed for each list (Chats, Calls, You).
  const contextOf = (e) => (e.id === 'home' ? (e.state && e.state.tab) || e.params.tab || 'chats' : e.id === 'settings-page' ? 'you' : 'chats');
  // Behaviour every screen gets from the app frame, not from the screen itself
  // ([gesture, on, does, layout?]). Exported to screens.json with each screen's own list.
  const GLOBAL_INTERACTIONS = [
    ['tap', 'Back arrow', 'Returns to the previous page; on a window, in the same pane.'],
    ['key', 'Esc', 'Closes the topmost thing: a menu or sheet, then a call or the viewer, the info pane, the right pane.', 'window'],
    ['key', 'Esc', 'Goes back, like the back arrow.', 'phone'],
    ['tap', 'Outside a sheet, menu or dialog', 'Closes it.'],
    ['tap', 'Menu or sheet row', 'Runs it and closes the menu or sheet.'],
    ['tap', 'Undo on a toast', 'Undoes what the toast reported.'],
    ['auto', 'Toast', 'Disappears after 2.8 s.'],
    ['tap', 'A row, tile or chat in the list pane', 'Replaces what the right pane shows; it stays marked in the list.', 'window'],
    ['auto', 'Right pane', 'Remembers its page for each list (Chats, Calls, You) and brings it back.', 'window'],
    ['auto', 'Info pages (contact, group, media, chat settings, message info)', 'Open beside the chat from 1200 px, over it below.', 'window'],
    ['auto', 'Menus', 'Hang from the button that opened them.', 'window'],
    ['auto', 'Sheets', 'Open as centred dialogs; a sheet from the composer pops up above its button.', 'window'],
  ];

  const PLACEHOLDER = {
    chats: { icon: 'chats-circle', title: 'Pick a chat', text: 'Choose a conversation on the left, or start a new one.', note: 'Messages are end-to-end encrypted' },
    calls: { icon: 'phone', title: 'Pick a call', text: 'Choose a call on the left to see its details, or start a new call.' },
    you: { icon: 'user-circle-gear', title: 'Pick a setting', text: 'Choose a topic on the left. Changes save as you go.' },
  };

  const P = { main: [], list: [], detail: [], info: [], full: [] }; // page stacks by pane
  let stashes = new Map(); // context -> { detail, info } while another list shows
  let ctx = null;          // the list context the right pane belongs to
  let lastPane = null;     // the pane the person last touched
  let lastPress = null;    // the control the person last pressed (anchors menus)
  const allEntries = () => [...Object.values(P).flat(), ...[...stashes.values()].flatMap((s) => [...s.detail, ...s.info])];
  const hostOf = (pane) => (pane === 'main' ? $('#stack') : $(`#stack > [data-pane="${pane}"]`));

  // ---------------------------------------------------------------- screens
  function register(def) {
    screens.set(def.id, def);
    (def.entries || [{ label: def.title, params: {} }]).forEach((e, i) => {
      entries.push({
        key: e.key || (i === 0 ? def.id : `${def.id}:${i}`),
        group: e.group || def.group,
        label: e.label,
        screen: def.id,
        params: e.params || {},
        base: e.base !== undefined ? e.base : def.base,
        order: e.order ?? def.order ?? 100,
      });
    });
  }

  function makePage(id, params, pane = 'main', root = false) {
    const def = screens.get(id);
    if (!def) throw new Error(`No screen ${id}`);
    const el = document.createElement('section');
    el.className = 'page' + (def.night ? ' night' : '');
    el.dataset.screen = id;
    const entry = { id, params: { ...params }, el, state: {}, pane, root };
    entry.rerender = () => paint(entry);
    paint(entry);
    return entry;
  }

  function paint(entry) {
    const def = screens.get(entry.id);
    const scrollers = $$('[data-keep-scroll]', entry.el).map((n) => [n.dataset.keepScroll, n.scrollTop]);
    entry.el.innerHTML = def.render(entry.params, entry);
    scrollers.forEach(([k, top]) => { const n = $(`[data-keep-scroll="${k}"]`, entry.el); if (n) n.scrollTop = top; });
    def.mount && def.mount(entry.el, entry.params, entry);
    decorate(entry);
  }

  // Window touches the screens do not draw themselves: no back arrow on the
  // first page of the right pane (the list is the way back), a close button
  // on the info pane, and the centred box for sign-in, reset and lock.
  function decorate(entry) {
    if (!isWide()) return;
    const el = entry.el;
    el.classList.toggle('detail-root', entry.root && entry.pane === 'detail');
    el.classList.toggle('boxed', entry.pane === 'full' && !UNBOXED.includes(entry.id));
    if (entry.root && entry.pane === 'info') {
      const b = el.querySelector(':scope > header > .ibtn[data-back]');
      if (b) { b.innerHTML = UI.icon('x'); b.title = 'Close'; b.setAttribute('aria-label', 'Close'); }
    }
    if (entry.pane === 'list' && P.list.includes(entry)) { syncContext(); markCurrent(); }
  }

  function top() {
    if (!isWide()) return P.main[P.main.length - 1];
    return ['full', 'info', 'detail', 'list'].map((p) => P[p][P[p].length - 1]).find(Boolean);
  }

  function syncChrome() {
    const t = top();
    const def = t && screens.get(t.id);
    $('#phoneScreen').classList.toggle('on-night', !!(def && def.night));
  }

  // Which pane a screen opens in, given the pane it was opened from.
  function route(id, params, from) {
    const k = placement(id, params);
    if (k === 'full' || k === 'list') return { pane: k };
    if (from === 'full') return { pane: 'full' };
    if (k === 'detail') return { pane: 'detail', reset: true };
    if (k === 'info') {
      if (from === 'detail') return hasInfoPane() ? { pane: 'info', reset: true } : { pane: 'detail' };
      if (from === 'info') return { pane: 'info' };
      return { pane: 'detail', reset: true };
    }
    if (from === 'detail' || from === 'info') return { pane: from };
    return { pane: 'detail', reset: true };
  }

  function clear(panes) { panes.forEach((p) => P[p].splice(0).forEach((e) => e.el.remove())); }

  function clearAll() {
    clear(Object.keys(P));
    stashes = new Map(); ctx = null; lastPane = null;
    refreshPanes();
  }

  function push(id, params = {}, { animate = true, from } = {}) {
    closeOverlays();
    if (!isWide()) return pushTo('main', id, params, animate);
    const r = route(id, params, from !== undefined ? from : P.full.length ? 'full' : lastPane);
    if (r.reset) clear(r.pane === 'detail' ? ['detail', 'info'] : ['info']);
    const entry = pushTo(r.pane, id, params, animate, r.reset);
    lastPane = r.pane;
    if (r.pane === 'list') syncContext();
    refreshPanes();
    return entry;
  }

  function pushTo(pane, id, params, animate, swap) {
    const arr = P[pane];
    const prev = arr[arr.length - 1];
    const entry = makePage(id, params, pane, arr.length === 0);
    // A page that replaces the right pane fades in; one pushed on top slides in.
    const fade = screens.get(id).modal || swap || (pane !== 'main' && pane !== 'info' && !prev);
    if (animate) entry.el.classList.add(fade ? 'fade-enter' : 'enter');
    hostOf(pane).appendChild(entry.el);
    arr.push(entry);
    if (animate) {
      requestAnimationFrame(() => requestAnimationFrame(() => {
        entry.el.classList.remove('enter', 'fade-enter');
        prev && prev.el.classList.add('under');
      }));
    } else if (prev) prev.el.classList.add('under');
    syncChrome();
    return entry;
  }

  // App.pop is often a click listener: the click says which pane to go back in.
  function pop(ev) {
    if (overlayOpen()) { closeOverlays(); return; }
    if (!isWide()) { popFrom('main', 1); return; }
    const from = ev && ev.target && ev.target.closest ? ev.target.closest('.wpane') : null;
    const pane = P.full.length ? 'full' : from ? from.dataset.pane : lastPane || 'list';
    popFrom(pane, pane === 'list' ? 1 : 0);
  }

  function popFrom(pane, min) {
    const arr = P[pane];
    if (arr.length <= min) return;
    const leaving = arr.pop();
    const prev = arr[arr.length - 1];
    leaving.el.classList.add(screens.get(leaving.id).modal || (!prev && pane !== 'main' && pane !== 'info') ? 'fade-enter' : 'leave');
    if (prev) {
      prev.el.classList.remove('under');
      screens.get(prev.id).refreshOnReturn && prev.rerender();
    }
    setTimeout(() => leaving.el.remove(), 280);
    if (pane === 'detail' && !arr.length) clear(['info']);
    if (pane === 'list') syncContext();
    refreshPanes();
    syncChrome();
  }

  // Esc closes the topmost thing: an overlay, the full-window layer, the info
  // pane, the right pane, then the list's own back.
  function escape() {
    if (overlayOpen()) { closeOverlays(); return; }
    if (!isWide()) { pop(); return; }
    const pane = ['full', 'info', 'detail'].find((p) => P[p].length);
    if (pane) popFrom(pane, 0); else popFrom('list', 1);
  }

  function popTo(id) {
    if (!isWide()) {
      while (P.main.length > 1 && top().id !== id) P.main.pop().el.remove();
      top().el.classList.remove('under'); syncChrome(); return;
    }
    const pane = ['list', 'detail', 'info', 'full'].find((p) => P[p].some((e) => e.id === id)) || 'list';
    while (P[pane].length > 1 && P[pane][P[pane].length - 1].id !== id) P[pane].pop().el.remove();
    const t = P[pane][P[pane].length - 1]; t && t.el.classList.remove('under');
    if (pane === 'list') { clear(['detail', 'info']); syncContext(); }
    lastPane = pane;
    refreshPanes(); syncChrome();
  }

  function replace(id, params = {}) {
    if (!isWide()) {
      const old = P.main.pop(); old && old.el.remove();
      return push(id, params, { animate: false });
    }
    const pane = P.full.length ? 'full' : lastPane || 'list';
    const old = P[pane].pop(); old && old.el.remove();
    const t = P[pane][P[pane].length - 1]; t && t.el.classList.remove('under');
    if (pane === 'list') syncContext();
    return push(id, params, { animate: false, from: pane });
  }

  function reset(id, params = {}) {
    closeOverlays();
    clearAll();
    return push(id, params, { animate: false, from: null });
  }

  // The list changed (a push, a pop, or Home switching tabs): park the right
  // pane under the old list and bring back what the new list had open.
  function syncContext() {
    if (!isWide()) return;
    const lt = P.list[P.list.length - 1];
    const next = lt ? contextOf(lt) : null;
    if (next === ctx) return;
    if (ctx) {
      const s = { detail: P.detail.splice(0), info: P.info.splice(0) };
      [...s.detail, ...s.info].forEach((e) => e.el.remove());
      if (s.detail.length) stashes.set(ctx, s);
    }
    ctx = next;
    const s = next && stashes.get(next);
    if (s) {
      stashes.delete(next);
      ['detail', 'info'].forEach((p) => s[p].forEach((e) => { P[p].push(e); hostOf(p).appendChild(e.el); }));
    }
    refreshPanes();
  }

  function refreshPanes() {
    if (!isWide()) return;
    const s = $('#stack');
    s.classList.toggle('info-open', P.info.length > 0);
    s.classList.toggle('full-open', P.full.length > 0);
    const empty = $('#wEmpty');
    if (empty) {
      const show = !P.detail.length;
      empty.hidden = !show;
      if (show) {
        const p = PLACEHOLDER[ctx] || PLACEHOLDER.chats;
        empty.innerHTML = `<div class="we-art" aria-hidden="true"><span class="we-ring"></span><span class="we-core">${UI.icon(p.icon, 'fill')}</span><span class="we-moon"></span></div>
          <h2 class="we-title">${p.title}</h2><p class="we-text">${p.text}</p>${p.note ? `<div class="we-note mono">${UI.icon('lock-simple')}${p.note}</div>` : ''}`;
      }
    }
    markCurrent();
  }

  // The row or tile whose page is open on the right stays highlighted.
  function markCurrent() {
    if (!isWide()) return;
    const lt = P.list[P.list.length - 1];
    if (!lt) return;
    $$('.current', lt.el).forEach((n) => n.classList.remove('current'));
    const d = P.detail[0];
    if (!d) return;
    const sel = d.id === 'chat' ? `[data-chat="${CSS.escape(String(d.params.id || ''))}"]`
      : d.id === 'call-detail' ? `[data-call="${CSS.escape(String(d.params.id || ''))}"]`
        : `.stile[data-go="${d.id}"], .card [data-go="${d.id}"]:not(.ibtn)`;
    $$(sel, lt.el).forEach((n) => n.classList.add('current'));
  }

  // Jump from the index: rebuild a believable back stack, then open the state.
  function open(key, { remember = true } = {}) {
    const e = entries.find((x) => x.key === key) || entries[0];
    currentKey = e.key;
    closeOverlays(true);
    clearAll();
    const bases = [e.base].flat(Infinity).filter(Boolean);
    bases.forEach((b) => push(b.screen, b.params || {}, { animate: false }));
    const entry = push(e.screen, e.params, { animate: false });
    const def = screens.get(e.screen);
    if (def.afterOpen) def.afterOpen(entry.el, entry.params, entry);
    $$('.v-item').forEach((b) => b.classList.toggle('active', b.dataset.key === e.key));
    $('#vCurrent').textContent = `${e.group} / ${e.label}`;
    if (remember) { try { history.replaceState(null, '', `#${encodeURIComponent(e.key)}`); } catch (_) {} }
    document.getElementById('viewer').classList.remove('index-open');
  }

  // --------------------------------------------------------------- overlays
  const overlays = [];
  function overlayOpen() { return overlays.length > 0; }

  function mountOverlay(html, { cls, onClose, scrim = true, dismiss = true } = {}) {
    const root = $('#overlayRoot');
    const wrap = document.createElement('div');
    wrap.style.cssText = 'position:absolute;inset:0;';
    wrap.innerHTML = (scrim ? '<div class="scrim"></div>' : '') + html;
    root.appendChild(wrap);
    const panel = wrap.lastElementChild;
    const close = (instant) => {
      const i = overlays.indexOf(handle);
      if (i < 0) return;
      overlays.splice(i, 1);
      wrap.querySelectorAll('.in').forEach((n) => n.classList.remove('in'));
      setTimeout(() => wrap.remove(), instant ? 0 : 240);
      onClose && onClose();
    };
    const handle = { wrap, panel, close };
    overlays.push(handle);
    if (dismiss) wrap.querySelector('.scrim')?.addEventListener('click', () => close());
    requestAnimationFrame(() => requestAnimationFrame(() => wrap.querySelectorAll('.scrim, .sheet, .popmenu, .dialog').forEach((n) => n.classList.add('in'))));
    return handle;
  }

  function closeOverlays(instant) { [...overlays].reverse().forEach((o) => o.close(instant)); }

  // Bottom sheet. items: [{icon, label, sub, danger, on, run}] or html body.
  function sheet({ title, text, items, body, onClose }) {
    const head = title || text ? `<div class="sh-head">${title ? `<h2>${title}</h2>` : ''}${text ? `<p>${text}</p>` : ''}</div>` : '';
    const rows = items ? items.map((it, i) => it === '-' ? '<hr style="border:0;height:1px;background:var(--line-2);margin:6px 0">' :
      `<button class="menu-row ${it.danger ? 'danger' : ''} ${it.on ? 'on' : ''}" data-i="${i}">${UI.icon(it.icon)}<span style="flex:1">${it.label}${it.sub ? `<span class="mr-sub">${it.sub}</span>` : ''}</span>${it.on ? UI.icon('check', 'bold') : ''}</button>`).join('') : '';
    const h = mountOverlay(`<div class="sheet" role="dialog" aria-modal="true"><div class="grab"></div>${head}<div class="sh-body">${body || rows}</div></div>`, { onClose });
    // On a window, a sheet opened from the composer pops up above its button
    // instead of in the middle of the window.
    if (isWide() && lastPress && lastPress.isConnected && lastPress.closest('.composer')) {
      const root = $('#overlayRoot'); const rr = root.getBoundingClientRect();
      const s = rr.width / root.offsetWidth || 1; const br = lastPress.getBoundingClientRect();
      h.panel.classList.add('anchored');
      h.panel.style.bottom = `${(rr.bottom - br.top) / s + 8}px`;
      h.panel.style.right = `${Math.max(8, (rr.right - br.right) / s - 12)}px`;
      h.wrap.querySelector('.scrim').style.background = 'transparent';
    }
    if (items) $$('.menu-row', h.panel).forEach((b) => b.addEventListener('click', () => { const it = items[+b.dataset.i]; h.close(); it.run && setTimeout(() => it.run(), 60); }));
    return h;
  }

  // Popup menu under the app bar's overflow button.
  function menu(items, { top: y = 92 } = {}) {
    const rows = items.map((it, i) => it === '-' ? '<hr>' : `<button class="menu-row ${it.danger ? 'danger' : ''}" data-i="${i}">${UI.icon(it.icon)}<span>${it.label}</span></button>`).join('');
    const h = mountOverlay(`<div class="popmenu" role="menu" style="top:${y}px">${rows}</div>`, { scrim: true });
    h.wrap.querySelector('.scrim').style.background = 'transparent';
    // On a window the menu hangs from the button that opened it.
    if (isWide() && lastPress && lastPress.isConnected) {
      const root = $('#overlayRoot'); const rr = root.getBoundingClientRect();
      const s = rr.width / root.offsetWidth || 1; const br = lastPress.getBoundingClientRect();
      h.panel.style.top = `${(br.bottom - rr.top) / s + 4}px`;
      h.panel.style.right = `${Math.max(8, (rr.right - br.right) / s)}px`;
    }
    $$('.menu-row', h.panel).forEach((b) => b.addEventListener('click', () => { const it = items[+b.dataset.i]; h.close(); it.run && setTimeout(() => it.run(), 60); }));
    return h;
  }

  function dialog({ title, text, actions }) {
    const btns = actions.map((a, i) => `<button class="btn ${a.kind || 'ghost'}" data-i="${i}">${a.label}</button>`).join('');
    const h = mountOverlay(`<div class="dialog" role="alertdialog" aria-modal="true"><h2>${title}</h2>${text ? `<p>${text}</p>` : ''}<div class="dl-actions">${btns}</div></div>`);
    $$('.btn', h.panel).forEach((b) => b.addEventListener('click', () => { const a = actions[+b.dataset.i]; h.close(); a.run && setTimeout(() => a.run(), 60); }));
    return h;
  }

  let snackTimer;
  function snack(text, action) {
    const s = $('#snackbar');
    s.innerHTML = `<span>${text}</span>${action ? `<button class="sn-action" style="border:0;background:none">${action.label}</button>` : ''}`;
    if (action) s.querySelector('.sn-action').addEventListener('click', () => { s.classList.remove('in'); action.run && action.run(); });
    s.style.pointerEvents = action ? 'auto' : 'none';
    s.classList.add('in');
    clearTimeout(snackTimer);
    snackTimer = setTimeout(() => s.classList.remove('in'), 2800);
  }

  // ------------------------------------------------------------ the index
  function buildIndex() {
    const list = $('#vList');
    const q = ($('#vFilter').value || '').trim().toLowerCase();
    const groups = [];
    entries.forEach((e) => {
      if (q && !(`${e.group} ${e.label}`.toLowerCase().includes(q))) return;
      let g = groups.find((x) => x.name === e.group);
      if (!g) groups.push(g = { name: e.group, order: e.order, items: [] });
      g.items.push(e);
    });
    groups.sort((a, b) => a.order - b.order);
    list.innerHTML = groups.map((g) => `<div class="v-group">${g.name}</div>` + g.items.map((e) =>
      `<button class="v-item ${e.key === currentKey ? 'active' : ''}" data-key="${e.key}">${e.label}</button>`).join('')).join('');
    $$('.v-item', list).forEach((b) => b.addEventListener('click', () => open(b.dataset.key)));
  }

  // ------------------------------------------------------------- tweaks
  const TWEAKS_KEY = 'helix-proto-tweaks-v2';
  const accents = {
    blue: { label: 'Orbit blue', accent: '#2563EB', ink: '#1D4FC4', soft: '#E8F0FE', line: '#C4D6FB' },
    indigo: { label: 'Indigo', accent: '#4F5BD5', ink: '#3A45B0', soft: '#ECEEFC', line: '#CCD1F6' },
    violet: { label: 'Violet', accent: '#6E47E0', ink: '#5532BF', soft: '#F0EBFD', line: '#D7CBF8' },
    teal: { label: 'Teal', accent: '#0E8A8A', ink: '#0B6C6C', soft: '#E1F4F4', line: '#B5E1E1' },
  };
  const bubbles = {
    paleCyan: { label: 'Pale cyan', out: '#E1F7FC', line: '#B2E7F2', ink: '#0A2A33', meta: '#3B6D79' },
    cyan: { label: 'Solid cyan', out: '#5FD3E8', line: '#4CC6DD', ink: '#062229', meta: '#0D4955' },
    ink: { label: 'Dark ink', out: '#151A26', line: '#151A26', ink: '#F2F5FB', meta: '#8FD8E8' },
    tint: { label: 'Indigo tint', out: '#ECEEFC', line: '#D6DAF8', ink: '#131722', meta: '#545D86' },
  };
  const defaults = { accent: 'blue', bubble: 'paleCyan', avatar: 25, bubbleR: 9, cut: true, bg: 'plain', density: 72, text: 100, dockLabels: false, targets: false };
  let tweaks = { ...defaults };

  function loadTweaks() { try { Object.assign(tweaks, JSON.parse(localStorage.getItem(TWEAKS_KEY) || '{}')); } catch (_) {} }
  function saveTweaks() { try { localStorage.setItem(TWEAKS_KEY, JSON.stringify(tweaks)); } catch (_) {} }

  function applyTweaks() {
    // Colour and shape tweaks only touch the Orbit theme; density and text size apply to all.
    document.documentElement.removeAttribute('style');
    let tag = document.getElementById('tweakStyle');
    if (!tag) { tag = document.createElement('style'); tag.id = 'tweakStyle'; document.head.appendChild(tag); }
    const a = accents[tweaks.accent] || accents.blue;
    const b = bubbles[tweaks.bubble] || bubbles.paleCyan;
    tag.textContent = `:root, [data-theme="orbit"] { --accent: ${a.accent}; --accent-ink: ${a.ink}; --accent-soft: ${a.soft}; --accent-line: ${a.line}; --read: ${a.accent}; `
      + `--out: ${b.out}; --out-line: ${b.line}; --out-ink: ${b.ink}; --out-meta: ${b.meta}; --avatar-r: ${tweaks.avatar}%; --bubble-r: ${tweaks.bubbleR}px; }\n`
      + `:root { --row-h: ${tweaks.density}px; --text-scale: ${tweaks.text / 100}; }`;
    const bc = document.body.classList;
    bc.toggle('no-cut', !tweaks.cut);
    bc.remove('bg-dots', 'bg-plain', 'bg-helix'); bc.add(`bg-${tweaks.bg}`);
    bc.toggle('dock-labels', !!tweaks.dockLabels);
    bc.toggle('show-targets', !!tweaks.targets);
    document.body.dataset.bubble = tweaks.bubble;
  }

  function seg(key, options) {
    return `<div class="t-seg" data-key="${key}">${Object.entries(options).map(([v, o]) =>
      `<button data-v="${v}" class="${String(tweaks[key]) === v ? 'on' : ''}">${o.swatch ? `<span class="t-swatch" style="background:${o.swatch}"></span>` : ''}${o.label}</button>`).join('')}</div>`;
  }
  function range(key, min, max, step, unit) {
    return `<input type="range" data-key="${key}" min="${min}" max="${max}" step="${step}" value="${tweaks[key]}" aria-label="${key}"><output data-for="${key}"></output>`;
  }
  function buildTweaks() {
    const body = $('#tBody');
    const accentOpts = Object.fromEntries(Object.entries(accents).map(([k, v]) => [k, { label: v.label, swatch: v.accent }]));
    const bubbleOpts = Object.fromEntries(Object.entries(bubbles).map(([k, v]) => [k, { label: v.label, swatch: v.out }]));
    const themeRow = `<div class="t-row"><div class="t-label">Theme</div><div class="t-seg" id="tTheme">${(window.OrbitThemes || []).map((t) =>
      `<button data-theme-pick="${t.id}" class="${t.id === theme ? 'on' : ''}"><span class="t-swatch" style="background:${t.swatches[1]};box-shadow:inset 0 0 0 3px ${t.swatches[0]}"></span>${t.name}</button>`).join('')}</div></div>`;
    body.innerHTML = `${themeRow}
      <div class="t-label" style="margin:14px 0 0;color:var(--ink-3)">The rows below shape the Orbit theme</div>
      <div class="t-row"><div class="t-label">Accent colour</div>${seg('accent', accentOpts)}</div>
      <div class="t-row"><div class="t-label">Your bubbles</div>${seg('bubble', bubbleOpts)}</div>
      <div class="t-row"><div class="t-label">Avatar roundness <output>${tweaks.avatar}%</output></div>${range('avatar', 0, 50, 1)}</div>
      <div class="t-row"><div class="t-label">Bubble roundness <output>${tweaks.bubbleR}px</output></div>${range('bubbleR', 6, 26, 1)}</div>
      <div class="t-row"><label class="t-check"><input type="checkbox" data-key="cut" ${tweaks.cut ? 'checked' : ''}> Sharp corner on first bubble</label></div>
      <div class="t-row"><div class="t-label">Chat background</div>${seg('bg', { dots: { label: 'Dot grid' }, plain: { label: 'Plain' }, helix: { label: 'Orbit lines' } })}</div>
      <div class="t-row"><div class="t-label">List density</div>${seg('density', { 72: { label: 'Comfortable' }, 64: { label: 'Compact' }, 80: { label: 'Roomy' } })}</div>
      <div class="t-row"><div class="t-label">Text size <output>${tweaks.text}%</output></div>${range('text', 90, 125, 5)}</div>
      <div class="t-row"><label class="t-check"><input type="checkbox" data-key="dockLabels" ${tweaks.dockLabels ? 'checked' : ''}> Dock: label every tab</label></div>
      <div class="t-row"><label class="t-check"><input type="checkbox" data-key="targets" ${tweaks.targets ? 'checked' : ''}> Show tap targets</label></div>`;
    $$('[data-theme-pick]', body).forEach((b) => b.addEventListener('click', () => setTheme(b.dataset.themePick)));
    $$('.t-seg[data-key]', body).forEach((s) => s.addEventListener('click', (ev) => {
      const b = ev.target.closest('button'); if (!b) return;
      const key = s.dataset.key; const v = b.dataset.v;
      tweaks[key] = typeof defaults[key] === 'number' ? Number(v) : v;
      $$('button', s).forEach((x) => x.classList.toggle('on', x === b));
      applyTweaks(); saveTweaks();
    }));
    $$('input[type=range]', body).forEach((i) => i.addEventListener('input', () => {
      tweaks[i.dataset.key] = Number(i.value);
      i.closest('.t-row').querySelector('.t-label output').textContent = i.value + (i.dataset.key === 'bubbleR' ? 'px' : '%');
      applyTweaks(); saveTweaks();
    }));
    $$('input[type=checkbox]', body).forEach((i) => i.addEventListener('change', () => { tweaks[i.dataset.key] = i.checked; applyTweaks(); saveTweaks(); }));
  }

  // -------------------------------------------------------------- themes
  // The chosen theme sits on the phone screen and stays until the person picks
  // another (no automatic day/night switching). Every open page redraws in it.
  const THEME_KEY = 'orbit-theme';
  let theme = 'orbit';
  const themeById = (id) => (window.OrbitThemes || []).find((t) => t.id === id) || (window.OrbitThemes || [])[0] || { id: 'orbit', icon: '' };
  function setTheme(id, { animate = true, save = true } = {}) {
    const t = themeById(id); theme = t.id;
    const ps = $('#phoneScreen');
    ps.dataset.theme = t.id; ps.classList.toggle('theme-dark', !!t.dark);
    UI.setIconWeight(t.icon);
    if (save) { try { localStorage.setItem(THEME_KEY, t.id); } catch (_) {} }
    allEntries().forEach((e) => e.rerender());
    refreshPanes();
    $$('#tTheme [data-theme-pick]').forEach((b) => b.classList.toggle('on', b.dataset.themePick === t.id));
    if (animate && ps.animate) ps.animate([{ opacity: 0.25, filter: 'blur(2px)' }, { opacity: 1, filter: 'blur(0)' }], { duration: 360, easing: 'cubic-bezier(.2,.7,.2,1)' });
  }
  const getTheme = () => themeById(theme);

  // Render the device at true size and scale it to fit the stage.
  function fitPhone() {
    const holder = $('#phoneHolder'); const phone = $('#phone');
    if (window.innerWidth <= 520) { holder.style.height = ''; holder.style.width = ''; phone.style.transform = ''; return; }
    const { w: W, h: H } = DEVICES[device];
    const bare = document.body.classList.contains('bare');
    const w = holder.clientWidth; const h = holder.parentElement.clientHeight - (bare ? 0 : $('.v-stage-top').offsetHeight + 30);
    const s = Math.min(1, w / W, h / H);
    phone.style.transform = `scale(${s})`;
    holder.style.height = `${H * s}px`;
    holder.style.flex = 'none';
  }

  // Phone or window. Switching rebuilds the open screen in the new layout.
  const DEVICE_KEY = 'orbit-device';
  function setDevice(d, { save = true, reopen = true } = {}) {
    if (!DEVICES[d]) d = 'phone';
    clearAll();
    device = d;
    const phone = $('#phone');
    phone.classList.toggle('window', isWide());
    $('#phoneScreen').classList.toggle('win', isWide());
    phone.style.width = isWide() ? `${DEVICES[d].w}px` : '';
    phone.style.height = isWide() ? `${DEVICES[d].h}px` : '';
    phone.style.setProperty('--list-w', `${LIST_W}px`);
    $('#stack').className = 'stack';
    $('#stack').innerHTML = isWide()
      ? '<div class="wpane" data-pane="list"></div><div class="wpane" data-pane="detail"><div class="w-empty" id="wEmpty" hidden></div></div><div class="wpane" data-pane="info"></div><div class="wpane wfull" data-pane="full"></div>'
      : '';
    $$('#vDevice [data-device]').forEach((b) => b.classList.toggle('on', b.dataset.device === d));
    if (save) { try { localStorage.setItem(DEVICE_KEY, d); } catch (_) {} }
    fitPhone();
    if (reopen && currentKey) open(currentKey, { remember: false });
  }

  // --------------------------------------------------------------- boot
  // ?bare draws only the device at true size (for screenshots and side-by-side
  // comparison); ?device=phone|window-m|window-l and ?theme=<id> pick without
  // saving. The screen is the hash: ?bare&device=window-l&theme=arcade#group
  function boot() {
    let dev = null; let q = null;
    try { q = new URLSearchParams(location.search); dev = q.get('device') || localStorage.getItem(DEVICE_KEY); } catch (_) {}
    if (q && q.has('bare')) document.body.classList.add('bare');
    // ?manifest prints every screen state as JSON (tools/manifest.py writes it to screens.json).
    if (q && q.has('manifest')) {
      const screensOut = entries.map((e) => ({
        key: e.key, group: e.group, label: e.label, screen: e.screen, params: e.params,
        base: [e.base].flat(Infinity).filter(Boolean).map((b) => ({ screen: b.screen, params: b.params || {} })),
        placement: placement(e.screen, e.params),
      }));
      const screenDefs = Object.fromEntries([...screens.values()].map((d) => [d.id, {
        title: d.title, group: d.group, placement: placement(d.id, {}), night: !!d.night,
        interactions: d.interactions === undefined ? null : d.interactions.map(([gesture, on, does, only]) => ({ gesture, on, does, ...(only ? { only } : {}) })),
      }]));
      const items = (list) => list.map(([gesture, on, does, only]) => ({ gesture, on, does, ...(only ? { only } : {}) }));
      const pre = document.createElement('pre'); pre.id = 'manifest';
      pre.textContent = JSON.stringify({
        devices: DEVICES, listWidth: LIST_W, placement: PLACEMENT,
        interactions: { global: items(GLOBAL_INTERACTIONS), components: items(Kit.INTERACTIONS) },
        screenDefs, screens: screensOut,
      });
      document.body.replaceChildren(pre);
      return;
    }
    setDevice(dev || 'phone', { save: false, reopen: false });
    // On a real phone (520 px or narrower) the prototype is always the phone layout.
    const fit = () => { if (isWide() && window.innerWidth > 0 && window.innerWidth <= 520) setDevice('phone', { save: false }); else fitPhone(); };
    window.addEventListener('resize', fit);
    $('#stack').addEventListener('pointerdown', (e) => { const p = e.target.closest('.wpane'); if (p) lastPane = p.dataset.pane; }, true);
    $('#phoneScreen').addEventListener('pointerdown', (e) => { const b = e.target.closest('button, [role="button"]'); if (b) lastPress = b; }, true);
    $$('#vDevice [data-device]').forEach((b) => b.addEventListener('click', () => setDevice(b.dataset.device)));
    let saved = null; try { saved = (q && q.get('theme')) || localStorage.getItem(THEME_KEY); } catch (_) {}
    setTheme(saved || 'orbit', { animate: false, save: false });
    loadTweaks();
    applyTweaks(); buildTweaks();
    $('#tReset').addEventListener('click', () => { tweaks = { ...defaults }; saveTweaks(); applyTweaks(); buildTweaks(); });
    $('#vFilter').addEventListener('input', buildIndex);
    $('#vIndexToggle').addEventListener('click', () => $('#viewer').classList.toggle('index-open'));
    $('#vTweaksToggle').addEventListener('click', () => $('#viewer').classList.toggle('tweaks-open'));
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') escape(); });
    window.addEventListener('hashchange', () => { let k = null; try { k = decodeURIComponent(location.hash.slice(1)); } catch (_) {} if (k && k !== currentKey && entries.some((x) => x.key === k)) open(k, { remember: false }); });
    let key = null;
    try { key = decodeURIComponent(location.hash.slice(1)) || null; } catch (_) {}
    if (!entries.some((e) => e.key === key)) key = entries.some((e) => e.key === 'chats') ? 'chats' : entries.slice().sort((a, b) => a.order - b.order)[0].key;
    currentKey = key;
    buildIndex();
    open(key);
  }

  return { register, push, pop, popTo, replace, reset, open, sheet, menu, dialog, snack, overlay: mountOverlay, closeOverlays, top, boot, $, $$, screens, setTheme, getTheme, themeById, setDevice, isWide, device: () => device, entries };
})();
