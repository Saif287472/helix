/* The shell's own wiring: the places, the status strip, the theme and the
   operator menu. Direction A keeps the strip in sync with whatever page is on
   top, so the operator always knows which node they are looking at and when
   the numbers were last read. */
const Shell = (() => {
  const NAV = { overview: 'overview', users: 'users', invites: 'invites', ops: 'ops_reports' };
  const THEME_KEY = 'helix.console.theme';

  function themes() {
    return { orbit: 'Orbit', night: 'Orbit Night' };
  }

  function theme() {
    const q = new URLSearchParams(location.search).get('theme');
    if (q && themes()[q]) return q;
    try { return localStorage.getItem(THEME_KEY) || 'orbit'; } catch (_) { return 'orbit'; }
  }

  function setTheme(id) {
    if (!themes()[id]) return;
    try { localStorage.setItem(THEME_KEY, id); } catch (_) {}
    document.documentElement.dataset.theme = id;
    document.querySelectorAll('[data-theme-set]').forEach((b) => {
      b.classList.toggle('on', b.dataset.themeSet === id);
    });
  }

  /* The prototype's story is fixed to one morning (22 Oct 2026, 11:42), so the
     strip stamps the read time in that story and moves it forward by the real
     seconds since the page opened. */
  const STORY = new Date('2026-10-22T11:42:08');
  const opened = Date.now();
  function clock(d) {
    return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}:${String(d.getSeconds()).padStart(2, '0')}`;
  }

  function stamp() {
    const el = document.getElementById('stripStamp');
    if (!el) return;
    const at = new Date(STORY.getTime() + (Date.now() - opened));
    el.textContent = `checked ${clock(at)} · ${DATA.server.latencyMs} ms`;
    el.title = `Last read ${at.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}, ${clock(at)}`;
    const m = document.getElementById('mStamp');
    if (m) m.textContent = clock(at);
  }

  /* The strip and the phone's status line follow the page on top. */
  function syncStrip() {
    const t = App.top();
    const def = t && App.screens.get(t.id);
    if (!def) return;
    const srv = DATA.server;
    const set = (id, text) => { const n = document.getElementById(id); if (n) n.textContent = text; };
    set('stripTitle', def.strip || def.title);
    set('stripWhere', def.stripSub || '');
    set('stripNode', srv.nodeId);
    set('mNode', srv.nodeId);
    const maint = document.getElementById('stripMaint');
    if (maint) maint.hidden = !(DATA.config.maintenance || (t.params && t.params.state === 'maintenance'));
    const st = (t.params && t.params.state) || '';
    const ready = st === 'offline' ? 'bad' : st === 'degraded' ? 'warn' : st === 'denied' ? 'idle' : (def.ready || 'ok');
    const word = { bad: 'Unreachable', warn: 'Not ready', idle: 'Signed out' }[ready] || 'Ready';
    const paint = (dotId, wordId) => {
      const dot = document.getElementById(dotId);
      if (dot) { dot.className = `tb-dot ${ready}`; dot.title = word; }
      const w = document.getElementById(wordId);
      if (w) { w.textContent = word; w.className = ready === 'ok' ? 'sstate' : `sstate ${ready}`; }
    };
    paint('mDot', 'mState');
    paint('tbDot', 'tbState');
    stamp();
  }

  function goPlace(place) {
    if (place === 'invites' && !App.invitesOn()) return;
    const screen = NAV[place];
    if (screen) App.reset(screen);
  }

  function menu() {
    App.sheet({
      title: 'Operator',
      text: `Signed in as the only admin on ${DATA.server.name}. This session ends ${DATA.config.signedInUntil}.`,
      items: [
        { icon: 'sliders-horizontal', label: 'Settings', sub: 'Server name, flags, password', run: () => App.reset('ops_config') },
        { icon: 'moon-stars', label: 'Orbit Night', sub: 'The same tokens, dark', on: theme() === 'night', run: () => setTheme(theme() === 'night' ? 'orbit' : 'night') },
        { icon: 'lock-simple', label: 'Lock the console', sub: 'Needs the device PIN', run: () => App.reset('lock') },
        { icon: 'sign-out', label: 'Sign out', sub: 'Ends every admin session', danger: true, run: signOut },
      ],
    });
  }

  function signOut() {
    Kit.confirm(
      'Sign out of this server?',
      'Every admin token stops working, on this device and any other. Nothing on the server changes, and the next sign-in needs the admin password again.',
      'Sign out',
      () => App.reset('signin'),
    );
  }

  function init() {
    setTheme(theme());
    document.addEventListener('click', (e) => {
      const th = e.target.closest('[data-theme-set]');
      if (th) { setTheme(th.dataset.themeSet); return; }
      const nav = e.target.closest('[data-nav]');
      if (nav) { goPlace(nav.dataset.nav); return; }
      if (e.target.closest('#meBtn')) { menu(); return; }
      if (e.target.closest('#stripRefresh')) {
        const t = App.top();
        if (t && t.rerender) t.rerender();
        stamp();
        App.snack('Reloaded from the node.');
        return;
      }
      if (e.target.closest('[data-signout]')) signOut();
      if (e.target.closest('[data-locknow]')) App.reset('lock');
    });
    syncStrip();
  }

  return { init, goPlace, syncStrip, theme, setMenu: menu };
})();

document.addEventListener('DOMContentLoaded', () => Shell.init());
