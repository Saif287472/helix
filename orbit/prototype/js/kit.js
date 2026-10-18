/*
  Page kit for the settings-style and form screens (pass 2). Flutter:
  HelixTextField, HelixSegmented, InlineNotice, PageIntro, HelixQrDisplay,
  KeyCodeDisplay, HelixSettingsSection, BusyFilledButton.
*/
const Kit = (() => {
  const { esc, icon, ibtn } = UI;

  /** Text field: { id, label, value, hint, helper, error, prefix, type, mono, max, counter, eye, paste, big } */
  function field(f) {
    const type = f.type || 'text';
    const counter = f.counter ? `<span class="fld-count">${(f.value || '').length}/${f.max}</span>` : '';
    const suffix = (f.eye ? ibtn('eye', 'Show password', 'data-eye', 'sm') : '') + (f.paste ? ibtn('clipboard-text', 'Paste', 'data-paste', 'sm') : '') + (f.suffix || '');
    const tag = f.multiline ? `<textarea id="${f.id || ''}" rows="${f.rows || 3}" placeholder="${esc(f.hint || '')}" ${f.max ? `maxlength="${f.max}"` : ''}>${esc(f.value || '')}</textarea>`
      : `<input id="${f.id || ''}" type="${type}" value="${esc(f.value || '')}" placeholder="${esc(f.hint || '')}" ${f.max ? `maxlength="${f.max}"` : ''} ${f.inputmode ? `inputmode="${f.inputmode}"` : ''} autocomplete="off" ${f.disabled ? 'disabled' : ''}>`;
    return `<label class="fld ${f.error ? 'has-error' : ''} ${f.mono ? 'mono-in' : ''} ${f.big ? 'big' : ''}">
      ${f.label ? `<span class="fld-label">${esc(f.label)}</span>` : ''}
      <span class="fld-box">${f.prefix ? `<span class="fld-prefix">${esc(f.prefix)}</span>` : ''}${tag}${suffix}</span>
      ${f.error ? `<span class="fld-err">${icon('warning-circle', 'fill')}${esc(f.error)}</span>` : f.helper ? `<span class="fld-help">${f.helper}</span>` : ''}${counter}
    </label>`;
  }

  /** Segmented control: options [[value, label, icon?]] */
  function seg(options, active, attr = 'data-seg') {
    return `<div class="seg" role="tablist">${options.map(([v, l, ic]) => `<button role="tab" aria-selected="${v === active}" class="${v === active ? 'on' : ''}" ${attr}="${esc(v)}">${ic ? icon(ic) : ''}${esc(l)}</button>`).join('')}</div>`;
  }

  /** Inline notice: kind info | success | error | warning */
  function notice(kind, text, action) {
    const ic = { info: 'info', success: 'check-circle', error: 'warning-circle', warning: 'warning' }[kind];
    return `<div class="inotice ${kind}">${icon(ic, 'fill')}<div class="in-body">${text}${action ? `<div style="margin-top:8px"><button class="btn ${kind === 'error' ? 'danger' : 'secondary'}" style="height:36px;padding:0 14px;font-size:13px" ${action.attr || ''}>${esc(action.label)}</button></div>` : ''}</div></div>`;
  }

  function intro(title, text) {
    return `<div class="pintro">${title ? `<h2>${title}</h2>` : ''}${text ? `<p>${text}</p>` : ''}</div>`;
  }

  /** A deterministic QR-looking matrix (the app draws the real one). */
  function qr(seed = 'helix', size = 200) {
    const n = 29; let h = 2166136261;
    for (const ch of seed) h = Math.imul(h ^ ch.charCodeAt(0), 16777619) >>> 0;
    const rnd = () => { h ^= h << 13; h >>>= 0; h ^= h >> 17; h ^= h << 5; h >>>= 0; return h / 4294967296; };
    const finder = (x, y) => [[0, 0], [n - 7, 0], [0, n - 7]].some(([fx, fy]) => x >= fx && x < fx + 7 && y >= fy && y < fy + 7);
    const finderOn = (x, y) => { for (const [fx, fy] of [[0, 0], [n - 7, 0], [0, n - 7]]) { const dx = x - fx, dy = y - fy; if (dx >= 0 && dx < 7 && dy >= 0 && dy < 7) return dx === 0 || dx === 6 || dy === 0 || dy === 6 || (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4); } return false; };
    let rects = '';
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
      const on = finder(x, y) ? finderOn(x, y) : rnd() > 0.52;
      if (on) rects += `<rect x="${x}" y="${y}" width="1.02" height="1.02"/>`;
    }
    return `<svg class="qr" viewBox="-2 -2 ${n + 4} ${n + 4}" width="${size}" height="${size}" role="img" aria-label="QR code"><rect x="-2" y="-2" width="${n + 4}" height="${n + 4}" fill="#fff"/><g fill="#0E1220">${rects}</g></svg>`;
  }

  /** KeyCodeDisplay: label over a large monospaced code */
  function code(label, value, opts = {}) {
    // groups: wrap only between dash-separated groups, never inside one.
    const shown = opts.groups ? value.split('-').map((g, i, a) => `<span class="cb-grp">${esc(g)}${i < a.length - 1 ? '-' : ''}</span>`).join('') : esc(value);
    return `<div class="codebox ${opts.cls || ''}"><span class="eyebrow">${esc(label)}</span><span class="cb-code">${shown}</span>${opts.note ? `<span class="cb-note">${opts.note}</span>` : ''}</div>`;
  }

  function progress(p) {
    return p == null ? '<div class="prog indet"><b></b></div>' : `<div class="prog"><b style="width:${Math.round(p * 100)}%"></b></div>`;
  }

  function check(label, on, attr = '') {
    return `<button class="chk ${on ? 'on' : ''}" role="checkbox" aria-checked="${!!on}" ${attr}><span class="chk-box">${icon('check', 'bold')}</span><span class="chk-label">${label}</span></button>`;
  }

  /** Settings section: optional title, card of rows, optional footer. */
  function section(title, rows, footer) {
    return `${title ? `<div class="group-title eyebrow">${title}</div>` : '<div style="height:14px"></div>'}<div class="card">${rows.join('')}</div>${footer ? `<p class="sec-foot">${footer}</p>` : ''}`;
  }

  /** Switch row */
  function sw(title, sub, on, attr = '') {
    return UI.row({ title, sub, end: 'switch', on, attrs: `data-switch ${attr}` });
  }

  /** A choice row whose value opens a radio sheet: data-choose="Title|Opt1|Opt2" */
  function choice(r, title, options, current) {
    return UI.row({ title, ...r, value: esc(current), end: 'chevron', attrs: `data-choose="${esc([title, ...options].join('|'))}"` });
  }

  /** Generic settings-style page */
  function page({ title, sub, body, actions = '', back = true, cls = '' }) {
    return `${UI.appbar({ title, sub, back, actions })}<div class="scroll ${cls}" data-keep-scroll="page" style="padding-bottom:40px">${body}</div>`;
  }

  // ------------------------------------------------------------ You style
  // The parts every You-style page is built from (the You page, its topics and
  // the pages under them). Flutter: OrbitTopicPage, OrbitSummaryCard,
  // OrbitStatusRing, OrbitSection, OrbitDangerZone, OrbitStepPills, OrbitRules.

  /** A You-style page: the flat header on the page colour, then the body. */
  function youPage(title, body, { close = false, back = true, keep = 'topic' } = {}) {
    const lead = !back ? '<span style="width:8px"></span>' : close ? ibtn('x', 'Close', 'data-back') : ibtn('arrow-left', 'Back', 'data-back');
    return `<header class="appbar flat you-bar">${lead}<div class="ab-title"><h1>${title}</h1></div></header><div class="scroll" data-keep-scroll="${keep}" style="padding-bottom:36px">${body}</div>`;
  }

  /**
   * The summary card at the top of a You-style page.
   * { ic, title, sub, pills: [{ icon, text, tone }], slot, tone, art }
   * tone ok | warn | danger tints the icon; art replaces the icon (a ring, an avatar).
   */
  function hero({ ic, title, sub, pills = [], slot = '', tone = '', art = '' }) {
    const lead = art || `<span class="hc-ico">${icon(ic, 'fill')}</span>`;
    return `<div class="hero-card ${tone ? `tone-${tone}` : ''}"><div class="hc-top">${lead}<div class="hc-text"><div class="hc-title">${title}</div>${sub ? `<div class="hc-sub">${sub}</div>` : ''}</div></div>
      ${slot}${pills.length ? `<div class="hc-pills">${pills.map((p) => `<span class="hc-pill ${p.tone || ''}">${icon(p.icon, p.tone ? 'fill' : '')}${p.text}</span>`).join('')}</div>` : ''}</div>`;
  }

  /** Status ring: ok | bad | run (with p from 0 to 1) | idle (with an icon). */
  function ring(state, { p = 0, ic = 'cloud-arrow-down', label = '' } = {}) {
    // label replaces the percentage when progress is counted in steps, not bytes.
    if (state === 'run') return `<span class="b-ring run" style="--p:${p}"><span>${label || `${Math.round(p * 100)}%`}</span></span>`;
    if (state === 'bad') return `<span class="b-ring bad">${icon('warning', 'fill')}</span>`;
    if (state === 'ok') return `<span class="b-ring ok">${icon('check', 'bold')}</span>`;
    return `<span class="b-ring idle">${icon(ic)}</span>`;
  }

  /** The red-edged danger zone at the bottom of a page. */
  function danger(rows, footer) {
    return `<div class="group-title eyebrow dz-title">Danger zone</div><div class="card danger-zone">${rows.join('')}</div>${footer ? `<p class="sec-foot">${footer}</p>` : ''}`;
  }

  /** Where a flow is: [label] with the current index; earlier steps show a tick. */
  function steps(labels, current) {
    return `<div class="hc-pills step-pills" aria-label="Step ${current + 1} of ${labels.length}">${labels.map((l, i) => `<span class="hc-pill ${i < current ? 'ok' : i === current ? 'accent' : ''}">${i < current ? icon('check-circle', 'fill') : `<b class="sp-n">${i + 1}</b>`}${l}</span>`).join('')}</div>`;
  }

  /** Rules that tick as the person types: [{ ok, text }]. */
  function rules(list) {
    return `<div class="rules" aria-live="polite">${list.map((r) => `<span class="rule ${r.ok ? 'ok' : ''}">${icon(r.ok ? 'check-circle' : 'circle', r.ok ? 'fill' : '')}${r.text}</span>`).join('')}</div>`;
  }

  /** A card that holds fields rather than rows. */
  const formCard = (html) => `<div class="card form-card">${html}</div>`;

  // ------------------------------------------------------- the state kit
  // How every screen draws loading, failure, permission and refusal (Phase
  // 1b, 2026-10-18). The contracts point here instead of drawing each case
  // again. Flutter: OrbitSkeleton, OrbitLoading, OrbitLoadFailed,
  // OrbitPermissionCard, OrbitFieldLock; toasts are OrbitToast (App.snack).

  /** Placeholder rows while a list loads. kind: chat | person | row | tile. */
  function skeleton(n = 6, kind = 'chat', label = 'Loading') {
    const one = {
      chat: '<span class="sk sk-av"></span><span class="sk-lines"><span class="sk sk-l1"></span><span class="sk sk-l2"></span></span><span class="sk sk-meta"></span>',
      person: '<span class="sk sk-av"></span><span class="sk-lines"><span class="sk sk-l1"></span><span class="sk sk-l2 short"></span></span>',
      row: '<span class="sk sk-ico"></span><span class="sk-lines"><span class="sk sk-l1"></span></span>',
      tile: '<span class="sk sk-tile"></span><span class="sk sk-tile"></span>',
    }[kind];
    return `<div class="skel skel-${kind}" role="status" aria-label="${esc(label)}">${Array.from({ length: n }, () => `<div class="sk-row">${one}</div>`).join('')}</div>`;
  }

  /** A page that is opening: a spinner and what it is waiting for. */
  function loading(label = 'Loading…') {
    return `<div class="page-loading" role="status"><i class="ph ph-spinner-gap spin" aria-hidden="true"></i><span>${esc(label)}</span></div>`;
  }

  /** A page or list that could not load, with Try again. compact: inside a card or list. */
  function loadFailed(title = 'This could not be loaded.', { sub = 'Check your connection and try again.', retry = true, compact = false } = {}) {
    return `<div class="load-failed ${compact ? 'compact' : ''}" role="alert"><span class="lf-ico">${icon('cloud-slash')}</span>
      <div class="lf-text"><div class="lf-title">${esc(title)}</div>${sub ? `<div class="lf-sub">${esc(sub)}</div>` : ''}</div>
      ${retry ? `<button class="btn secondary" data-retry>${icon('arrows-clockwise')}Try again</button>` : ''}</div>`;
  }

  /** Asking for a system permission. kind: camera | microphone | contacts | notifications. */
  function permission(kind, { denied = false, dark = false, text = '' } = {}) {
    const [ic, name] = { camera: ['camera', 'camera'], microphone: ['microphone', 'microphone'], contacts: ['address-book', 'contacts'], notifications: ['bell-ringing', 'notifications'] }[kind];
    const title = denied ? `Orbit can’t use your ${name}` : `Allow your ${name}`;
    return `<div class="perm-card ${dark ? 'dark' : ''}"><span class="pc-ico">${icon(ic, 'fill')}</span><div class="pc-body"><div class="pc-title">${title}</div>${text ? `<div class="pc-text">${text}</div>` : ''}
      <button class="btn ${denied ? 'secondary' : 'primary'}" data-perm="${denied ? 'settings' : 'ask'}">${denied ? 'Open settings' : 'Allow'}</button></div></div>`;
  }

  /** Under a field: locked for a while after too many tries. */
  function fieldLock(text) {
    return `<span class="fld-lock" role="alert">${icon('hourglass-medium', 'fill')}${esc(text)}</span>`;
  }

  /** Wire the common behaviour of kit pages. */
  function wire(el, entry) {
    el.querySelectorAll('[data-back]').forEach((b) => b.addEventListener('click', App.pop));
    el.querySelectorAll('[data-go]').forEach((b) => b.addEventListener('click', (e) => {
      e.stopPropagation();
      let params = {};
      try { params = b.dataset.params ? JSON.parse(b.dataset.params) : {}; } catch (_) {}
      App.push(b.dataset.go, params);
    }));
    el.querySelectorAll('[data-snack]').forEach((b) => b.addEventListener('click', () => App.snack(b.dataset.snack)));
    // State kit: Try again reopens the screen in its normal state; a
    // permission button hands over to the system.
    el.querySelectorAll('[data-retry]').forEach((b) => b.addEventListener('click', () => {
      if (!entry) return;
      const p = { ...entry.params }; delete p.state;
      App.replace(entry.id, p);
    }));
    el.querySelectorAll('[data-perm]').forEach((b) => b.addEventListener('click', () => App.snack(b.dataset.perm === 'settings' ? 'Opens the system settings for Orbit' : 'Opens the system permission prompt')));
    el.querySelectorAll('[data-switch]').forEach((r) => r.addEventListener('click', () => {
      const s = r.querySelector('.switch'); const on = !s.classList.contains('on');
      s.classList.toggle('on', on); s.setAttribute('aria-checked', String(on));
      r.dispatchEvent(new CustomEvent('toggle', { detail: on }));
    }));
    el.querySelectorAll('[data-choose]').forEach((r) => r.addEventListener('click', () => {
      const [title, ...opts] = r.dataset.choose.split('|');
      const v = r.querySelector('.rw-value');
      App.sheet({ title, items: opts.map((o) => ({ icon: o === v.textContent ? 'radio-button' : 'circle', label: o, on: o === v.textContent, run: () => { v.textContent = o; r.dispatchEvent(new CustomEvent('chosen', { detail: o })); } })) });
    }));
    el.querySelectorAll('[data-eye]').forEach((b) => b.addEventListener('click', (e) => {
      e.preventDefault();
      const inp = b.closest('.fld-box').querySelector('input');
      const show = inp.type === 'password'; inp.type = show ? 'text' : 'password';
      b.innerHTML = icon(show ? 'eye-slash' : 'eye'); b.title = show ? 'Hide password' : 'Show password'; b.setAttribute('aria-label', b.title);
    }));
    el.querySelectorAll('.chk').forEach((c) => c.addEventListener('click', (e) => {
      e.preventDefault(); const on = !c.classList.contains('on');
      c.classList.toggle('on', on); c.setAttribute('aria-checked', String(on));
      c.dispatchEvent(new CustomEvent('toggle', { detail: on }));
    }));
    el.querySelectorAll('.seg').forEach((s) => s.addEventListener('click', (e) => {
      const b = e.target.closest('button'); if (!b) return;
      s.querySelectorAll('button').forEach((x) => { x.classList.toggle('on', x === b); x.setAttribute('aria-selected', String(x === b)); });
    }));
    el.querySelectorAll('.fld-count').forEach((cnt) => {
      const inp = cnt.closest('.fld').querySelector('input, textarea'); const max = inp.maxLength;
      inp.addEventListener('input', () => { cnt.textContent = `${inp.value.length}/${max}`; });
    });
  }

  /** Destructive confirm in one call */
  function confirm(title, text, label, run, kind = 'danger') {
    App.dialog({ title, text, actions: [{ label: 'Cancel' }, { label, kind, run }] });
  }

  /** Text input dialog (rename etc.) */
  function inputDialog({ title, label, value = '', max = 60, confirmLabel = 'Save', run }) {
    const h = App.overlay(`<div class="dialog" role="dialog" aria-modal="true"><h2>${esc(title)}</h2>${field({ id: 'dlgIn', label, value, max })}<div class="dl-actions"><button class="btn ghost" data-x>Cancel</button><button class="btn primary" data-ok>${esc(confirmLabel)}</button></div></div>`);
    const inp = h.panel.querySelector('#dlgIn'); setTimeout(() => inp.focus(), 60);
    h.panel.querySelector('[data-x]').addEventListener('click', () => h.close());
    h.panel.querySelector('[data-ok]').addEventListener('click', () => { h.close(); run && run(inp.value); });
  }

  // What the kit's parts do wherever they appear ([gesture, on, does]).
  // Exported to screens.json, so each screen lists only its own behaviour.
  const INTERACTIONS = [
    ['tap', 'Row with a chevron, or a tile', 'Opens its page.'],
    ['tap', 'Switch row', 'Toggles the switch; the whole row is the target.'],
    ['tap', 'Choice row (value on the right)', 'Opens a sheet of options; the current one is ticked; picking sets it.'],
    ['tap', 'Segmented control option', 'Selects it.'],
    ['tap', 'Checkbox row', 'Ticks or unticks it.'],
    ['tap', 'Eye in a password field', 'Shows or hides the password.'],
    ['tap', 'Paste in a field', 'Pastes from the clipboard.'],
    ['type', 'Field with a counter', 'The counter shows length out of the maximum.'],
    ['tap', 'Button that starts work', 'Shows a spinner in place of its label until the work ends.'],
    ['tap', 'Try again (could not be loaded)', 'Loads the page again; while loading it shows the skeleton or spinner.'],
    ['tap', 'Allow / Open settings (permission card)', 'Allow opens the system prompt; after a refusal, Open settings opens Orbit’s system settings.'],
    ['auto', 'Lists while loading', 'Placeholder rows the shape of the real ones, announced as loading; they shimmer unless reduce motion is on.'],
  ];

  return { field, seg, notice, intro, qr, code, progress, check, section, sw, choice, page, wire, confirm, inputDialog, youPage, hero, ring, danger, steps, rules, formCard, skeleton, loading, loadFailed, permission, fieldLock, INTERACTIONS };
})();
