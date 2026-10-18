/*
  The pages under Devices and Backup, in the You style (2026-10-17): Link a
  new device, Security activity, Restore history, Send to my other devices,
  Recovery backup. Each opens on a summary card; flows show their steps
  (Kit.steps) and status rings (Kit.ring).
  Flutter: features/devices/presentation, features/backup/presentation.
*/
(() => {
  const { esc, icon, row } = UI;
  const { section, field, notice, code, progress, check, wire, youPage, hero, ring, steps, formCard } = Kit;
  const base = [{ screen: 'home', params: { tab: 'chats' } }, { screen: 'settings-page', params: {} }];

  // ---------------------------------------- link a new device (approving side)
  const LINK_STEPS = ['Scan', 'Check', 'Done'];
  App.register({
    id: 'approve-device', title: 'Link a new device', group: 'Profile and devices', order: 70,
    interactions: [
      ['type', 'Link code', 'Continue turns on once there is a code.'],
      ['tap', 'Paste', 'Pastes the link code.'],
      ['tap', 'Continue', 'Checks the code: an error if it is not an Orbit link code, otherwise the approve step.'],
      ['tap', 'Approve', 'Asks for your fingerprint, face or PIN (Windows Hello on Windows), then Approving, then Done.'],
      ['tap', 'Send (history)', 'Sends your history to the new device; the row turns to Sent.'],
      ['tap', 'Cancel / Done', 'Goes back.'],
    ],
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
        body = `${hero({ ic: 'qr-code', title: 'Scan the new device', sub: 'Its code lasts ten minutes',
          slot: `${steps(LINK_STEPS, 0)}<div class="hero-scan"><div class="scan-frame"><span class="corner c1"></span><span class="corner c2"></span><span class="corner c3"></span><span class="corner c4"></span><span class="beam"></span></div></div>` })}
          ${st.error ? notice('error', esc(st.error)) : ''}
          <div class="group-title eyebrow">Or paste the code</div>
          ${formCard(field({ id: 'lnk', label: 'Link code', hint: 'helix-link:…', mono: true, helper: 'It starts with helix-link', paste: true }))}
          <div class="btn-row"><button class="btn primary block" data-continue disabled>Continue</button></div>
          <p class="sec-foot">On the new device, open Orbit and choose to link it to an existing account. It shows a QR code. Nobody from Orbit will ever ask you to scan one.</p>`;
      } else if (st.step === 'review' || st.step === 'approving') {
        body = `${hero({ ic: 'devices', title: 'Approve this device?', sub: `A device on ${esc(Data.me.host)} wants to join`,
          slot: `${steps(LINK_STEPS, 1)}${code('Check number', '72 914', { cls: 'huge' })}` })}
          ${notice('warning', 'Check that the new device shows the same number. Do not approve a device you are not holding.')}
          <p class="sec-foot">Once approved it can read your new messages and can receive your history. The new device then shows your account key code to check.</p>
          <div class="btn-row" style="flex-direction:column"><button class="btn primary block" data-approve>${st.step === 'approving' ? '<i class="ph ph-spinner-gap spin"></i>' : icon('check', 'bold')}Approve</button><button class="btn secondary block" data-back>Cancel</button></div>`;
      } else {
        body = `${hero({ art: ring('ok'), title: 'The device is joining', sub: 'It shows in your list once its owner confirms the account', slot: steps(LINK_STEPS, 3) })}
          ${section('Chat history', [row({ icon: 'paper-plane-tilt', color: 0, title: st.sent ? 'History on its way' : 'Send your history to it', sub: st.sent ? 'The new device asks to accept it under You, Backup' : 'Your past messages are not on the new device yet', end: st.sent ? `<span class="tag success">${icon('check', 'bold')}Sent</span>` : '<button class="btn secondary" style="height:38px" data-send>Send</button>', tag: 'div' })], 'The new device asks before it accepts your history.')}
          <div class="btn-row"><button class="btn primary block" data-back>Done</button></div>`;
      }
      return youPage('Link a new device', body);
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      const lnk = el.querySelector('#lnk'); const cont = el.querySelector('[data-continue]');
      lnk?.addEventListener('input', () => { cont.disabled = !lnk.value.trim(); });
      el.querySelector('[data-paste]')?.addEventListener('click', (e) => { e.preventDefault(); lnk.value = 'helix-link:v2:helix.agiletechbd.com:8QZK…'; cont.disabled = false; });
      el.querySelector('[data-continue]')?.addEventListener('click', () => {
        const v = el.querySelector('#lnk').value.trim();
        if (v && !v.startsWith('helix-link')) { st.error = 'That is not an Orbit link code. Scan the code shown on the new device, or paste it exactly.'; entry.rerender(); return; }
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
    interactions: [
      ['tap', 'Review your devices', 'Opens Devices.'],
      ['tap', 'Change your password', 'Opens Change password.'],
    ],
    entries: [{ key: 'activity', label: 'Security activity', params: {}, base: [base, { screen: 'devices', params: {} }] }],
    render() {
      const ev = (ic, t, d, w, warn) => row({ icon: warn ? 'warning' : ic, color: warn ? 4 : 7, title: t, sub: `${d} · ${w}`, tag: 'div', end: warn ? '<span class="tag warning">Check</span>' : '' });
      return youPage('Security activity', `
        ${hero({ ic: 'shield-check', title: 'Security activity', sub: '5 recent events', pills: [{ icon: 'warning', text: '1 to check', tone: 'warn' }, { icon: 'devices', text: '2 devices now' }] })}
        ${section('This week', [ev('sign-in', 'Signed in', 'Pixel 8', 'Today, 08:02'), ev('device-mobile', 'A device was added', 'Office PC', 'Yesterday, 18:40')])}
        ${section('Earlier', [ev('password', 'Password changed', 'Pixel 8', '24 September'), ev('key', 'Your account key was reset', 'Pixel 8', '2 September', true), ev('x-circle', 'A device was removed', 'Old Redmi', '1 September')], 'Your account’s sign-ins, devices and key changes. Nothing here includes your messages.')}
        ${section('Something you do not recognise?', [
          row({ icon: 'devices', color: 0, title: 'Review your devices', sub: 'Remove any you do not know', end: 'chevron', attrs: 'data-go="devices"' }),
          row({ icon: 'password', color: 1, title: 'Change your password', end: 'chevron', attrs: 'data-go="password"' }),
        ])}`);
    },
    mount(el, params, entry) { wire(el, entry); },
  });

  App.register({
    id: 'restore-history', title: 'Restore history', group: 'Backup', order: 80,
    interactions: [
      ['tap', 'Restore from my backup', 'Runs: looking, downloading, unlocking, adding messages, with a percentage; then done, or nothing found.'],
      ['tap', 'I have a recovery secret', 'Opens Recovery backup on Restore.'],
      ['tap', 'Done', 'Goes back.'],
    ],
    entries: [{ key: 'restore-history', label: 'Restore history (from Settings)', params: {}, base: [base, { screen: 'backup', params: {} }] }],
    render(params, entry) { return youPage('Restore history', window.HelixRestorePage({}, entry.state)); },
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
      offered: ['Sent. Your other device chooses whether to add it; it shows there under Backup.', null, [['Cancel', 'secondary']]],
      declined: ['Your other device declined it.', null, [['Dismiss', 'ghost']]],
      stopped: ['Stopped: the connection dropped.', 0.4, [['Resume', 'primary'], ['Cancel', 'secondary']]],
      ready: ['Ready to receive. Nothing is downloaded until you accept.', null, [['Accept', 'primary'], ['Decline', 'secondary']]],
      receiving: ['Receiving (5 of 8)', 0.62, [['Pause', 'secondary']]],
      done: ['Done', null, [['Dismiss', 'ghost']]],
    }[t.state];
    return `<div class="xfer" data-out="${t.out ? 1 : 0}"><div class="xf-title">${icon(t.out ? 'upload-simple' : 'download-simple', 'bold')}${esc(t.title)}</div><div class="xf-status">${st[0]}</div>${st[1] != null ? progress(st[1]) : ''}
      <div class="xf-actions">${st[2].map(([l, k]) => `<button class="btn ${k}" data-xf="${l}">${l}</button>`).join('')}</div></div>`;
  }
  App.register({
    id: 'transfer', title: 'Send to my other devices', group: 'Backup', order: 80,
    interactions: [
      ['tap', 'Resume (stopped) / Dismiss (declined)', 'Continues receiving, or clears the card.'],
      ['tap', 'Send my history', 'A sending card appears and shows its progress.'],
      ['tap', 'Cancel (sending)', 'Stops sending.'],
      ['tap', 'Accept / Decline (waiting here)', 'Accept starts receiving with progress; Decline removes it.'],
      ['tap', 'Pause / Dismiss', 'Pauses receiving, or clears a finished transfer.'],
    ],
    entries: [
      { key: 'transfer', label: 'Send to my other devices', params: {} },
      { key: 'transfer-empty', label: 'Send to my other devices · nothing waiting', params: { empty: true } },
      { key: 'transfer-stopped', label: 'Send to my other devices · stopped, and declined', params: { stopped: true } },
      { key: 'transfer-only-device', label: 'Send to my other devices · this is your only device', params: { empty: true, only: true } },
    ].map((e) => ({ ...e, base: [base, { screen: 'backup', params: {} }] })),
    render(params, entry) {
      const st = entry.state;
      if (!st.init) {
        Object.assign(st, { init: true, out: params.empty ? [] : [{ out: true, title: 'Sending your history', state: 'offered' }], in: params.empty ? [] : [{ title: 'History from Office PC', state: 'ready' }] });
        if (params.stopped) { st.out = [{ out: true, title: 'Sending your history', state: 'declined' }]; st.in = [{ title: 'History from Office PC', state: 'stopped' }]; }
        if (params.only) st.error = 'This is your only device. Link another device first, then send your history to it.';
      }
      const waiting = st.in.filter((t) => t.state === 'ready').length;
      return youPage('Send to my other devices', `
        ${hero({ ic: 'devices', title: 'Send your history', sub: 'To your own devices only',
          pills: [{ icon: 'lock-simple', text: 'Encrypted on this phone' }, { icon: 'hand-pointing', text: 'Your other device chooses' }, ...(waiting ? [{ icon: 'download-simple', text: `${waiting} waiting here`, tone: 'accent' }] : [])] })}
        <div class="btn-row"><button class="btn primary block" data-send>${st.busy ? '<i class="ph ph-spinner-gap spin"></i>' : icon('paper-plane-tilt')}Send my history</button></div>
        ${st.error ? `<div class="si-error" style="margin:10px var(--gutter) 0">${icon('warning-circle', 'fill')}<span>${esc(st.error)}</span></div>` : ''}
        <p class="sec-foot">Files are not included. Your history is sent encrypted, and your other device chooses whether to add it.</p>
        ${st.out.length ? `<div class="group-title eyebrow">Sending</div>${st.out.map(xfer).join('')}` : ''}
        <div class="group-title eyebrow">Waiting for this phone</div>
        ${st.in.length ? st.in.map(xfer).join('') : '<p class="sec-foot" style="margin-top:0">Nothing is waiting. When another of your devices sends its history, it shows up here.</p>'}`);
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelector('[data-send]').addEventListener('click', () => { st.busy = true; entry.rerender(); setTimeout(() => { st.busy = false; st.out = [{ out: true, title: 'Sending your history', state: 'preparing' }]; if (entry.el.isConnected) entry.rerender(); }, 600); });
      el.querySelectorAll('[data-xf]').forEach((b) => b.addEventListener('click', () => {
        const a = b.dataset.xf;
        const card = b.closest('.xfer'); const outgoing = !!card && card.dataset.out === '1';
        if (a === 'Accept') { st.in[0].state = 'receiving'; } else if (a === 'Resume') { st.in[0].state = 'receiving'; } else if (a === 'Decline' || a === 'Dismiss') { if (outgoing) st.out = []; else st.in = []; } else if (a === 'Pause') { App.snack('Paused'); return; } else if (a === 'Cancel') { if (outgoing) st.out = []; else st.in = []; }
        entry.rerender();
      }));
    },
  });

  // ---------------------------------------------------------- recovery backup
  const REC_STEPS = ['Save the secret', 'Confirm', 'Create'];
  App.register({
    id: 'recovery', title: 'Recovery backup', group: 'Backup', order: 80,
    interactions: [
      ['auto', 'A recovery backup already exists', 'Warns that a new one replaces it and the saved secret stops working.'],
      ['tap', 'Delete my recovery backup (danger zone)', 'Asks first, then deletes it; the saved secret stops working.'],
      ['tap', 'Create / Restore', 'Switches the tab.'],
      ['tap', 'Copy / Share', 'Copies or shares the secret; step 1 is ticked and a note says what to do next.'],
      ['tap', 'I saved it somewhere safe', 'Turns on the Create button.'],
      ['tap', 'Create recovery backup', 'Creates it; the checkup item is fixed.'],
      ['tap', 'Restore from recovery backup', 'Restores; with an empty field it asks for the secret first.'],
    ],
    entries: [
      { key: 'recovery', label: 'Recovery backup · create', params: { tab: 'create' } },
      { key: 'recovery-restore', label: 'Recovery backup · restore', params: { tab: 'restore' } },
      { key: 'recovery-made', label: 'Recovery backup · one already made', params: { tab: 'create', made: true } },
    ].map((e) => ({ ...e, base: [base, { screen: 'backup', params: {} }] })),
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, tab: params.tab || 'create', saved: false, done: false });
      const made = st.done || params.made || (window.HelixYouState && window.HelixYouState.recovery);
      const replacing = made && !st.done;
      const secret = 'K7QM-X2PD-9WTR-4HNB-F6CZ-JY3V';
      const at = st.done ? 3 : st.saved ? 2 : st.note ? 1 : 0;
      const create = st.done
        ? `${notice('success', 'Recovery backup created.')}<p class="sec-foot">The secret is not stored anywhere on this phone or on the server. If you lose it, this backup cannot be opened.</p>`
        : `${replacing ? notice('warning', 'You already have a recovery backup. Making a new one replaces it, and the secret you saved stops working.') : ''}<div class="group-title eyebrow">Your recovery secret</div>
          <div class="card secret-card">${code('Shown only now', secret, { cls: 'secret', groups: true })}
            <div class="btn-row"><button class="btn secondary" data-copy>${icon('copy')}Copy</button><button class="btn secondary" data-share>${icon('share-network')}Share</button></div></div>
          <p class="sec-foot">${st.note || 'Save it away from this phone, like in a password manager or on paper.'}</p>
          ${formCard(check('I saved it somewhere safe', st.saved, 'data-saved'))}
          <div class="btn-row"><button class="btn primary block" data-create ${st.saved ? '' : 'disabled'}>${icon('key')}Create recovery backup</button></div>`;
      const restore = `<div class="group-title eyebrow">Restore</div>
        ${formCard(field({ id: 'rsec', label: 'Recovery secret', hint: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX', mono: true, helper: 'Exactly as you saved it, with the dashes' }))}
        ${st.restored ? notice('success', 'Restored 2,318 messages.') : ''}
        <div class="btn-row"><button class="btn primary block" data-rest>Restore from recovery backup</button></div>`;
      return youPage('Recovery backup', `
        ${hero({ ic: 'key', title: 'Recovery backup', sub: 'For when you lose every device',
          pills: [made ? { icon: 'check-circle', text: 'Made today', tone: 'ok' } : { icon: 'warning-circle', text: 'Not made yet', tone: 'warn' }, { icon: 'lock-simple', text: 'Only your secret opens it' }],
          slot: st.tab === 'create' ? steps(REC_STEPS, at) : '' })}
        <div class="pad" style="margin-top:14px">${Kit.seg([['create', 'Create'], ['restore', 'Restore']], st.tab, 'data-tab2')}</div>
        ${st.tab === 'create' ? create : restore}
        <p class="sec-foot" style="text-align:center;margin-top:18px">Orbit cannot reset or recover a recovery secret.</p>
        ${made ? Kit.danger([row({ icon: 'trash', title: 'Delete my recovery backup', sub: 'The secret you saved stops working', danger: true, attrs: 'data-delete-rec' })]) : ''}`);
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelectorAll('[data-tab2]').forEach((b) => b.addEventListener('click', () => { st.tab = b.dataset.tab2; entry.rerender(); }));
      el.querySelector('[data-copy]')?.addEventListener('click', () => { st.note = 'Copied. Put it somewhere safe now: it leaves the clipboard in a minute.'; entry.rerender(); });
      el.querySelector('[data-share]')?.addEventListener('click', () => { st.note = 'Shared. Check that it reached somewhere only you can open.'; entry.rerender(); });
      el.querySelector('[data-saved]')?.addEventListener('toggle', (e) => { st.saved = e.detail; entry.rerender(); });
      el.querySelector('[data-create]')?.addEventListener('click', () => { st.done = true; if (window.HelixYouState) window.HelixYouState.recovery = true; entry.rerender(); });
      el.querySelector('[data-delete-rec]')?.addEventListener('click', () => Kit.confirm('Delete your recovery backup?', 'The secret you saved stops working. Your chats on your devices are not affected.', 'Delete', () => { if (window.HelixYouState) window.HelixYouState.recovery = false; st.done = false; App.replace('recovery', { tab: 'create' }); App.snack('Recovery backup deleted'); }));
      el.querySelector('[data-rest]')?.addEventListener('click', () => { if (!el.querySelector('#rsec').value.trim()) { App.snack('Type your recovery secret first.'); return; } st.restored = true; entry.rerender(); });
    },
  });
})();
