/*
  The console kit: fields, dialogs, the state kit (skeleton, loading, failed,
  empty) and the common wiring. Flutter: ConsoleField, ConsoleDialog,
  ConsoleSkeleton, ConsoleLoadFailed, ConsoleEmptyState, ConsoleCodeOnce.
*/
const Kit = (() => {
  const { esc, icon } = UI;

  function field(f) {
    const suffix = (f.eye ? UI.ibtn('eye', 'Show password', 'data-eye', 'sm') : '') + (f.suffix || '');
    const tag = f.multiline
      ? `<textarea id="${f.id || ''}" rows="${f.rows || 3}" placeholder="${esc(f.hint || '')}">${esc(f.value || '')}</textarea>`
      : `<input id="${f.id || ''}" type="${f.type || 'text'}" value="${esc(f.value || '')}" placeholder="${esc(f.hint || '')}" autocomplete="off" ${f.disabled ? 'disabled' : ''}>`;
    return `<label class="fld ${f.error ? 'has-error' : ''}" ${f.cls ? `data-field="${esc(f.cls)}"` : ''}>
      ${f.label ? `<span class="fld-label">${esc(f.label)}</span>` : ''}
      <span class="fld-box">${f.prefix ? `<span class="fld-prefix">${esc(f.prefix)}</span>` : ''}${tag}${suffix}</span>
      <span class="fld-err" ${f.error ? '' : 'hidden'}>${icon('warning-circle', 'fill')}<span>${esc(f.error || '')}</span></span>
    </label>`;
  }

  const skeletonRows = (n = 6) => UI.skeletonRows(n);
  const loading = (label = 'Loading…') => `<div class="page-loading" role="status"><i class="ph ph-spinner-gap" style="animation:spin 0.9s linear infinite" aria-hidden="true"></i><span>${esc(label)}</span></div>`;
  const empty = (opts) => UI.empty(opts);

  function loadFailed(title = 'This could not be loaded.', sub = 'Check that the server is reachable, then try again.') {
    return `<div class="pcard"><div class="load-failed" role="alert">
      <span class="lf-ico">${icon('cloud-slash')}</span>
      <div class="lf-text"><div class="lf-title">${esc(title)}</div><div class="lf-sub">${esc(sub)}</div></div>
      <button class="btn secondary" data-retry>${icon('arrows-clockwise')}Try again</button>
    </div></div>`;
  }

  /* ---- The three failures an operator actually meets, each named for its
     cause: the node is not there, the session is not allowed, the data is
     empty. They look alike on purpose - only the words and the button differ. */
  function offline(opts = {}) {
    return `<div class="cr-panel cr-state"><div class="load-failed" role="alert">
      <span class="lf-ico">${icon('wifi-slash')}</span>
      <div class="lf-text">
        <div class="lf-title">${esc(opts.title || 'The node is not answering.')}</div>
        <div class="lf-sub">${esc(opts.text || 'The console could not reach it just now. Everything on this page is the last read, not the present.')}</div>
        <div class="lf-meta">${esc(opts.node || DATA.server.nodeId)} · ${esc(opts.address || DATA.server.address)} · last read ${esc(opts.at || '11:41:58')}</div>
      </div>
      <button class="btn secondary" data-retry>${icon('arrows-clockwise')}${esc(opts.action || 'Try again')}</button>
    </div></div>`;
  }

  function noPermission(opts = {}) {
    return `<div class="cr-panel cr-state"><div class="load-failed denied" role="alert">
      <span class="lf-ico">${icon('shield-check')}</span>
      <div class="lf-text">
        <div class="lf-title">${esc(opts.title || 'This session has ended.')}</div>
        <div class="lf-sub">${esc(opts.text || 'Someone signed out or changed the admin password, which stops every admin token. Nothing you did here was saved.')}</div>
      </div>
      <button class="btn secondary" data-signin>${icon('key')}Sign in again</button>
    </div></div>`;
  }

  const skeletonTable = (rows = 8, cols = 5) => `<div class="sk-table" role="status" aria-label="Loading">` +
    Array.from({ length: rows }, () =>
      `<div class="sk-row">${Array.from({ length: cols }, (_, c) =>
        `<span class="sk" style="width:${[120, 74, 96, 60, 88][c % 5]}px"></span>`).join('')}</div>`).join('') +
    `</div>`;

  /* Relative time, with the exact value one hover away. */
  const NOW = new Date('2026-10-22T11:42:00');
  function rel(iso, short) {
    const then = new Date(iso.replace(' ', 'T'));
    const s = Math.round((NOW - then) / 1000);
    if (Number.isNaN(s)) return iso;
    const abs = `${String(then.getHours()).padStart(2, '0')}:${String(then.getMinutes()).padStart(2, '0')}`;
    if (short) {
      if (s < 60) return 'now';
      if (s < 3600) return `${Math.round(s / 60)}m`;
      if (s < 86400) return `${Math.round(s / 3600)}h`;
      return `${Math.round(s / 86400)}d`;
    }
    if (s < 45) return 'just now';
    if (s < 3600) return `${Math.round(s / 60)} min ago`;
    if (s < 86400) return `${Math.round(s / 3600)} h ago`;
    const d = Math.round(s / 86400);
    if (d < 31) return `${d} d ago`;
    return then.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) + ` · ${abs}`;
  }
  const time = (iso, { cls = '', short = false } = {}) =>
    `<time class="t-rel ${cls}" datetime="${esc(iso)}" title="${esc(iso)}">${esc(rel(iso, short))}</time>`;

  function confirm(title, text, label, run, kind = 'danger') {
    App.dialog({
      title, text,
      actions: [{ label: 'Cancel' }, { label, kind: kind === 'danger' ? 'danger-solid' : 'primary', run }],
    });
  }

  async function copy(text, what = 'Copied to the clipboard') {
    try { await navigator.clipboard.writeText(text); App.snack(`${what} · ${text}`); return; }
    catch (_) {}
    try {
      const ta = document.createElement('textarea');
      ta.value = text; ta.style.cssText = 'position:fixed;opacity:0';
      document.body.appendChild(ta); ta.select(); document.execCommand('copy'); ta.remove();
      App.snack(`${what} · ${text}`);
    } catch (_) {
      App.snack('Could not use the clipboard', null, { tone: 'error' });
    }
  }

  // ------------------------------------------------------------- typed flow
  function typed({ title, text, word, label, kind = 'danger-solid', body = '', run }) {
    const id = `typed-${word.toLowerCase()}`;
    App.dialog({
      title, text,
      body: `${body}${field({ id, label: `Type ${word} to confirm`, hint: word })}`,
      actions: [{ label: 'Cancel' }, {
        label, kind,
        run: (panel) => {
          const input = panel.querySelector(`#${id}`);
          if (!input || input.value.trim().toUpperCase() !== word) { input?.focus(); return false; }
          run && run();
        },
      }],
      onMount: (panel) => {
        const input = panel.querySelector(`#${id}`);
        const act = panel.querySelector('.dl-actions .btn:last-child');
        if (!input || !act) return;
        act.disabled = true;
        input.addEventListener('input', () => { act.disabled = input.value.trim().toUpperCase() !== word; });
        input.focus();
      },
    });
  }

  function reason({ title, text, label = 'Suspend account', placeholder = 'What happened? This is written to the audit trail.', kind = 'danger-solid', run }) {
    App.dialog({
      title, text,
      body: field({ id: 'reasonInput', label: 'Reason', hint: placeholder, multiline: true, rows: 3 }),
      actions: [{ label: 'Cancel' }, {
        label, kind,
        run: (panel) => {
          const input = panel.querySelector('#reasonInput');
          if (!input || input.value.trim().length < 3) {
            const err = panel.querySelector('.fld-err');
            if (err) { err.hidden = false; err.querySelector('span').textContent = 'Give a short reason first.'; }
            input?.focus();
            return false;
          }
          run && run(input.value.trim());
        },
      }],
      onMount: (panel) => panel.querySelector('#reasonInput')?.focus(),
    });
  }

  function rename(current, run) {
    App.dialog({
      title: 'Rename this server',
      text: 'The name shows in the console bar and in the app’s server list. People already signed in see it after their next refresh.',
      body: field({ id: 'serverNameInput', label: 'Server name', value: current, hint: 'Helix Global' }),
      actions: [{ label: 'Cancel' }, {
        label: 'Save name', kind: 'primary',
        run: (panel) => {
          const v = panel.querySelector('#serverNameInput')?.value.trim() || '';
          if (!v) { panel.querySelector('#serverNameInput')?.focus(); return false; }
          run(v);
        },
      }],
      onMount: (panel) => { const i = panel.querySelector('#serverNameInput'); i?.focus(); i?.select(); },
    });
  }

  function changePassword(run) {
    App.dialog({
      title: 'Change the admin password',
      text: 'Every other admin session is signed out. The password never leaves this device; only its derived key is sent.',
      body: field({ id: 'pwCurrent', label: 'Current password', type: 'password', eye: true }) +
        field({ id: 'pwNext', label: 'New password', type: 'password', eye: true, helper: 'At least 12 characters.' }) +
        field({ id: 'pwAgain', label: 'Repeat the new password', type: 'password', eye: true }),
      actions: [{ label: 'Cancel' }, {
        label: 'Change password', kind: 'primary',
        run: (panel) => {
          const cur = panel.querySelector('#pwCurrent')?.value || '';
          const next = panel.querySelector('#pwNext')?.value || '';
          const again = panel.querySelector('#pwAgain')?.value || '';
          if (!cur) { panel.querySelector('#pwCurrent')?.focus(); return false; }
          if (next.length < 12) { panel.querySelector('#pwNext')?.focus(); return false; }
          if (next !== again) { panel.querySelector('#pwAgain')?.focus(); return false; }
          run && run();
        },
      }],
      onMount: (panel) => panel.querySelector('#pwCurrent')?.focus(),
    });
  }

  function codeOnce({ code, title = 'Invite created', text = 'Give this code to one person. It works once and is shown only now — the server keeps a hash, not the code.', run }) {
    App.dialog({
      title,
      text,
      cls: 'code-dialog',
      body: `<div class="code-box"><code id="inviteCode">${esc(code)}</code>${UI.copyBtn(code, 'Copy code')}</div>
        <div class="code-note">${icon('eye-slash')} After this closes you can still see the ${title === 'Invite created' ? 'invite' : 'code record'}, but not the code.</div>`,
      actions: [{ label: 'Done', kind: 'primary', run }],
    });
  }

  function createInvite(run) {
    App.dialog({
      title: 'Create an invite',
      text: 'An invite lets one person create an account on this server. It expires after seven days and can be cancelled before it is used.',
      actions: [{ label: 'Cancel' }, {
        label: 'Create invite', kind: 'primary',
        run: () => run && run('HX-7F2K-QP9D'),
      }],
    });
  }

  // ---------------------------------------------------------------- wiring
  function wire(el, entry) {
    el.querySelectorAll('[data-back]').forEach((b) => b.addEventListener('click', (e) => { e.preventDefault(); App.pop(); }));
    el.querySelectorAll('[data-go]').forEach((b) => b.addEventListener('click', (e) => {
      if (e.target.closest('[data-nested]')) return;
      let params = {};
      try { params = b.dataset.params ? JSON.parse(b.dataset.params) : {}; } catch (_) {}
      App.push(b.dataset.go, params);
    }));
    el.querySelectorAll('[data-opstab]').forEach((b) => b.addEventListener('click', () => {
      const map = { reports: 'ops_reports', audit: 'ops_audit', logs: 'ops_logs', config: 'ops_config' };
      if (map[b.dataset.opstab]) App.reset(map[b.dataset.opstab]);
    }));
    el.querySelectorAll('[data-snack]').forEach((b) => b.addEventListener('click', () => App.snack(b.dataset.snack)));
    el.querySelectorAll('[data-copy]').forEach((b) => b.addEventListener('click', (e) => {
      e.stopPropagation();
      copy(b.dataset.copy, b.dataset.copyLabel || 'Copied to the clipboard');
    }));
    el.querySelectorAll('[data-retry]').forEach((b) => b.addEventListener('click', () => {
      if (!entry) return;
      const p = { ...entry.params }; delete p.state;
      App.replace(entry.id, p);
    }));
    el.querySelectorAll('[data-eye]').forEach((b) => b.addEventListener('click', (e) => {
      e.preventDefault();
      const inp = b.closest('.fld-box')?.querySelector('input'); if (!inp) return;
      const show = inp.type === 'password';
      inp.type = show ? 'text' : 'password';
      b.innerHTML = icon(show ? 'eye-slash' : 'eye');
      b.title = show ? 'Hide password' : 'Show password';
    }));
    el.querySelectorAll('[data-switch]').forEach((r) => {
      const hit = (e) => {
        if (e.target.closest('button, a, input, textarea, .switch')) return;
        e.preventDefault();
        r.click();
      };
      r.addEventListener('click', (e) => {
        if (e.target.closest('button, a') && !e.target.closest('[data-switch]')) return;
        const s = r.querySelector('.switch'); if (!s) return;
        const on = !s.classList.contains('on');
        s.classList.toggle('on', on); s.setAttribute('aria-checked', String(on));
        r.dispatchEvent(new CustomEvent('toggle', { detail: on }));
      });
      r.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') hit(e); });
      if (!r.hasAttribute('tabindex')) r.setAttribute('tabindex', '0');
    });
    el.querySelectorAll('[data-choose]').forEach((b) => b.addEventListener('click', () => {
      const [title, ...opts] = b.dataset.choose.split('|');
      const v = b.querySelector('.rw-value') || b.querySelector('.v');
      App.sheet({ title, items: opts.map((o) => ({ icon: o === (v && v.textContent) ? 'radio-button' : 'circle', label: o, on: o === (v && v.textContent), run: () => { if (v) v.textContent = o; } })) });
    }));
  }

  return { field, skeletonRows, skeletonTable, loading, loadFailed, offline, noPermission, empty, confirm, copy, typed, reason, rename, changePassword, codeOnce, createInvite, rel, time, wire };
})();
