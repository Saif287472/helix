/*
  The pages under You's topics, in the You style (2026-10-17): Change or set a
  password, Delete my account, Blocked, Help and about, Terms and Privacy
  Policy, Advanced. Each opens on a summary card (Kit.hero), then grouped
  cards, with live feedback where it helps (password rules that tick as you
  type). Flutter: features/settings/presentation/*. Copy from SCREENS.md.
*/
(() => {
  const { esc, icon, avatar, row } = UI;
  const { section, sw, field, notice, check, wire, progress, youPage, hero, ring, rules, formCard } = Kit;
  const base = [{ screen: 'home', params: { tab: 'chats' } }, { screen: 'settings-page', params: {} }];
  const deeper = (screen, params = {}) => [base, { screen, params }];
  const reg = (def) => App.register({ group: 'Settings', order: 60, ...def, entries: def.entries.map((e) => ({ base, ...e })) });

  // ---------------------------------------------------------------- password
  // The rules tick as you type; the password is checked on this device only.
  function pwRules(st, set) {
    const list = [{ ok: (st.pw1 || '').length >= 8, text: 'At least 8 characters' }];
    if (!set) list.push({ ok: !!st.pw1 && st.pw1 !== st.pw0, text: 'Not the same as your current one' });
    list.push({ ok: !!st.pw2 && st.pw1 === st.pw2, text: 'Both new passwords match' });
    return list;
  }
  reg({
    id: 'password', title: 'Change password',
    interactions: [
      ['auto', 'Linked device', 'Asks for your phone number once, above the current password.'],
      ['type', 'Password fields', 'The rules tick as you type; the button turns on when all of them pass.'],
      ['tap', 'Show passwords', 'Shows or hides all three fields.'],
      ['tap', 'Change password / Set password', 'Saves, then shows Password saved.'],
    ],
    entries: [
      { key: 'password', label: 'Change password', params: {}, base: deeper('account') },
      { key: 'password-set', label: 'Set a password', params: { set: true }, base: deeper('account', { noPassword: true }) },
      { key: 'password-error', label: 'Change password · mismatch', params: { error: true }, base: deeper('account') },
      { key: 'password-done', label: 'Change password · saved', params: { done: true }, base: deeper('account') },
      { key: 'password-linked', label: 'Change password · linked device (number needed)', params: { linked: true }, base: deeper('account') },
      { key: 'password-wrong', label: 'Change password · wrong current password, locked out', params: { wrong: true }, base: deeper('account') },
    ],
    render(params, entry) {
      const st = entry.state;
      if (!st.init) Object.assign(st, { init: true, done: params.done, show: false, pw0: params.error ? 'old-password' : '', pw1: params.error ? 'sunrise-42' : '', pw2: params.error ? 'sunrise-24' : '' });
      const title = params.set ? 'Set a password' : 'Change password';
      if (st.done) {
        return youPage(title, `${hero({ art: ring('ok'), title: 'Password saved', sub: 'Use it to sign in on a new phone' })}
          <div class="btn-row"><button class="btn primary block" data-back>Done</button></div>`);
      }
      const t = st.show ? 'text' : 'password';
      const list = pwRules(st, params.set);
      const mismatch = params.error && st.pw2 && st.pw1 !== st.pw2;
      return youPage(title, `
        ${hero(params.set
          ? { ic: 'password', title: 'Set a password', sub: 'Sign in on a new phone without another device', pills: [{ icon: 'warning-circle', text: 'Orbit cannot reset it', tone: 'warn' }] }
          : { ic: 'password', title: 'Change password', sub: 'Last changed 3 weeks ago', pills: [{ icon: 'device-mobile', text: 'Checked on this device' }, { icon: 'lock-simple', text: 'Never sent to Orbit' }] })}
        <div class="group-title eyebrow">${params.set ? 'Your new password' : 'Passwords'}</div>
        ${formCard(`${params.linked ? field({ id: 'pwPhone', label: 'Your phone number', value: '+880 ', inputmode: 'tel', helper: 'Needed once to check your current password, with its country code' }) : ''}${params.set ? '' : field({ id: 'pw0', label: 'Current password', type: t, value: params.wrong ? 'not-it' : st.pw0, error: params.wrong ? 'That is not your current password.' : '' })}${params.wrong ? Kit.fieldLock('Too many tries. Try again in 15 minutes.') : ''}
          ${field({ id: 'pw1', label: 'New password', type: t, value: st.pw1 })}
          ${field({ id: 'pw2', label: 'Confirm new password', type: t, value: st.pw2, error: mismatch ? 'The passwords do not match.' : '' })}
          ${rules(list)}
          ${check('Show passwords', st.show, 'data-show')}`)}
        <div class="btn-row"><button class="btn primary block" data-save ${list.every((r) => r.ok) ? '' : 'disabled'}>${st.busy ? '<i class="ph ph-spinner-gap spin"></i>' : title}</button></div>
        <p class="sec-foot">${params.set ? 'Choose one you will remember: Orbit cannot reset it.' : 'Only a key made from your password leaves this device, so Orbit cannot reset it.'}</p>`);
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      // Typing updates the rules and the button in place, so the field keeps focus.
      el.querySelectorAll('#pw0, #pw1, #pw2').forEach((i) => i.addEventListener('input', () => {
        st[i.id] = i.value;
        const list = pwRules(st, params.set);
        el.querySelector('.rules').outerHTML = rules(list);
        el.querySelector('[data-save]').disabled = !list.every((r) => r.ok);
      }));
      el.querySelector('[data-show]')?.addEventListener('toggle', (e) => { st.show = e.detail; el.querySelectorAll('.fld input').forEach((i) => { i.type = e.detail ? 'text' : 'password'; }); });
      el.querySelector('[data-save]')?.addEventListener('click', () => { st.busy = true; entry.rerender(); setTimeout(() => { st.busy = false; st.done = true; if (entry.el.isConnected) entry.rerender(); }, 900); });
    },
  });

  // ---------------------------------------------------------- delete account
  reg({
    id: 'delete-account', title: 'Delete my account',
    interactions: [
      ['type', 'Type DELETE', 'Must read DELETE before anything is deleted.'],
      ['tap', 'Send me a code (SMS)', 'Sends a code; the code field appears with “Send a new code”.'],
      ['tap', 'Eye in the password field', 'Shows or hides the password.'],
      ['tap', 'Delete my account', 'Deletes, wipes this device, and returns to sign-in.'],
      ['tap', 'Export my data first / Cancel', 'Shares the account data, or goes back.'],
    ],
    entries: [
      { key: 'delete-account', label: 'Delete my account · password', params: { proof: 'password' }, base: deeper('account') },
      { key: 'delete-account-sms', label: 'Delete my account · SMS code', params: { proof: 'sms' }, base: deeper('account') },
      { key: 'delete-account-key', label: 'Delete my account · this phone’s key', params: { proof: 'key' }, base: deeper('account') },
      { key: 'delete-account-linked', label: 'Delete my account · linked device (number needed)', params: { proof: 'password', linked: true }, base: deeper('account') },
    ],
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, sent: false, typed: '' });
      let proof = '';
      if (params.proof === 'password') proof = (params.linked ? field({ id: 'dPhone', label: 'Your phone number', value: '+880 ', inputmode: 'tel', helper: 'Needed once to check your password, with its country code' }) : '') + field({ id: 'dpw', label: 'Your password', type: 'password', eye: true, helper: 'It is checked on this phone; Orbit never sees it.' });
      if (params.proof === 'sms') proof = st.sent ? `<p class="fld-help" style="margin:0 2px 10px">We sent a 6-digit code to ${esc(Data.me.masked)}.</p>${field({ id: 'dcode', label: 'Code', inputmode: 'numeric', max: 6, mono: true })}<button class="btn ghost" style="height:36px;padding:0 4px;margin:-6px 0 10px" data-resend>Send a new code</button>` : '<p class="fld-help" style="margin:0 2px 14px">Orbit will text a code to your phone number to check that it is you.</p>';
      if (params.proof === 'key') proof = '<p class="fld-help" style="margin:0 2px 14px">This phone will prove it is yours with its own key. Nothing else to enter.</p>';
      const primary = params.proof === 'sms' && !st.sent ? 'Send me a code' : 'Delete my account';
      const what = (ic, title) => row({ icon: ic, color: 7, title, tag: 'div' });
      return youPage('Delete my account', `
        ${hero({ ic: 'warning', tone: 'danger', title: 'Delete your account', sub: 'Permanent · every device · cannot be undone' })}
        ${section('What happens', [
          what('user-minus', 'Your account and your devices are removed'),
          what('cloud-x', 'Everything the server holds for you is deleted'),
          what('devices', 'Your other devices lose their messages when they are signed out'),
          what('chats', 'People you talked to keep their copies'),
        ])}
        ${section('', [row({ icon: 'export', color: 2, title: 'Export my data first', sub: 'Account details, devices and settings', end: 'chevron', attrs: 'data-snack="Opens the share sheet with orbit-account.json"' })])}
        <div class="group-title eyebrow dz-title">Confirm it is you</div>
        <div class="card form-card danger-zone">${field({ id: 'dtype', label: 'Type DELETE to confirm', hint: 'DELETE', mono: true, value: st.typed })}${proof}</div>
        ${st.busy ? `<div class="pad" style="margin-top:14px">${progress(null)}</div>` : ''}
        <div class="btn-row" style="flex-direction:column"><button class="btn danger block" data-del>${icon('trash')}${primary}</button>
          <button class="btn secondary block" data-back>Cancel</button></div>`);
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelector('#dtype').addEventListener('input', (e) => { st.typed = e.target.value; });
      el.querySelector('[data-resend]')?.addEventListener('click', () => App.snack('A new code is on its way'));
      el.querySelector('[data-del]').addEventListener('click', () => {
        if (params.proof === 'sms' && !st.sent) { st.sent = true; entry.rerender(); return; }
        if (st.typed !== 'DELETE') { App.snack('Type DELETE to confirm.'); return; }
        st.busy = true; entry.rerender();
        setTimeout(() => { App.snack('Your account was deleted and this phone was wiped. Signing you out...'); setTimeout(() => App.reset('signin', { step: 'phone' }), 1200); }, 900);
      });
    },
  });

  // ----------------------------------------------------------------- blocked
  // Since ADR-030 a blocked person is told they are blocked, so the page says so.
  reg({
    id: 'blocked', title: 'Blocked',
    interactions: [
      ['tap', 'Unblock', 'Asks first, then removes them from the list.'],
    ],
    entries: [{ key: 'blocked', label: 'Blocked', params: {}, base: deeper('privacy') }, { key: 'blocked-empty', label: 'Blocked · nobody', params: { empty: true }, base: deeper('privacy') }],
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, list: params.empty ? [] : ['shuvo'] });
      const n = st.list.length;
      const person = (id) => { const p = Data.people[id]; return `<div class="row">${avatar(Data.av(p), 40)}<span class="rw-body"><span class="rw-title" style="display:block">${esc(Data.displayName(p))}</span><span class="rw-sub mono" style="display:block">${esc(p.names.number)}</span></span><button class="btn secondary" style="height:38px" data-unblock="${id}">Unblock</button></div>`; };
      return youPage('Blocked', `
        ${hero({ ic: 'prohibit', title: n ? `${n} blocked ${n === 1 ? 'person' : 'people'}` : 'Nobody is blocked', sub: n ? 'They cannot message or call you' : 'People you block cannot message or call you',
          pills: [{ icon: 'eye', text: 'Orbit tells them they are blocked' }] })}
        ${n ? section('Blocked', st.list.map(person)) : ''}
        <p class="sec-foot">${n ? '' : 'Nobody is blocked. '}To block someone, open their chat or their contact page.</p>`);
    },
    mount(el, params, entry) {
      wire(el, entry);
      el.querySelectorAll('[data-unblock]').forEach((b) => b.addEventListener('click', () => App.dialog({ title: `Unblock ${Data.displayName(Data.people[b.dataset.unblock])}?`, text: 'They will be able to message and call you again.', actions: [{ label: 'Cancel' }, { label: 'Unblock', kind: 'primary', run: () => { entry.state.list = entry.state.list.filter((x) => x !== b.dataset.unblock); entry.rerender(); App.snack('Unblocked'); } }] })));
    },
  });

  // ------------------------------------------------------------ about, legal
  const DOCS = {
    terms: ['Orbit Terms of Service', '3', 'These terms explain how you may use Orbit and what we promise in return.\n\nYour account. You sign up with your phone number. Keep your password and your devices safe.\n\nYour messages. Messages and calls are end-to-end encrypted. The server stores them only until they are delivered and cannot read them.\n\nAcceptable use. Do not use Orbit to send spam, to harass people, or to break the law.'],
    privacy: ['Orbit Privacy Policy', '4', 'What the server keeps: your phone number, your devices and their public keys, and encrypted messages until they are delivered.\n\nWhat it never sees: the content of your messages and calls, your profile name, about line and picture.\n\nContacts are hashed on your phone before any check; names never leave it.'],
  };
  reg({
    id: 'about', title: 'Help and about',
    interactions: [
      ['tap', 'Terms of Service / Privacy Policy tile', 'Opens that document.'],
      ['tap', 'Server details', 'Opens Advanced.'],
      ['tap', 'Open-source licences', 'Opens the licence page.'],
      ['tap', 'Send crash reports', 'Switch.'],
    ],
    entries: [{ key: 'about', label: 'Help and about', params: {} }, { key: 'about-no-crash', label: 'Help and about · server takes no crash reports', params: { noCrash: true } }],
    render(params) {
      const doc = (k, ic, color, title) => `<button class="stile" data-go="legal" data-params='{"doc":"${k}"}'><span class="rw-ico av-${color}">${icon(ic)}</span><span class="st-title">${title}</span><span class="st-meta">Version ${DOCS[k][1]}</span></button>`;
      return youPage('Help and about', `
        ${hero({ art: '<span class="hc-logo" role="img" aria-label="Orbit"></span>', title: 'Orbit', sub: 'Version 2.0.0 (412)',
          pills: [{ icon: 'globe-simple', text: 'Orbit Global' }, { icon: 'lock-simple', text: 'End-to-end encrypted' }] })}
        <div class="group-title eyebrow">Legal</div>
        <div class="stiles" style="padding-top:0">${doc('terms', 'scroll', 2, 'Terms of Service')}${doc('privacy', 'shield-check', 3, 'Privacy Policy')}</div>
        ${section('More', [
          row({ icon: 'hard-drives', color: 1, title: 'Server details', sub: `Orbit Global (${Data.me.host})`, end: 'chevron', attrs: 'data-go="advanced"' }),
          row({ icon: 'code', color: 7, title: 'Open-source licences', end: 'chevron', attrs: 'data-snack="Opens Flutter’s licence page"' }),
        ])}
        ${params.noCrash
          ? section('Diagnostics', [row({ icon: 'bug', color: 7, title: 'Crash reports', sub: 'This server does not accept crash reports', tag: 'div' })])
          : section('Diagnostics', [sw('Send crash reports', 'Only the error’s type, the app version and the platform', false)], 'A crash report never contains messages, names, numbers or keys.')}`);
    },
    mount(el, params, entry) { wire(el, entry); },
  });

  reg({
    id: 'legal', title: 'Terms and Privacy Policy',
    interactions: [
      ['tap', 'Terms / Privacy', 'Switches the document.'],
    ],
    entries: [{ key: 'legal', label: 'Terms and Privacy Policy', params: {}, base: deeper('about') }],
    render(params, entry) {
      const st = entry.state; st.doc = st.doc || params.doc || 'terms';
      const [t, v, b] = DOCS[st.doc];
      return youPage('Terms and Privacy Policy', `<div class="pad" style="margin-top:6px">${Kit.seg([['terms', 'Terms', 'file-text'], ['privacy', 'Privacy', 'shield-check']], st.doc, 'data-doc')}</div>
        <div class="card doc-card"><div class="doc-head"><h2>${t}</h2><span class="tag">Version ${v}</span></div><div class="legal-body">${esc(b)}</div></div>`, { keep: 'legal' });
    },
    mount(el, params, entry) { wire(el, entry); el.querySelectorAll('[data-doc]').forEach((b) => b.addEventListener('click', () => { entry.state.doc = b.dataset.doc; entry.rerender(); })); },
  });

  // ----------------------------------------------------------------- advanced
  reg({
    id: 'advanced', title: 'Advanced',
    interactions: [
      ['tap', 'Check for messages now', 'Spinner, then Up to date.'],
      ['tap', 'Try again (cannot reach the server)', 'Tries again.'],
    ],
    entries: [{ key: 'advanced', label: 'Advanced', params: {} }, { key: 'advanced-offline', label: 'Advanced · server unreachable', params: { offline: true } }],
    render(params, entry) {
      const st = entry.state;
      const fact = (ic, color, t, v) => row({ icon: ic, color, title: t, value: `<span class="mono">${v}</span>`, tag: 'div' });
      const feat = (t, on) => row({ title: t, end: `<span class="tag ${on ? 'success' : ''}">${on ? 'On' : 'Off'}</span>`, tag: 'div' });
      const pills = params.offline
        ? [{ icon: 'warning-circle', text: 'Cannot reach it', tone: 'warn' }]
        : [{ icon: 'check-circle', text: 'Connected', tone: 'ok' }, { icon: 'tag', text: 'Server 2.0.4' }, { icon: 'user-plus', text: 'New accounts can join' }];
      const sync = st.syncing ? '<i class="ph ph-spinner-gap spin"></i>' : st.synced ? `<span class="tag success">${icon('check', 'bold')}Up to date</span>` : '';
      return youPage('Advanced', `
        ${hero({ ic: 'hard-drives', title: 'Orbit Global', sub: Data.me.host, pills, tone: params.offline ? 'warn' : '' })}
        ${params.offline ? notice('error', 'The server could not be reached, so its details are not available.', { label: 'Try again', attr: 'data-snack="Trying again…"' })
          : `${section('Limits and documents', [fact('paperclip', 2, 'Largest attachment', '100 MB'), fact('scroll', 3, 'Terms version', '3'), fact('shield-check', 1, 'Privacy policy version', '4')])}
          ${section('Server features', [feat('Crash reports accepted', true), feat('Minimal usage counts', false), feat('Group calls', false)], 'Switched by the server’s operator.')}`}
        ${section('Connection', [row({ icon: 'arrows-clockwise', color: 0, title: 'Check for messages now', end: sync, attrs: 'data-sync' })], 'Orbit keeps a live connection to the server while it is open, so this is rarely needed.')}`);
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelector('[data-sync]').addEventListener('click', () => { st.syncing = true; st.synced = false; entry.rerender(); setTimeout(() => { st.syncing = false; st.synced = true; if (entry.el.isConnected) entry.rerender(); }, 900); });
    },
  });
})();
