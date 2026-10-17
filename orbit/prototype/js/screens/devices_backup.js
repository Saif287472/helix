/*
  Devices (/devices, /devices/link, /devices/activity) and Backup (/backup,
  /backup/restore, /backup/transfer, /backup/recovery).
  Flutter: features/devices/presentation, features/backup/presentation.
*/
(() => {
  const { esc, icon, ibtn, row } = UI;
  const { section, sw, field, intro, notice, code, qr, progress, check, wire, confirm, inputDialog } = Kit;
  const base = [{ screen: 'home', params: { tab: 'chats' } }, { screen: 'settings-page', params: {} }];
  const DEVICES = [
    { id: 'd1', name: 'Pixel 8', platform: 'Android', icon: 'device-mobile', self: true },
    { id: 'd2', name: 'Office PC', platform: 'Windows', icon: 'desktop', last: 'Last active 5 minutes ago' },
    { id: 'd3', name: 'Galaxy Tab', platform: 'Android', icon: 'device-tablet', last: 'Last active 3 weeks ago' },
  ];

  // ---------------------------------------- link a new device (approving side)
  App.register({
    id: 'approve-device', title: 'Link a new device', group: 'Profile and devices', order: 70,
    entries: [
      { key: 'approve-device', label: 'Link a new device · scan', params: { step: 'enter' } },
      { key: 'approve-device-error', label: 'Link a new device · expired code', params: { step: 'enter', error: 'That code has expired. Codes last ten minutes. Ask the new device to show a new one.' } },
      { key: 'approve-device-review', label: 'Link a new device · approve?', params: { step: 'review' } },
      { key: 'approve-device-done', label: 'Link a new device · done', params: { step: 'done' } },
    ].map((e) => ({ ...e, base: [base, { screen: 'devices', params: {} }] })),
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, step: params.step, error: params.error, sent: false });
      let body;
      if (st.step === 'enter') {
        body = `${intro('', 'On the new device, open Orbit and choose to link it to an existing account. It will show a QR code. Scan it here.')}
          ${st.error ? notice('error', esc(st.error)) : ''}
          <div class="pad" style="display:flex;justify-content:center;margin-top:16px"><div class="scan-frame" style="width:100%;max-width:320px;height:250px"><span class="corner c1"></span><span class="corner c2"></span><span class="corner c3"></span><span class="corner c4"></span><span class="beam"></span></div></div>
          <div class="pad" style="margin-top:16px">${field({ id: 'lnk', label: 'Or paste the code', hint: 'helix-link:…', mono: true, helper: 'It starts with helix-link', paste: true })}
          <button class="btn primary block" data-continue>Continue</button></div>`;
      } else if (st.step === 'review' || st.step === 'approving') {
        body = `${intro('Approve this device?', `A device on <span class="mono">${esc(Data.me.host)}</span> is asking to join your account. Once approved it can read your new messages and can receive your history.`)}
          ${code('Check number', '72 914', { cls: 'huge' })}
          ${code('Your account key code', '4821 9930 1175')}
          ${notice('warning', 'Check that the new device shows the same numbers. Do not approve a device you are not holding. Nobody from Orbit will ever ask you to scan a code.')}
          <div class="btn-row" style="flex-direction:column"><button class="btn primary block" data-approve>${st.step === 'approving' ? '<i class="ph ph-spinner-gap spin"></i>' : icon('check', 'bold')}Approve</button><button class="btn secondary block" data-back>Cancel</button></div>`;
      } else {
        body = `${notice('success', 'The device is joining your account. It will show up in your device list in a moment, once its owner has confirmed the account.')}
          ${intro('Chat history', 'Your past messages are not on the new device yet. You can send them now; the new device asks before it accepts them.')}
          ${st.sent ? notice('success', 'Your history is on its way. The new device will ask to accept it under Settings, Backup.') : `<div class="btn-row"><button class="btn secondary block" data-send>${icon('paper-plane-tilt')}Send history to this device</button></div>`}
          <div class="btn-row"><button class="btn primary block" data-back>Done</button></div>`;
      }
      return Kit.page({ title: 'Link a new device', body });
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelector('[data-paste]')?.addEventListener('click', (e) => { e.preventDefault(); el.querySelector('#lnk').value = 'helix-link:v2:helix.agiletechbd.com:8QZK…'; });
      el.querySelector('[data-continue]')?.addEventListener('click', () => {
        const v = el.querySelector('#lnk').value.trim();
        if (v && !v.startsWith('helix-link')) { st.error = 'That is not a Orbit link code. Scan the code shown on the new device, or paste it exactly.'; entry.rerender(); return; }
        st.step = 'review'; st.error = null; entry.rerender();
      });
      el.querySelector('[data-approve]')?.addEventListener('click', () => {
        App.dialog({ title: 'Approve a new device for your Orbit account', text: `Confirm with ${UI.unlock().what}.`, actions: [{ label: 'Cancel' }, { label: UI.unlock().button, kind: 'primary', run: () => { st.step = 'approving'; entry.rerender(); setTimeout(() => { st.step = 'done'; if (entry.el.isConnected) entry.rerender(); }, 900); } }] });
      });
      el.querySelector('[data-send]')?.addEventListener('click', () => { st.sent = true; entry.rerender(); });
    },
  });

  // -------------------------------------------------------- security activity
  App.register({
    id: 'activity', title: 'Security activity', group: 'Profile and devices', order: 70,
    entries: [{ key: 'activity', label: 'Security activity', params: {}, base: [base, { screen: 'devices', params: {} }] }],
    render() {
      const ev = [
        ['sign-in', 'Signed in', 'Pixel 8', 'Today, 08:02'],
        ['device-mobile', 'A device was added', 'Office PC', 'Yesterday, 18:40'],
        ['password', 'Password changed', 'Pixel 8', '24 September'],
        ['key', 'Your account key was reset', 'Pixel 8', '2 September', true],
        ['x-circle', 'A device was removed', 'Old Redmi', '1 September'],
      ];
      return Kit.page({ title: 'Security activity', body: `<div style="height:14px"></div><div class="card">${ev.map(([ic, t, d, w, warn]) => row({ icon: warn ? 'warning' : ic, color: warn ? 5 : 7, title: t, sub: `${d} - ${w}`, tag: 'div', end: warn ? '<span class="tag danger">!</span>' : '' })).join('')}</div>` });
    },
    mount(el, params, entry) { wire(el, entry); },
  });

  App.register({
    id: 'restore-history', title: 'Restore history', group: 'Backup', order: 80,
    entries: [{ key: 'restore-history', label: 'Restore history (from Settings)', params: {}, base: [base, { screen: 'backup', params: {} }] }],
    render(params, entry) { return Kit.page({ title: 'Restore history', body: window.HelixRestorePage({}, entry.state) }); },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelector('[data-restore]')?.addEventListener('click', () => {
        st.phase = 'running'; st.p = 0; entry.rerender();
        const tick = () => { if (!entry.el.isConnected) return; st.p++; if (st.p > 3) st.phase = 'done'; entry.rerender(); if (st.phase === 'running') setTimeout(tick, 700); };
        setTimeout(tick, 700);
      });
      el.querySelector('[data-continue]')?.addEventListener('click', App.pop);
    },
  });

  // --------------------------------------------------------------- transfers
  function xfer(t) {
    const st = {
      preparing: ['Getting your history ready (3 of 8)', 0.35, [['Cancel', 'secondary']]],
      offered: ['Waiting for your other device to accept. It will appear there under Backup.', null, [['Cancel', 'secondary']]],
      ready: ['Ready to receive. Nothing is downloaded until you accept.', null, [['Accept', 'primary'], ['Decline', 'secondary']]],
      receiving: ['Receiving (5 of 8)', 0.62, [['Pause', 'secondary']]],
      done: ['Done', null, [['Dismiss', 'ghost']]],
    }[t.state];
    return `<div class="xfer"><div class="xf-title">${icon(t.out ? 'upload-simple' : 'download-simple', 'bold')}${esc(t.title)}</div><div class="xf-status">${st[0]}</div>${st[1] != null ? progress(st[1]) : ''}
      <div class="xf-actions">${st[2].map(([l, k]) => `<button class="btn ${k}" data-xf="${l}">${l}</button>`).join('')}</div></div>`;
  }
  App.register({
    id: 'transfer', title: 'Send to my other devices', group: 'Backup', order: 80,
    entries: [
      { key: 'transfer', label: 'Send to my other devices', params: {} },
      { key: 'transfer-empty', label: 'Send to my other devices · nothing waiting', params: { empty: true } },
    ].map((e) => ({ ...e, base: [base, { screen: 'backup', params: {} }] })),
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, out: params.empty ? [] : [{ out: true, title: 'Sending your history', state: 'offered' }], in: params.empty ? [] : [{ title: 'History from Office PC', state: 'ready' }] });
      return Kit.page({ title: 'Send to my other devices', body: `
        ${intro('', 'Your history is encrypted before it leaves this phone. The other device has to accept it, and files are not included.')}
        <div class="btn-row"><button class="btn primary block" data-send>${st.busy ? '<i class="ph ph-spinner-gap spin"></i>' : icon('paper-plane-tilt')}Send my history</button></div>
        ${st.out.map(xfer).join('')}
        <div class="group-title eyebrow">Waiting for this phone</div>
        ${st.in.length ? st.in.map(xfer).join('') : '<p class="sec-foot">Nothing is waiting. When another of your devices sends its history, it shows up here.</p>'}` });
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelector('[data-send]').addEventListener('click', () => { st.busy = true; entry.rerender(); setTimeout(() => { st.busy = false; st.out = [{ out: true, title: 'Sending your history', state: 'preparing' }]; entry.rerender(); }, 600); });
      el.querySelectorAll('[data-xf]').forEach((b) => b.addEventListener('click', () => {
        const a = b.dataset.xf;
        if (a === 'Accept') { st.in[0].state = 'receiving'; } else if (a === 'Decline' || a === 'Dismiss') { st.in = []; } else if (a === 'Pause') { App.snack('Paused'); return; } else if (a === 'Cancel') { st.out = []; }
        entry.rerender();
      }));
    },
  });

  // ---------------------------------------------------------- recovery backup
  App.register({
    id: 'recovery', title: 'Recovery backup', group: 'Backup', order: 80,
    entries: [
      { key: 'recovery', label: 'Recovery backup · create', params: { tab: 'create' } },
      { key: 'recovery-restore', label: 'Recovery backup · restore', params: { tab: 'restore' } },
    ].map((e) => ({ ...e, base: [base, { screen: 'backup', params: {} }] })),
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, tab: params.tab || 'create', saved: false, done: false });
      const secret = 'K7QM-X2PD-9WTR-4HNB-F6CZ-JY3V';
      const create = st.done
        ? `${notice('success', 'Recovery backup created.')}<p class="sec-foot" style="margin-top:12px">The secret is not stored anywhere on this phone or on the server. If you lose it, this backup cannot be opened.</p>`
        : `${intro('', 'Orbit made a secret for this backup. Save it somewhere away from this phone, like a password manager or on paper. It is shown only now.')}
          ${code('Recovery secret', secret, { cls: 'secret' })}
          <div class="btn-row"><button class="btn secondary" data-copy>${icon('copy')}Copy</button><button class="btn secondary" data-share>${icon('share-network')}Share</button></div>
          ${st.note ? `<p class="sec-foot">${st.note}</p>` : ''}
          <div class="pad" style="margin-top:8px">${check('I saved it', st.saved, 'data-saved')}</div>
          <div class="btn-row"><button class="btn primary block" data-create ${st.saved ? '' : 'disabled style="opacity:.5"'}>${icon('key')}Create recovery backup</button></div>`;
      const restore = `${intro('', 'Type the recovery secret exactly as you saved it, including the dashes.')}
        <div class="pad" style="margin-top:14px">${field({ id: 'rsec', label: 'Recovery secret', hint: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX', mono: true })}
        ${st.restored ? notice('success', 'Restored 2,318 messages.') : ''}
        <button class="btn primary block" style="margin-top:10px" data-rest>Restore from recovery backup</button></div>`;
      return Kit.page({ title: 'Recovery backup', body: `<div class="pad" style="margin-top:14px">${Kit.seg([['create', 'Create'], ['restore', 'Restore']], st.tab, 'data-tab2')}</div>
        ${st.tab === 'create' ? create : restore}
        <p class="sec-foot" style="text-align:center;margin-top:18px">Orbit cannot reset or recover a recovery secret.</p>` });
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelectorAll('[data-tab2]').forEach((b) => b.addEventListener('click', () => { st.tab = b.dataset.tab2; entry.rerender(); }));
      el.querySelector('[data-copy]')?.addEventListener('click', () => { st.note = 'Copied. Put it somewhere safe now: it leaves the clipboard in a minute.'; entry.rerender(); });
      el.querySelector('[data-share]')?.addEventListener('click', () => { st.note = 'Shared. Check that it reached somewhere only you can open.'; entry.rerender(); });
      el.querySelector('[data-saved]')?.addEventListener('toggle', (e) => { st.saved = e.detail; entry.rerender(); });
      el.querySelector('[data-create]')?.addEventListener('click', () => { st.done = true; if (window.HelixYouState) window.HelixYouState.recovery = true; entry.rerender(); });
      el.querySelector('[data-rest]')?.addEventListener('click', () => { if (!el.querySelector('#rsec').value.trim()) { App.snack('Type your recovery secret first.'); return; } st.restored = true; entry.rerender(); });
    },
  });
})();
