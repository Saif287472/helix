/*
  Console prototype engine: one page stack, the shell's active place, overlays
  (dialogs, sheets, toasts), the screen index and the manifest. Screens
  register with App.register({...}) and draw only their page; the app bar and
  the bottom bar belong to the shell.
*/
const App = (() => {
  const screens = new Map();
  const entries = [];
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  let stack = [];
  let currentKey = null;

  const DEVICES = {
    phone: { w: 412, h: 866, label: 'Phone' },
    'window-m': { w: 960, h: 720, label: 'Window 960' },
    'window-l': { w: 1280, h: 800, label: 'Window 1280' },
  };
  let device = 'phone';
  const isWide = () => device !== 'phone';

  const PLACE = {
    overview: 'Overview', users: 'Users', account: 'Users', invites: 'Invites',
    ops_reports: 'Ops', ops_audit: 'Ops', ops_logs: 'Ops', ops_config: 'Ops',
  };

  const GLOBAL_INTERACTIONS = [
    ['tap', 'A place in the header (window) or the floating dock (phone)', 'Opens that place. The frame stays where it is; the page changes.'],
    ['tap', 'Back arrow on an account page', 'Returns to Users & Devices.'],
    ['key', 'Esc', 'Closes a dialog first; otherwise goes back one page.'],
    ['tap', 'An account row, report card or invite card', 'Opens it; in a wide window an account opens beside the list instead.'],
    ['tap', 'A filter chip or the search field', 'Narrows the list in place; the count beside each chip is what it would show.'],
    ['tap', 'Refresh', 'Asks the server again and shows the page loading while it waits.'],
    ['tap', 'Resolve, Dismiss, Suspend, Resume, Revoke, Cancel, Purge, Create', 'Runs in place. Anything that changes a person or a session asks first.'],
    ['tap', 'Copy beside an ID or a code', 'Copies it and says so in a toast.'],
    ['auto', 'Toasts', 'Disappear after 3 s; errors stay 5 s and are read out.'],
    ['auto', 'The header chip', 'Shows the server’s name and a ready dot on every signed-in page. Invites appears only on servers that register by invite.'],
    ['auto', 'Destructive dialogs', 'Name the account or job and the effect, and keep Cancel as the default.'],
  ];
  const KIT_INTERACTIONS = [
    ['tap', 'Switch row', 'Toggles it; the whole row is the target. Saves at once and says so.'],
    ['tap', 'Password eye', 'Shows or hides the password.'],
    ['tap', 'Try again (could not be loaded)', 'Reloads the page; while it waits it shows the skeleton.'],
    ['type', 'Typed confirmation (DELETE, BAN)', 'The confirming button stays disabled until the word is exact.'],
    ['tap', 'Show a code once', 'The invite code is shown in a dialog once; after it closes only the code’s ID remains.'],
    ['auto', 'Loading lists', 'Placeholder rows the shape of the real ones, announced as loading.'],
    ['auto', 'Destructive dialogs', 'Keep Cancel as the default and name what will change.'],
  ];

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

  function top() { return stack[stack.length - 1]; }

  function makePage(id, params) {
    const def = screens.get(id);
    if (!def) throw new Error(`No screen ${id}`);
    const el = document.createElement('section');
    el.className = 'page';
    el.dataset.screen = id;
    const entry = { id, params: { ...params }, el, state: {} };
    entry.rerender = () => paint(entry);
    paint(entry);
    return entry;
  }

  function paint(entry) {
    const def = screens.get(entry.id);
    const scrollers = $$('[data-keep-scroll]', entry.el).map((n) => [n.dataset.keepScroll, n.scrollTop]);
    entry.el.innerHTML = def.render(entry.params, entry);
    scrollers.forEach(([k, t]) => { const n = $(`[data-keep-scroll="${k}"]`, entry.el); if (n) n.scrollTop = t; });
    def.mount && def.mount(entry.el, entry.params, entry);
    Kit.wire(entry.el, entry);
  }

  // ---------------------------------------------------------------- shell
  function invitesOn() {
    try { if (new URLSearchParams(location.search).get('invites') === '1') return true; } catch (_) {}
    return DATA.server.registration !== 'phone';
  }

  function syncChrome() {
    const t = top();
    const def = t && screens.get(t.id);
    const app = $('#app');
    const bare = !!(def && def.chrome === false);
    app.classList.toggle('auth', bare);
    if (!def) return;
    app.dataset.place = def.nav || 'none';
    $$('#topnav [data-nav], .tabbar [data-nav]').forEach((b) => {
      b.classList.toggle('on', b.dataset.nav === def.nav);
      b.setAttribute('aria-current', b.dataset.nav === def.nav ? 'page' : 'false');
    });
    $$('[data-invites]').forEach((n) => { n.hidden = !invitesOn(); });
    const ready = (t && t.ready) || def.ready || 'ok';
    const dot = $('#tbDot');
    if (dot) {
      dot.classList.toggle('ok', ready === 'ok');
      dot.classList.toggle('warn', ready === 'warn');
      dot.classList.toggle('bad', ready === 'bad');
      dot.title = ready === 'bad' ? 'Server unreachable' : ready === 'warn' ? 'Server not ready' : 'Server ready';
    }
    const name = DATA.server.name;
    const tb = $('#tbServer');
    if (tb) tb.textContent = name;
    document.title = `${def.title} · Helix Admin`;
    if (typeof Shell !== 'undefined') Shell.syncStrip();
  }

  function scrollTop() { const t = top(); const sc = t && t.el.querySelector('.scroll'); if (sc) sc.scrollTop = 0; }

  // ---------------------------------------------------------------- pages
  function push(id, params = {}, { animate = true } = {}) {
    closeOverlays(true);
    if (!screens.has(id)) return null;
    const prev = top();
    const entry = makePage(id, params);
    if (prev) {
      prev.el.classList.add('under');
      if (animate) entry.el.classList.add('enter');
    }
    $('#stack').appendChild(entry.el);
    stack.push(entry);
    if (animate) requestAnimationFrame(() => requestAnimationFrame(() => {
      entry.el.classList.remove('enter');
    }));
    syncChrome();
    const def = screens.get(id);
    def.afterOpen && def.afterOpen(entry.el, entry.params, entry);
    scrollTop();
    return entry;
  }

  function pop() {
    if (overlayOpen()) { closeOverlays(); return; }
    if (stack.length <= 1) return;
    const leaving = stack.pop();
    const prev = top();
    leaving.el.classList.remove('enter');
    leaving.el.classList.add('leave');
    setTimeout(() => leaving.el.remove(), 240);
    if (prev) prev.el.classList.remove('under');
    syncChrome();
  }

  function reset(id, params = {}) {
    closeOverlays(true);
    stack.forEach((e) => e.el.remove());
    stack = [];
    $('#stack').innerHTML = '';
    const entry = push(id, params, { animate: false });
    currentKey = findKey(id, params);
    highlightIndex();
    return entry;
  }

  function replace(id, params = {}) {
    if (stack.length) { const old = stack.pop(); old.el.remove(); }
    if (stack.length) stack[stack.length - 1].el.classList.remove('under');
    return push(id, params, { animate: false });
  }

  // Jump from the index: rebuild the base pages, then the state.
  function open(key, { remember = true } = {}) {
    const e = entries.find((x) => x.key === key) || entries[0];
    currentKey = e.key;
    closeOverlays(true);
    $('#snackbar').classList.remove('in');
    stack.forEach((x) => x.el.remove());
    stack = [];
    $('#stack').innerHTML = '';
    const bases = [e.base].flat(Infinity).filter(Boolean);
    bases.forEach((b) => push(b.screen, b.params || {}, { animate: false }));
    push(e.screen, e.params, { animate: false });
    $$('.v-item').forEach((b) => b.classList.toggle('active', b.dataset.key === e.key));
    $('#vCurrent').textContent = `${e.group} / ${e.label}`;
    highlightIndex();
    if (remember) { try { history.replaceState(null, '', `#${encodeURIComponent(e.key)}`); } catch (_) {} }
    $('#viewer').classList.remove('index-open');
  }

  function findKey(id, params) {
    const e = entries.find((x) => x.screen === id && JSON.stringify(x.params) === JSON.stringify(params));
    return e ? e.key : id;
  }
  function highlightIndex() { $$('.v-item').forEach((b) => b.classList.toggle('active', b.dataset.key === currentKey)); }

  // -------------------------------------------------------------- overlays
  const overlays = [];
  const overlayOpen = () => overlays.length > 0;

  function mountOverlay(html, { cls = '', onClose, scrim = true, dismiss = true } = {}) {
    const root = $('#overlayRoot');
    const wrap = document.createElement('div');
    wrap.className = cls;
    wrap.style.cssText = 'position:absolute;inset:0;';
    wrap.innerHTML = (scrim ? '<div class="scrim"></div>' : '') + html;
    root.appendChild(wrap);
    const panel = wrap.lastElementChild;
    const close = (instant) => {
      const i = overlays.indexOf(handle);
      if (i < 0) return;
      overlays.splice(i, 1);
      wrap.querySelectorAll('.in').forEach((n) => n.classList.remove('in'));
      setTimeout(() => wrap.remove(), instant ? 0 : 180);
      onClose && onClose();
    };
    const handle = { wrap, panel, close };
    overlays.push(handle);
    if (dismiss) wrap.querySelector('.scrim')?.addEventListener('click', () => close());
    requestAnimationFrame(() => requestAnimationFrame(() => wrap.querySelectorAll('.scrim, .dialog, .sheet').forEach((n) => n.classList.add('in'))));
    return handle;
  }
  function closeOverlays(instant) { [...overlays].reverse().forEach((o) => o.close(instant)); }

  /**
   * A dialog. An action's `run` gets the panel before the dialog closes and
   * may return false to keep it open (a typed word that does not match yet).
   */
  function dialog({ title, text, body = '', actions = [], onClose, onMount, cls = '' }) {
    const btns = actions.map((a, i) => `<button class="btn ${a.kind || 'secondary'}" data-i="${i}">${a.label}</button>`).join('');
    const h = mountOverlay(`<div class="dialog ${cls}" role="alertdialog" aria-modal="true"><h2>${title}</h2>${text ? `<p>${text}</p>` : ''}${body}<div class="dl-actions">${btns}</div></div>`, { onClose });
    $$('.btn', h.panel).forEach((b) => b.addEventListener('click', () => {
      const a = actions[+b.dataset.i];
      if (a.run) { const r = a.run(h.panel); if (r === false) return; }
      h.close();
    }));
    onMount && onMount(h.panel);
    return h;
  }

  function sheet({ title, text, items, body, onClose }) {
    const head = title || text ? `<div class="sh-head">${title ? `<h2>${title}</h2>` : ''}${text ? `<p>${text}</p>` : ''}</div>` : '';
    const rows = items ? items.map((it, i) => `<button class="menu-row ${it.danger ? 'danger' : ''} ${it.on ? 'on' : ''}" data-i="${i}">${UI.icon(it.icon)}<span style="flex:1">${it.label}${it.sub ? `<span class="mr-sub">${it.sub}</span>` : ''}</span>${it.on ? UI.icon('check', 'bold') : ''}</button>`).join('') : '';
    const h = mountOverlay(`<div class="sheet" role="dialog" aria-modal="true">${head}<div class="sh-body">${body || rows}</div></div>`, { onClose });
    if (items) $$('.menu-row', h.panel).forEach((b) => b.addEventListener('click', () => {
      const it = items[+b.dataset.i]; h.close(); it.run && setTimeout(() => it.run(), 60);
    }));
    return h;
  }

  let snackTimer;
  function snack(text, action, { tone = '', stay = false } = {}) {
    const s = $('#snackbar');
    s.classList.toggle('error', tone === 'error');
    s.setAttribute('role', tone === 'error' ? 'alert' : 'status');
    s.innerHTML = `${tone === 'error' ? UI.icon('warning-circle', 'fill') : ''}<span>${text}</span>${action ? `<button class="sn-action" style="border:0;background:none">${action.label}</button>` : ''}`;
    if (action) s.querySelector('.sn-action').addEventListener('click', () => { s.classList.remove('in'); action.run && action.run(); });
    s.style.pointerEvents = action ? 'auto' : 'none';
    s.classList.add('in');
    clearTimeout(snackTimer);
    if (!stay) snackTimer = setTimeout(() => s.classList.remove('in'), tone === 'error' ? 5000 : 3000);
  }

  // ------------------------------------------------------------- the index
  function buildIndex() {
    const list = $('#vList');
    const q = ($('#vFilter').value || '').trim().toLowerCase();
    const groups = [];
    entries.forEach((e) => {
      if (q && !`${e.group} ${e.label}`.toLowerCase().includes(q)) return;
      let g = groups.find((x) => x.name === e.group);
      if (!g) groups.push(g = { name: e.group, order: e.order, items: [] });
      g.items.push(e);
    });
    groups.sort((a, b) => a.order - b.order);
    list.innerHTML = groups.map((g) => `<div class="v-group">${UI.esc(g.name)}</div>` + g.items.map((e) =>
      `<button class="v-item ${e.key === currentKey ? 'active' : ''}" data-key="${e.key}">${UI.esc(e.label)}</button>`).join('')).join('');
    $$('.v-item', list).forEach((b) => b.addEventListener('click', () => open(b.dataset.key)));
  }

  // ---------------------------------------------------------------- device
  function fitPhone() {
    const holder = $('#phoneHolder'); const phone = $('#phone');
    if (window.innerWidth <= 520) { holder.style.height = ''; holder.style.width = ''; phone.style.transform = ''; return; }
    const { w: W, h: H } = isWide() ? DEVICES[device] : { w: 412, h: 866 };
    const bare = document.body.classList.contains('bare');
    const w = holder.clientWidth;
    const h = holder.parentElement.clientHeight - (bare ? 0 : $('.v-stage-top').offsetHeight + 24);
    const s = Math.min(1, w / W, h / H);
    phone.style.transform = `scale(${s})`;
    holder.style.height = `${H * s}px`;
    holder.style.flex = 'none';
  }

  const DEVICE_KEY = 'helix-admin-device';
  function setDevice(d, { save = true, reopen = true } = {}) {
    if (!DEVICES[d]) d = 'phone';
    closeOverlays(true);
    stack.forEach((e) => e.el.remove());
    stack = [];
    $('#stack').innerHTML = '';
    device = d;
    const phone = $('#phone'); const scr = $('#phoneScreen');
    phone.classList.toggle('window', isWide());
    scr.classList.toggle('win', isWide());
    phone.style.width = isWide() ? `${DEVICES[d].w}px` : '';
    phone.style.height = isWide() ? `${DEVICES[d].h}px` : '';
    $$('#vDevice [data-device]').forEach((b) => b.classList.toggle('on', b.dataset.device === d));
    if (save) { try { localStorage.setItem(DEVICE_KEY, d); } catch (_) {} }
    fitPhone();
    if (reopen) open(currentKey || 'overview', { remember: false });
  }

  // --------------------------------------------------------------- manifest
  function manifest() {
    const items = (list) => list.map(([gesture, on, does, only]) => ({ gesture, on, does, ...(only ? { only } : {}) }));
    return {
      devices: DEVICES,
      interactions: { global: items(GLOBAL_INTERACTIONS), components: items(KIT_INTERACTIONS) },
      screenDefs: Object.fromEntries([...screens.values()].map((d) => [d.id, {
        title: d.title, group: d.group, nav: d.nav, crumb: typeof d.crumb === 'function' ? null : d.crumb,
        interactions: d.interactions === undefined ? null : items(d.interactions),
      }])),
      screens: entries.map((e) => ({
        key: e.key, group: e.group, label: e.label, screen: e.screen, params: e.params,
        base: [e.base].flat(Infinity).filter(Boolean).map((b) => ({ screen: b.screen, params: b.params || {} })),
      })),
    };
  }

  // ------------------------------------------------------------------- boot
  function boot() {
    let q = null;
    try { q = new URLSearchParams(location.search); } catch (_) {}
    if (q && q.has('bare')) document.body.classList.add('bare');
    if (q && q.has('manifest')) {
      const pre = document.createElement('pre'); pre.id = 'manifest';
      pre.textContent = JSON.stringify(manifest());
      document.body.replaceChildren(pre);
      return;
    }
    let dev = null;
    try { dev = q.get('device') || localStorage.getItem(DEVICE_KEY); } catch (_) {}
    setDevice(dev || 'phone', { save: false, reopen: false });
    const fit = () => { if (isWide() && window.innerWidth > 0 && window.innerWidth <= 520) setDevice('phone', { save: false }); else fitPhone(); };
    window.addEventListener('resize', fit);
    $$('#vDevice [data-device]').forEach((b) => b.addEventListener('click', () => setDevice(b.dataset.device)));
    $('#vFilter').addEventListener('input', buildIndex);
    $('#vIndexToggle').addEventListener('click', () => $('#viewer').classList.toggle('index-open'));
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') { if (overlayOpen()) closeOverlays(); else pop(); }
    });
    window.addEventListener('hashchange', () => {
      let k = null; try { k = decodeURIComponent(location.hash.slice(1)); } catch (_) {}
      if (k && k !== currentKey && entries.some((x) => x.key === k)) open(k, { remember: false });
    });
    let key = null;
    try { key = decodeURIComponent(location.hash.slice(1)) || null; } catch (_) {}
    if (!entries.some((e) => e.key === key)) key = 'overview';
    currentKey = key;
    buildIndex();
    open(key);
  }

  return {
    register, push, pop, reset, replace, open, dialog, sheet, snack, closeOverlays, overlayOpen,
    top, boot, $, $$, screens, isWide, invitesOn, device: () => device, setDevice, entries, manifest,
    PLACE,
  };
})();
