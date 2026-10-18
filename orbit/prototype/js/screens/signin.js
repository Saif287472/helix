/*
  Sign-in (/sign-in), the restore step (/restore), link this device
  (/link-device, reachable signed out), the reset screen and the app lock.
  Flutter: SignInScreen + SignInFrame, RestoreHistoryPage(afterSignIn),
  LinkThisDevicePage, ResetScreen, AppLockGate. Copy from SCREENS.md.
*/
(() => {
  const { esc, icon, ibtn } = UI;
  const { field, check, notice, code, qr, progress } = Kit;
  const LEGAL = {
    terms: { title: 'Orbit Terms of Service', version: '3', date: '1 September 2026', body: 'These terms explain how you may use Orbit and what we promise in return.\n\n1. Your account. You sign up with your phone number. Keep your password and your devices safe; anyone holding an unlocked, signed-in device can read your messages.\n\n2. Your messages. Messages and calls are end-to-end encrypted. The server stores them only until they are delivered and cannot read them.\n\n3. Acceptable use. Do not use Orbit to send spam, to harass people, or to break the law.\n\n4. Changes. We will tell you in the app before these terms change.' },
    privacy: { title: 'Orbit Privacy Policy', version: '4', date: '1 September 2026', body: 'This policy explains what Orbit keeps and why.\n\nWhat the server keeps: your phone number (to find you), your devices and their public keys, and encrypted messages until they are delivered.\n\nWhat it never sees: the content of your messages, calls, profile name, about line and pictures.\n\nContacts: numbers are hashed on your phone before any check; names never leave it.\n\nBackups: encrypted with a key only your devices hold.' },
  };

  function legalSheet(start = 'terms') {
    const draw = (k) => `<div class="sh-head" style="display:flex;align-items:center;gap:8px;padding-right:10px"><h2 style="flex:1">${LEGAL[k].title}</h2>${ibtn('x', 'Close', 'data-x')}</div>
      <div class="legal-meta">Version ${LEGAL[k].version} · Effective ${LEGAL[k].date}</div>
      <div style="padding:12px 18px 0">${Kit.seg([['terms', 'Terms', 'file-text'], ['privacy', 'Privacy', 'shield-check']], k, 'data-doc')}</div>
      <div class="legal-body">${esc(LEGAL[k].body)}</div>`;
    const h = App.sheet({ body: `<div data-legal>${draw(start)}</div>` });
    h.panel.style.height = '88%';
    const bind = () => {
      h.panel.querySelector('[data-x]').addEventListener('click', () => h.close());
      h.panel.querySelectorAll('[data-doc]').forEach((b) => b.addEventListener('click', () => { h.panel.querySelector('[data-legal]').innerHTML = draw(b.dataset.doc); bind(); }));
    };
    bind();
  }

  // ---------------------------------------------------------------- steps
  const STEPS = {
    phone: (st) => ({
      title: 'Sign in', sub: 'Use your phone number to continue to Orbit.', back: false,
      fields: field({ id: 'siPhone', label: 'Phone number', prefix: '+880', value: st.phone || '', hint: '1711 000001', inputmode: 'tel', helper: 'New to Orbit? Enter your number and we will set up your account.' }),
      primary: 'Next', foot: true, corner: true,
    }),
    phoneAdv: (st) => ({
      title: st.recovery ? 'Recover your account' : 'Join the server', sub: st.recovery ? 'Enter the phone number of the account.' : 'Enter your phone number.', back: true, badge: true,
      fields: field({ id: 'siPhone', label: 'Phone number', prefix: '+880', value: st.phone || '', hint: '1711 000001', inputmode: 'tel', helper: 'Continuing moves your account to this phone.' }),
      primary: 'Next',
    }),
    code: (st) => ({
      title: 'Enter the code', sub: `We sent a 6-digit code by SMS to +880 ${esc(st.phone || '1711 000001')}.`, back: true,
      fields: field({ id: 'siCode', label: 'Enter code', value: st.code || '', hint: '••••••', inputmode: 'numeric', max: 6, big: true }),
      secondary: 'Resend code', primary: 'Next',
    }),
    password: (st) => ({
      title: 'Welcome back', sub: `+880 ${esc(st.phone || '1711 000001')}`, back: true,
      fields: field({ id: 'siPass', label: 'Password', type: 'password', eye: true }) +
        `<p class="fld-help" style="margin:-4px 2px 4px">Your other devices stay signed in. Signing in with an SMS code instead signs them out.</p>
        <button class="btn ghost" data-link-instead style="padding:0 4px;height:44px;align-self:flex-start">${icon('qr-code')}Link from another device instead</button>`,
      secondary: 'Forgot password?', primary: 'Sign in',
    }),
    name: (st) => ({
      title: 'Your name', sub: 'This is how your contacts will see you.', back: true,
      fields: field({ id: 'siName', label: 'Your name', value: st.name || '', max: 80 }) +
        check('I agree to the Orbit Terms of Service and Privacy Policy', st.terms, 'data-terms') +
        `<button class="btn ghost" data-legal style="padding:0 4px;height:40px;align-self:flex-start;margin:-2px 0 10px">${icon('book-open-text')}Read the Terms and Privacy Policy</button>
        <p class="fld-help" style="margin:4px 2px 8px">Set a password (optional) so you can sign back in on a new phone without another device.</p>` +
        field({ id: 'siNewPass', label: 'Password (optional)', type: 'text', eye: true }),
      secondary: 'Skip', primary: 'Create account',
    }),
    takeover: () => ({
      title: 'Welcome back', sub: 'Accept the terms to continue to your account.', back: true,
      fields: `<div class="inotice warning" style="margin:0 0 14px">${icon('devices', 'fill')}<div class="in-body">Continuing moves your account to this phone and signs your other devices out.</div></div>`,
      secondary: 'Link from another device instead', primary: 'Continue',
    }),
    advCode: (st) => {
      const v = (st.setup || '').trim().toUpperCase();
      const det = v.startsWith('HLX-REC-') ? ['ok', 'Recovery code: you will sign back in to your account.'] : v.startsWith('HLX-INV-') ? ['ok', 'Invite code: you will create an account on that server.'] : ['', 'Your server admin gives you this code.'];
      return {
        title: 'Personal server', sub: 'Enter the invite or recovery code from your server admin.', back: true,
        fields: field({ id: 'siSetup', label: 'Invite or recovery code', value: st.setup || '', hint: 'HLX-INV-… or HLX-REC-…', mono: true, paste: true }) +
          `<div class="si-detect ${det[0]}">${icon(det[0] ? 'check-circle' : 'info', det[0] ? 'fill' : '')}${det[1]}</div>`,
        primary: 'Next', corner: true,
      };
    },
    serverConfirm: () => ({
      title: 'Personal server', sub: 'This code wants to sign you in on <span class="mono" style="color:var(--ink)">chat.rahman.family</span>.', back: true,
      fields: `<div class="card" style="margin:0 0 14px;padding:16px;display:flex;gap:12px">${icon('hard-drives')}<span style="font-size:14px;line-height:1.5;color:var(--ink-2)">Only continue if you know this server and expected this code. Your phone number and messages will be handled by it.</span></div>`,
      secondary: 'Cancel', primary: 'Continue',
    }),
  };

  const ERRORS = {
    badPhone: 'Enter a valid phone number.',
    taken: 'This phone number already has an account on this server. Ask your server admin for a recovery code to sign back in.',
    offline: 'Could not reach the server. Check your connection and try again.',
    rate: 'Too many attempts. Wait a moment and try again.',
    maintenance: 'This server is down for maintenance. Try again shortly.',
    badCode: 'That code is not right. Check the SMS and try again.',
    blocked: 'This account has been blocked.',
    noSms: 'This server cannot send SMS codes. Ask your server admin for an invite code.',
    badPass: 'That password is not right. Try again, or use “Forgot password”.',
    lockedPass: 'Too many wrong passwords. Try again after 14:35, or use “Forgot password”.',
    terms: 'Accept the Terms of Service and Privacy Policy to continue.',
    badSetup: 'This is not an invite or recovery code. Paste the whole HLX-INV- or HLX-REC- code you were given.',
    usedInvite: 'This invite code has already been used.',
  };

  App.register({
    id: 'signin', title: 'Sign in', group: 'Sign-in', order: 5,
    interactions: [
      ['type', 'Phone number', 'Shows which country it detected; Next checks the length.'],
      ['type', 'SMS code', 'Digits only; the sixth digit continues by itself.'],
      ['tap', 'Resend code', 'Sends a new code.'],
      ['tap', 'Next / Sign in / Create account / Continue', 'Shows a spinner, then the next step or an error under the field.'],
      ['tap', 'Forgot password?', 'Opens the take-over step.'],
      ['tap', 'Link from another device instead', 'Opens Link this device.'],
      ['tap', 'Terms checkbox (new account)', 'Needed before Create account.'],
      ['tap', 'Skip (name step)', 'Creates the account without a name.'],
      ['tap', 'Back arrow on a step', 'Returns to the previous step.'],
      ['tap', 'Terms & Privacy', 'Sheet with both documents.'],
      ['tap', 'Bottom-right corner ×3 (each within 2 s)', 'Shows “Advanced mode” for 2 s; tapping it opens the personal-server code.'],
      ['type', 'Personal-server code', 'Accepts HLX-INV- and HLX-REC- codes; Paste fills it; then the server is confirmed.'],
    ],
    entries: [
      { key: 'signin', label: 'Sign in · phone', params: { step: 'phone' } },
      { key: 'signin-phone-error', label: 'Sign in · phone error', params: { step: 'phone', phone: '1711 00', error: 'badPhone' } },
      { key: 'signin-offline', label: 'Sign in · cannot reach server', params: { step: 'phone', phone: '1711 000001', error: 'offline' } },
      { key: 'signin-code', label: 'SMS code', params: { step: 'code', phone: '1711 000001' } },
      { key: 'signin-code-error', label: 'SMS code · wrong code', params: { step: 'code', phone: '1711 000001', code: '482910', error: 'badCode' } },
      { key: 'signin-password', label: 'Password (welcome back)', params: { step: 'password', phone: '1711 000001' } },
      { key: 'signin-password-error', label: 'Password · too many tries', params: { step: 'password', phone: '1711 000001', error: 'lockedPass' } },
      { key: 'signin-name', label: 'New account · your name', params: { step: 'name', phone: '1711 000001' } },
      { key: 'signin-name-terms', label: 'New account · terms not accepted', params: { step: 'name', phone: '1711 000001', name: 'Hasan', error: 'terms' } },
      { key: 'signin-takeover', label: 'Take-over confirmation', params: { step: 'takeover' } },
      { key: 'signin-advanced', label: 'Advanced · personal server code', params: { step: 'advCode' } },
      { key: 'signin-advanced-rec', label: 'Advanced · recovery code detected', params: { step: 'advCode', setup: 'HLX-REC-7Q2M-K9TD-XR4P' } },
      { key: 'signin-advanced-error', label: 'Advanced · not a code', params: { step: 'advCode', setup: 'hello', error: 'badSetup' } },
      { key: 'signin-server', label: 'Advanced · confirm the server', params: { step: 'serverConfirm' } },
      { key: 'signin-join', label: 'Advanced · join the server (phone)', params: { step: 'phoneAdv' } },
      { key: 'signin-legal', label: 'Terms and Privacy sheet', params: { step: 'phone', legal: true } },
    ],
    render(params, entry) {
      const st = entry.state;
      if (!st.init) Object.assign(st, { init: true, step: params.step, phone: params.phone, code: params.code, name: params.name, setup: params.setup, error: params.error, terms: false, recovery: false, history: [] });
      const s = STEPS[st.step](st);
      const err = st.error ? `<div class="si-error">${icon('warning-circle', 'fill')}<span>${ERRORS[st.error] || st.error}</span></div>` : '';
      return `<div class="si-top">${s.back ? ibtn('arrow-left', 'Back', 'data-si-back') : ''}</div>
        <div class="si-body">
          <div class="si-logo" role="img" aria-label="Orbit"></div>
          <h1 class="si-title">${s.title}</h1>
          <p class="si-sub">${s.sub}</p>
          ${s.badge ? `<span class="si-badge">${icon('hard-drives')}chat.rahman.family (Rahman Family)</span>` : ''}
          <div class="si-fields">${s.fields}</div>
          ${err}
          <div class="si-actions">${s.secondary ? `<button class="btn ghost" data-secondary>${s.secondary}</button>` : '<span></span>'}<button class="btn primary" data-primary>${st.busy ? '<i class="ph ph-spinner-gap spin"></i>' : s.primary}</button></div>
        </div>
        <div class="si-foot">${s.foot ? `<button class="btn ghost" style="height:40px;padding:0 6px;color:var(--ink-3)" data-legal>Terms &amp; Privacy</button>` : '<span></span>'}
          ${s.corner ? `<div class="si-corner" data-corner aria-hidden="true">${st.reveal ? '<button class="btn secondary" data-advanced style="height:40px;font-size:13px">Advanced mode</button>' : ''}</div>` : ''}</div>`;
    },
    mount(el, params, entry) {
      const st = entry.state; const rerender = () => entry.rerender();
      el.classList.add('signin');
      Kit.wire(el, entry);
      const go = (step) => { st.history.push(st.step); st.step = step; st.error = null; st.busy = false; rerender(); };
      const busy = (then) => { st.busy = true; rerender(); setTimeout(() => { st.busy = false; then(); }, 700); };
      const val = (id) => (el.querySelector(id)?.value || '').trim();
      el.querySelector('[data-si-back]')?.addEventListener('click', () => { st.step = st.history.pop() || (st.step === 'advCode' ? 'phone' : 'phone'); st.error = null; rerender(); });
      el.querySelectorAll('[data-legal]').forEach((b) => b.addEventListener('click', (e) => { e.preventDefault(); legalSheet(); }));
      el.querySelector('[data-terms]')?.addEventListener('toggle', (e) => { st.terms = e.detail; });
      el.querySelector('[data-link-instead]')?.addEventListener('click', () => App.push('link-device'));
      const setup = el.querySelector('#siSetup');
      if (setup) setup.addEventListener('input', () => { st.setup = setup.value; const pos = setup.selectionStart; rerender(); const n = el.querySelector('#siSetup'); n.focus(); n.setSelectionRange(pos, pos); });
      el.querySelector('[data-paste]')?.addEventListener('click', (e) => { e.preventDefault(); st.setup = 'HLX-INV-4FQ8-2KDM-ZP7W'; rerender(); });
      const codeIn = el.querySelector('#siCode');
      if (codeIn) codeIn.addEventListener('input', () => { codeIn.value = codeIn.value.replace(/\D/g, ''); st.code = codeIn.value; if (codeIn.value.length === 6) el.querySelector('[data-primary]').click(); });

      el.querySelector('[data-primary]').addEventListener('click', () => {
        switch (st.step) {
          case 'phone': case 'phoneAdv': {
            st.phone = val('#siPhone');
            if (st.phone.replace(/\D/g, '').length < 10) { st.error = 'badPhone'; rerender(); return; }
            busy(() => go('code')); break;
          }
          case 'code': if ((st.code || '').length < 6) { st.error = 'badCode'; rerender(); return; } busy(() => go('password')); break;
          case 'password': if (!val('#siPass')) { st.error = 'badPass'; rerender(); return; } busy(() => App.reset('restore', { afterSignIn: true })); break;
          case 'name': if (!st.terms) { st.error = 'terms'; rerender(); return; } busy(() => App.reset('home', { tab: 'chats' })); break;
          case 'takeover': busy(() => App.reset('home', { tab: 'chats' })); break;
          case 'advCode': {
            const v = (st.setup || '').toUpperCase();
            if (!/^HLX-(INV|REC)-/.test(v)) { st.error = 'badSetup'; rerender(); return; }
            st.recovery = v.startsWith('HLX-REC-'); busy(() => go('serverConfirm')); break;
          }
          case 'serverConfirm': go('phoneAdv'); break;
          default:
        }
      });
      el.querySelector('[data-secondary]')?.addEventListener('click', () => {
        if (st.step === 'code') App.snack('A new code is on its way');
        if (st.step === 'password') go('takeover');
        if (st.step === 'name') busy(() => App.reset('home', { tab: 'chats' }));
        if (st.step === 'takeover') App.push('link-device');
        if (st.step === 'serverConfirm') { st.step = 'advCode'; rerender(); }
      });
      // The hidden corner: 3 taps (each within 2 s) reveal "Advanced mode" for 2 s.
      const corner = el.querySelector('[data-corner]');
      if (corner) {
        corner.addEventListener('click', (e) => {
          if (e.target.closest('[data-advanced]')) { st.reveal = false; st.taps = 0; go('advCode'); return; }
          const t = Date.now();
          st.taps = t - (st.lastTap || 0) < 2000 ? (st.taps || 0) + 1 : 1; st.lastTap = t;
          if (st.taps >= 3) {
            st.reveal = true; rerender();
            clearTimeout(st.hide); st.hide = setTimeout(() => { st.reveal = false; st.taps = 0; if (entry.el.isConnected) rerender(); }, 2000);
          }
        });
      }
      if (params.legal && !st.legalShown) { st.legalShown = true; setTimeout(() => legalSheet(), 60); }
    },
  });

  // ------------------------------------------------- restore step / history
  // You style: a status ring card says where the restore is (ready, running,
  // nothing found, done); offers from your other devices sit under it.
  function restorePage(params, st) {
    const after = !!params.afterSignIn;
    const phase = st.phase || 'idle';
    const phases = ['Looking for your backup...', 'Downloading your backup...', 'Unlocking it...', 'Adding messages...'];
    const p = Math.min(0.95, (st.p || 0) / 4 + 0.1);
    const card = {
      idle: { art: Kit.ring('idle'), title: after ? 'Bring your chats back' : 'Restore from your backup', sub: 'Text messages only · files are not in the backup' },
      running: { art: Kit.ring('run', { p }), title: phases[st.p || 0], sub: st.p >= 3 ? '1,204 messages added so far' : 'Encrypted with a key only your devices have' },
      failed: { art: Kit.ring('bad'), title: 'No backup was found', sub: 'Back up on your other phone first, then try again' },
      done: { art: Kit.ring('ok'), title: 'Restored 2,318 messages', sub: 'Messages already here were kept' },
    }[phase];
    const offers = after || params.offer ? `<div class="group-title eyebrow">From your other devices</div>
      <div class="xfer" style="margin-top:0"><div class="xf-title">${icon('device-mobile', 'fill')}History from Galaxy S23</div><div class="xf-status">Ready to receive. Nothing is downloaded until you accept.</div>
      <div class="xf-actions"><button class="btn primary" data-snack="Receiving your history">Accept</button><button class="btn secondary" data-snack="Declined">Decline</button></div></div>
      <div class="group-title eyebrow">From your backup</div>` : '';
    const buttons = phase === 'done'
      ? `<div class="btn-row"><button class="btn primary block" data-continue>${after ? 'Continue' : 'Done'}</button></div>`
      : `<div class="btn-row" style="flex-direction:column">
          <button class="btn primary block" data-restore ${phase === 'running' ? 'disabled' : ''}>${icon('cloud-arrow-down')}${phase === 'failed' ? 'Try again' : 'Restore from my backup'}</button>
          <button class="btn secondary block" data-go="recovery" data-params='{"tab":"restore"}'>${icon('key')}I have a recovery secret</button>
          ${after ? '<button class="btn ghost block" data-skip>Skip for now</button>' : ''}</div>`;
    return `${after ? Kit.intro('Welcome back', '') : ''}${offers}${Kit.hero(card)}
      ${buttons}
      <p class="sec-foot" style="text-align:center;margin-top:16px">${after ? 'You can restore later from You, Backup.' : 'Text messages you backed up come back to this device. Messages already here are kept.'}</p>`;
  }

  App.register({
    id: 'restore', title: 'Restore your chats', group: 'Sign-in', order: 5,
    interactions: [
      ['tap', 'Restore from my backup', 'Runs with a percentage; then done, or nothing found.'],
      ['tap', 'I have a recovery secret', 'Opens Recovery backup on Restore.'],
      ['tap', 'Accept / Decline (history from another device)', 'Receives it, or declines.'],
      ['tap', 'Skip for now / Continue', 'Goes on to Chats.'],
    ],
    entries: [
      { key: 'restore', label: 'Restore step (after sign-in)', params: { afterSignIn: true } },
      { key: 'restore-running', label: 'Restore step · running', params: { afterSignIn: true, phase: 'running', p: 3 } },
      { key: 'restore-failed', label: 'Restore step · no backup', params: { afterSignIn: true, phase: 'failed' } },
      { key: 'restore-done', label: 'Restore step · done', params: { afterSignIn: true, phase: 'done' } },
    ],
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, phase: params.phase, p: params.p });
      return Kit.youPage(params.afterSignIn ? 'Restore your chats' : 'Restore history', restorePage(params, st), { back: !params.afterSignIn });
    },
    mount(el, params, entry) {
      const st = entry.state; Kit.wire(el, entry);
      el.querySelector('[data-restore]')?.addEventListener('click', () => {
        st.phase = 'running'; st.p = 0; entry.rerender();
        const tick = () => { if (!entry.el.isConnected) return; st.p++; if (st.p > 3) { st.phase = 'done'; } entry.rerender(); if (st.phase === 'running') setTimeout(tick, 700); };
        setTimeout(tick, 700);
      });
      el.querySelector('[data-skip]')?.addEventListener('click', () => App.reset('home', { tab: 'chats' }));
      el.querySelector('[data-continue]')?.addEventListener('click', () => (params.afterSignIn ? App.reset('home', { tab: 'chats' }) : App.pop()));
    },
  });
  // Exported for Settings > Backup > Restore history.
  window.HelixRestorePage = restorePage;

  // ------------------------------------------- link this device (new device)
  App.register({
    id: 'link-device', title: 'Link this device', group: 'Sign-in', order: 5,
    interactions: [
      ['auto', 'Code timer', 'Counts down to the code’s expiry.'],
      ['tap', 'Show a new code (expired)', 'Shows a fresh code and restarts the timer.'],
      ['tap', 'Simulate approval (prototype only)', 'Shows “Is this your account?”.'],
      ['tap', 'Yes, this is my account', 'Signs in, then the restore step.'],
      ['tap', 'No, cancel', 'Goes back.'],
    ],
    entries: [
      { key: 'link-device', label: 'Link this device · QR', params: {} },
      { key: 'link-device-expired', label: 'Link this device · code expired', params: { phase: 'expired' } },
      { key: 'link-device-confirm', label: 'Link this device · is this your account?', params: { phase: 'confirm' } },
    ].map((e) => ({ ...e, base: { screen: 'signin', params: { step: 'password', phone: '1711 000001' } } })),
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, phase: params.phase || 'waiting', secs: 585 });
      if (st.phase === 'confirm') {
        return `${UI.appbar({ title: 'Link this device', actions: '' }).replace(UI.ibtn('arrow-left', 'Back', 'data-back'), UI.ibtn('x', 'Cancel', 'data-back'))}
          <div class="scroll" style="padding-bottom:30px">
            ${Kit.intro('Is this your account?', 'Your other device approved this one. Check that this is your account before Orbit gives this phone its keys.')}
            ${Kit.section('The account', [UI.row({ icon: 'phone', color: 0, title: '+880 17•• ••0001', sub: 'Phone number, shown in part', tag: 'div' }), UI.row({ icon: 'at', color: 1, title: '~hasan', sub: 'Orbit name', tag: 'div' })])}
            ${code('Key code', '4821 9930 1175', { note: 'The same key code is shown on your other device. If it is different, or the account is not yours, choose No.' })}
            <p class="sec-foot">Choosing Yes gives this phone your account’s keys. It can then read your new messages.</p>
            <div class="btn-row" style="flex-direction:column"><button class="btn primary block" data-yes>${icon('check', 'bold')}Yes, this is my account</button><button class="btn secondary block" data-back>No, cancel</button></div>
          </div>`;
      }
      const t = `${Math.floor(st.secs / 60)}:${String(st.secs % 60).padStart(2, '0')}`;
      const status = st.phase === 'expired'
        ? notice('error', 'This code has expired. Show a new code to try again.', { label: 'Show a new code', attr: 'data-new' })
        : st.phase === 'approved' ? `<div class="pad" style="text-align:center;margin-top:14px;font-weight:600;color:var(--success)">${icon('check-circle', 'fill')} Approved. Signing in...</div>`
          : `<div class="pad" style="text-align:center;margin-top:14px;font-size:13.5px;color:var(--ink-3)">${icon('spinner-gap')} Waiting for approval. Code expires in <span class="mono" data-left>${t}</span>.</div>`;
      return Kit.page({ title: 'Link this device', body: `
        ${Kit.intro('', 'On a device that is already signed in to your account, open Settings, Devices, Link a new device, and scan this code. Show it only to your own device.')}
        <div class="qr-wrap" style="${st.phase === 'expired' ? 'opacity:.25' : ''}"><div class="qr-card">${qr('link-this-device', 220)}</div></div>
        ${code('Check number', '72 914', { cls: 'huge' })}
        ${status}
        ${st.phase === 'waiting' ? '<div class="pad" style="text-align:center;margin-top:10px"><button class="btn ghost" data-approve-demo>Simulate approval</button></div>' : ''}` });
    },
    mount(el, params, entry) {
      const st = entry.state; Kit.wire(el, entry);
      el.querySelector('[data-new]')?.addEventListener('click', () => { st.phase = 'waiting'; st.secs = 600; entry.rerender(); });
      el.querySelector('[data-approve-demo]')?.addEventListener('click', () => { st.phase = 'confirm'; entry.rerender(); });
      el.querySelector('[data-yes]')?.addEventListener('click', () => { st.phase = 'approved'; entry.rerender(); setTimeout(() => App.reset('restore', { afterSignIn: true }), 900); });
      if (st.phase === 'waiting' && !st.timer) st.timer = setInterval(() => { if (!entry.el.isConnected) { clearInterval(st.timer); return; } st.secs = Math.max(0, st.secs - 1); const n = entry.el.querySelector('[data-left]'); if (n) n.textContent = `${Math.floor(st.secs / 60)}:${String(st.secs % 60).padStart(2, '0')}`; }, 1000);
    },
  });

  // -------------------------------------------------------- reset and lock
  App.register({
    id: 'reset', title: 'Reset', group: 'App', order: 95,
    interactions: [
      ['type', 'Type DELETE', 'Turns on Reset Orbit.'],
      ['tap', 'Reset Orbit', 'Deletes the local data and returns to sign-in.'],
    ],
    entries: [
      { key: 'reset-window', label: 'Already open in another window', params: { kind: 'window' } },
      { key: 'reset-key', label: 'Reset required · key missing', params: { kind: 'key' } },
      { key: 'reset-decrypt', label: 'Reset required · cannot decrypt', params: { kind: 'decrypt' } },
    ],
    render(params, entry) {
      const st = entry.state;
      if (params.kind === 'window') {
        return `${UI.appbar({ title: 'Orbit', back: false })}<div class="center-page"><div class="cp-icon" style="background:var(--accent-soft);color:var(--accent)">${icon('app-window', 'fill')}</div><h2>Orbit is open elsewhere</h2><p>Orbit is already open in another window. Close that one, then try again.</p><button class="btn primary" style="margin-top:10px" data-snack="Trying again…">Try again</button></div>`;
      }
      const text = params.kind === 'key'
        ? 'An existing database was found, but its encryption key is not available in secure storage. A destructive reset is required to continue.'
        : 'Your local database could not be decrypted. Orbit never opens it without its key, so a destructive reset is required to continue.';
      const ok = (st.typed || '') === 'DELETE';
      return `${UI.appbar({ title: 'Reset required', back: false })}<div class="center-page" style="justify-content:flex-start;padding-top:40px">
        <div class="cp-icon" style="background:var(--danger-soft);color:var(--danger)">${icon('lock-key', 'fill')}</div><h2>Reset required</h2><p>${text}</p>
        <div style="width:100%;margin-top:18px;text-align:left">${field({ id: 'rsIn', label: 'Type DELETE to confirm', hint: 'DELETE', value: st.typed || '', mono: true })}</div>
        <button class="btn ${ok ? 'danger' : 'secondary'} block" data-reset ${ok ? '' : 'disabled style="opacity:.5"'}>${st.busy ? 'Deleting…' : 'Reset Orbit'}</button></div>`;
    },
    mount(el, params, entry) {
      const st = entry.state; Kit.wire(el, entry);
      const inp = el.querySelector('#rsIn');
      if (inp) inp.addEventListener('input', () => { st.typed = inp.value; const pos = inp.selectionStart; entry.rerender(); const n = entry.el.querySelector('#rsIn'); n.focus(); n.setSelectionRange(pos, pos); });
      el.querySelector('[data-reset]')?.addEventListener('click', () => { st.busy = true; entry.rerender(); setTimeout(() => App.reset('signin', { step: 'phone' }), 900); });
    },
  });

  App.register({
    id: 'lock', title: 'App lock', group: 'App', order: 95,
    interactions: [
      ['tap', 'Unlock', 'Asks for your fingerprint, face or PIN (Windows Hello on Windows), then opens Orbit.'],
    ],
    entries: [{ key: 'lock', label: 'App lock', params: {} }],
    render() {
      return `<div class="center-page" style="background:var(--bg)"><div class="cp-icon" style="background:var(--surface);border:1px solid var(--line);color:var(--accent);box-shadow:0 0 0 10px var(--bg),0 0 0 11px var(--line-2)">${icon('lock-simple', 'fill')}</div>
        <h2>Orbit is locked</h2><p>Unlock with ${UI.unlock().full}.</p>
        <button class="btn primary" style="margin-top:14px" data-unlock>${icon('fingerprint')}Unlock</button></div>`;
    },
    mount(el) { el.querySelector('[data-unlock]').addEventListener('click', () => App.reset('home', { tab: 'chats' })); },
  });
})();
