/*
  Settings pages and Profile. Flutter: features/settings/presentation/*,
  features/profile/presentation/profile_page.dart. Copy from SCREENS.md.
*/
(() => {
  const { esc, icon, ibtn, avatar, row } = UI;
  const { section, sw, field, intro, notice, check, wire, confirm, progress } = Kit;
  const base = [{ screen: 'home', params: { tab: 'chats' } }, { screen: 'settings-page', params: {} }];
  const deeper = (screen, params = {}) => [base, { screen, params }];
  const reg = (def) => App.register({ group: 'Settings', order: 60, ...def, entries: def.entries.map((e) => ({ base, ...e })) });

  reg({
    id: 'password', title: 'Change password',
    entries: [
      { key: 'password', label: 'Change password', params: {}, base: deeper('account') },
      { key: 'password-set', label: 'Set a password', params: { set: true }, base: deeper('account', { noPassword: true }) },
      { key: 'password-error', label: 'Change password · mismatch', params: { error: true }, base: deeper('account') },
      { key: 'password-done', label: 'Change password · saved', params: { done: true }, base: deeper('account') },
    ],
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, done: params.done, show: false });
      const t = st.show ? 'text' : 'password';
      if (st.done) return Kit.page({ title: params.set ? 'Set a password' : 'Change password', body: `${notice('success', 'Your password is saved. Use it to sign in on a new phone.')}<div class="btn-row"><button class="btn primary block" data-back>Done</button></div>` });
      return Kit.page({ title: params.set ? 'Set a password' : 'Change password', body: `
        ${intro('', params.set ? 'A password lets you sign in on a new phone without another device. Choose one you will remember: Orbit cannot reset it.' : 'Enter your current password, then choose a new one.')}
        <div class="pad" style="margin-top:16px">
          ${params.set ? '' : field({ id: 'pw0', label: 'Current password', type: t })}
          ${field({ id: 'pw1', label: 'New password', type: t, helper: 'At least 8 characters' })}
          ${field({ id: 'pw2', label: 'Confirm new password', type: t, error: params.error ? 'The passwords do not match.' : '' })}
          ${check('Show passwords', st.show, 'data-show')}
          <button class="btn primary block" style="margin-top:8px" data-save>${st.busy ? '<i class="ph ph-spinner-gap spin"></i>' : params.set ? 'Set password' : 'Change password'}</button></div>` });
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelector('[data-show]')?.addEventListener('toggle', (e) => { st.show = e.detail; el.querySelectorAll('.fld input').forEach((i) => { i.type = e.detail ? 'text' : 'password'; }); });
      el.querySelector('[data-save]')?.addEventListener('click', () => { st.busy = true; entry.rerender(); setTimeout(() => { st.busy = false; st.done = true; entry.rerender(); }, 900); });
    },
  });

  reg({
    id: 'delete-account', title: 'Delete my account',
    entries: [
      { key: 'delete-account', label: 'Delete my account · password', params: { proof: 'password' }, base: deeper('account') },
      { key: 'delete-account-sms', label: 'Delete my account · SMS code', params: { proof: 'sms' }, base: deeper('account') },
      { key: 'delete-account-key', label: 'Delete my account · this phone’s key', params: { proof: 'key' }, base: deeper('account') },
    ],
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, sent: false, typed: '' });
      let proof = '';
      if (params.proof === 'password') proof = field({ id: 'dpw', label: 'Your password', type: 'password', eye: true, helper: 'It is checked on this phone; Orbit never sees it.' });
      if (params.proof === 'sms') proof = st.sent ? `<p class="fld-help" style="margin:0 2px 10px">We sent a 6-digit code to ${esc(Data.me.masked)}.</p>${field({ id: 'dcode', label: 'Code', inputmode: 'numeric', max: 6, mono: true })}<button class="btn ghost" style="height:36px;padding:0 4px;margin:-6px 0 10px" data-resend>Send a new code</button>` : '<p class="fld-help" style="margin:0 2px 12px">Orbit will text a code to your phone number to check that it is you.</p>';
      if (params.proof === 'key') proof = '<p class="fld-help" style="margin:0 2px 12px">This phone will prove it is yours with its own key. Nothing else to enter.</p>';
      const primary = params.proof === 'sms' && !st.sent ? 'Send me a code' : 'Delete my account';
      return Kit.page({ title: 'Delete my account', body: `
        ${intro('This cannot be undone', 'Your account, your devices and everything the server holds for you are removed. Messages on your other devices are deleted when they are signed out. People you talked to keep their copies.')}
        <div class="pad" style="margin-top:16px">${field({ id: 'dtype', label: 'Type DELETE to confirm', hint: 'DELETE', mono: true, value: st.typed })}${proof}
        ${st.busy ? progress(null) : ''}
        <button class="btn danger block" style="margin-top:8px" data-del>${icon('trash')}${primary}</button>
        <button class="btn secondary block" style="margin-top:10px" data-back>Cancel</button></div>` });
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

  reg({
    id: 'blocked', title: 'Blocked',
    entries: [{ key: 'blocked', label: 'Blocked', params: {}, base: deeper('privacy') }, { key: 'blocked-empty', label: 'Blocked · nobody', params: { empty: true }, base: deeper('privacy') }],
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, list: params.empty ? [] : ['shuvo'] });
      if (!st.list.length) return Kit.page({ title: 'Blocked', body: UI.empty({ icon: 'prohibit', title: 'Nobody is blocked', text: 'People you block cannot message or call you. Block someone from their chat.' }) });
      return Kit.page({ title: 'Blocked', body: `<div style="height:14px"></div><div class="card">${st.list.map((id) => `<div class="row">${avatar(Data.av(Data.people[id]), 40)}<span class="rw-body"><span class="rw-title" style="display:block">${esc(Data.displayName(Data.people[id]))}</span><span class="rw-sub mono" style="display:block">${esc(Data.people[id].names.number)}</span></span><button class="btn secondary" style="height:38px" data-unblock="${id}">Unblock</button></div>`).join('')}</div>` });
    },
    mount(el, params, entry) {
      wire(el, entry);
      el.querySelectorAll('[data-unblock]').forEach((b) => b.addEventListener('click', () => App.dialog({ title: 'Unblock Shuvo?', text: 'They will be able to message and call you again.', actions: [{ label: 'Cancel' }, { label: 'Unblock', kind: 'primary', run: () => { entry.state.list = []; entry.rerender(); } }] })));
    },
  });

  // ------------------------------------------------------------ about, legal
  reg({
    id: 'about', title: 'Help and about',
    entries: [{ key: 'about', label: 'Help and about', params: {} }],
    render() {
      return Kit.page({ title: 'Help and about', body: `
        ${section('Orbit', [row({ icon: 'info', color: 0, title: 'Version', value: '<span class="mono">2.0.0 (412)</span>', tag: 'div' }), row({ icon: 'globe-simple', color: 1, title: 'Server', sub: `Orbit Global (${Data.me.host})`, tag: 'div' })])}
        ${section('Legal', [row({ icon: 'scroll', color: 2, title: 'Terms of Service and Privacy Policy', sub: 'Terms 3, privacy 4', end: 'chevron', attrs: 'data-go="legal"' }), row({ icon: 'code', color: 7, title: 'Open-source licences', end: 'chevron', attrs: 'data-snack="Opens Flutter’s licence page"' })])}
        ${section('Diagnostics', [sw('Send crash reports', 'Only the error’s type, the app version and the platform', false)], 'A crash report never contains messages, names, numbers or keys.')}` });
    },
    mount(el, params, entry) { wire(el, entry); },
  });

  reg({
    id: 'legal', title: 'Terms and Privacy Policy',
    entries: [{ key: 'legal', label: 'Terms and Privacy Policy', params: {}, base: deeper('about') }],
    render(params, entry) {
      const st = entry.state; st.doc = st.doc || 'terms';
      const docs = { terms: ['Orbit Terms of Service', '3', 'These terms explain how you may use Orbit and what we promise in return.\n\nYour account. You sign up with your phone number. Keep your password and your devices safe.\n\nYour messages. Messages and calls are end-to-end encrypted. The server stores them only until they are delivered and cannot read them.\n\nAcceptable use. Do not use Orbit to send spam, to harass people, or to break the law.'], privacy: ['Orbit Privacy Policy', '4', 'What the server keeps: your phone number, your devices and their public keys, and encrypted messages until they are delivered.\n\nWhat it never sees: the content of your messages and calls, your profile name, about line and picture.\n\nContacts are hashed on your phone before any check; names never leave it.'] };
      const [t, v, b] = docs[st.doc];
      return Kit.page({ title: 'Terms and Privacy Policy', body: `<div class="pad" style="margin-top:12px">${Kit.seg([['terms', 'Terms', 'file-text'], ['privacy', 'Privacy', 'shield-check']], st.doc, 'data-doc')}</div>
        <div class="pintro"><h2>${t}</h2><p class="mono" style="font-size:11.5px">Version ${v}</p></div><div class="legal-body">${esc(b)}</div>` });
    },
    mount(el, params, entry) { wire(el, entry); el.querySelectorAll('[data-doc]').forEach((b) => b.addEventListener('click', () => { entry.state.doc = b.dataset.doc; entry.rerender(); })); },
  });

  // ----------------------------------------------------------------- advanced
  reg({
    id: 'advanced', title: 'Advanced',
    entries: [{ key: 'advanced', label: 'Advanced', params: {} }, { key: 'advanced-offline', label: 'Advanced · server unreachable', params: { offline: true } }],
    render(params, entry) {
      const st = entry.state;
      const fact = (t, v) => row({ title: t, value: `<span class="mono">${v}</span>`, tag: 'div' });
      const feat = (t, on) => row({ title: t, value: on ? 'On' : 'Off', end: icon(on ? 'check-circle' : 'circle', on ? 'fill' : ''), tag: 'div' });
      return Kit.page({ title: 'Advanced', body: `
        ${params.offline ? notice('error', 'The server could not be reached, so its details are not available.', { label: 'Try again', attr: 'data-snack="Trying again…"' })
          : `${section('Server', [fact('Name', 'Orbit Global'), fact('Address', Data.me.host), fact('Server version', '2.0.4'), fact('New accounts', 'Can join'), fact('Largest attachment', '100 MB'), fact('Terms version', '3'), fact('Privacy policy version', '4')])}
          ${section('Server features', [feat('Crash reports accepted', true), feat('Minimal usage counts', false), feat('Group calls', false)], 'Switched by the server’s operator.')}`}
        ${st.synced ? notice('success', 'Up to date.') : ''}
        ${section('Connection', [row({ icon: 'arrows-clockwise', color: 0, title: 'Check for messages now', end: st.syncing ? '<i class="ph ph-spinner-gap spin"></i>' : '', attrs: 'data-sync' })], 'Orbit keeps a live connection to the server while it is open, so this is rarely needed.')}` });
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelector('[data-sync]').addEventListener('click', () => { st.syncing = true; st.synced = false; entry.rerender(); setTimeout(() => { st.syncing = false; st.synced = true; if (entry.el.isConnected) entry.rerender(); }, 900); });
    },
  });

})();
