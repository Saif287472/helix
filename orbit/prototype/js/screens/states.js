/*
  The state kit's own pages (Phase 1b, 2026-10-18):
    - startup: "Opening Orbit…" while the database opens. Today the app shows
      the phone step for a moment instead (signin.md).
    - state-kit: every shared state drawn once, in the current theme, for
      review. The contracts point to these instead of drawing each case.
  Flutter: OrbitStartup; the parts are in kit.js.
*/
(() => {
  const { icon } = UI;

  App.register({
    id: 'startup', title: 'Opening Orbit', group: 'App', order: 94,
    interactions: [
      ['auto', 'Startup', 'Shows while the encrypted database opens, then goes to Chats, sign-in, the restore step or reset.'],
    ],
    entries: [{ key: 'startup', label: 'Opening Orbit (startup)', params: {} }],
    render() {
      return `<div class="startup" role="status" aria-label="Opening Orbit"><span class="su-mark" aria-hidden="true"></span><span class="su-text">Opening Orbit…</span>
        <div style="width:120px"><div class="prog indet" style="margin:0"><b></b></div></div></div>`;
    },
  });

  App.register({
    id: 'state-kit', title: 'State kit', group: 'Design system', order: 99,
    interactions: [
      ['tap', 'Show a toast / an error toast / a toast with Undo', 'Shows that toast.'],
      ['tap', 'Try again', 'Shows the loading state, then the content.'],
      ['tap', 'Allow / Open settings', 'Says which system screen opens.'],
    ],
    entries: [{ key: 'state-kit', label: 'State kit · every shared state', params: {} }],
    render(params, entry) {
      const st = entry.state;
      const L = (t) => `<div class="kit-label">${t}</div>`;
      return Kit.youPage('State kit', `
        <p class="sec-foot" style="margin-top:4px">How every screen draws loading, failure, empty lists, permissions and refusals. Screens use these instead of their own.</p>
        ${L('A list is loading')}<div class="kit-frame">${Kit.skeleton(3, 'chat', 'Loading chats')}</div>
        ${L('Rows and tiles are loading')}<div class="kit-frame">${Kit.skeleton(2, 'row', 'Loading')}${Kit.skeleton(1, 'tile', 'Loading')}</div>
        ${L('A page is opening')}<div class="kit-frame">${Kit.loading('Opening the conversation…')}</div>
        ${L('A page could not load')}<div class="kit-frame">${st.retrying ? Kit.skeleton(2, 'chat') : Kit.loadFailed('Your chats could not be loaded.')}</div>
        ${L('A list inside a page could not load')}<div class="card" style="margin-top:0">${Kit.loadFailed('Muted chats could not be loaded.', { compact: true, sub: '' })}</div>
        ${L('Nothing here yet')}<div class="kit-frame">${UI.empty({ icon: 'chats-circle', title: 'No chats yet', text: 'Search for a name or a number to start a conversation.' })}</div>
        ${L('Asking for a permission')}${Kit.permission('contacts', { text: 'To show which of your contacts use Orbit. Only scrambled numbers are checked; your contacts never leave this device.' })}
        ${L('After a refusal')}${Kit.permission('camera', { denied: true, text: 'Allow camera access in your phone’s settings to take photos and scan codes.' })}
        ${L('A field refusal and a lockout')}${Kit.formCard(`${Kit.field({ id: 'kpw', label: 'Current password', type: 'password', value: 'secret', error: 'That is not your current password.' })}${Kit.fieldLock('Too many tries. Try again in 15 minutes.')}`)}
        ${L('A notice on the page')}${Kit.notice('error', 'That was not saved. Check your connection and try again.')}${Kit.notice('info', 'Saved on this device. Your phone did not let Orbit change your contacts.')}
        ${L('Toasts')}<div class="btn-row" style="padding-top:4px"><button class="btn secondary" data-t="plain">Toast</button><button class="btn secondary" data-t="error">Error toast</button><button class="btn secondary" data-t="undo">With Undo</button></div>
        ${L('A button at work')}<div class="btn-row" style="padding-top:4px"><button class="btn primary"><i class="ph ph-spinner-gap spin"></i>Sending</button><button class="btn secondary" disabled>Not ready</button></div>
        <p class="sec-foot" style="margin-top:18px">Placeholder rows shimmer unless the system asks to reduce motion.</p>`, { back: false, keep: 'kit' });
    },
    mount(el, params, entry) {
      Kit.wire(el, null);
      el.querySelectorAll('[data-t]').forEach((b) => b.addEventListener('click', () => {
        if (b.dataset.t === 'plain') App.snack('Chat muted for 8 hours');
        if (b.dataset.t === 'error') App.snack('The message could not be sent. Check your connection.', null, { tone: 'error' });
        if (b.dataset.t === 'undo') App.snack('Chat archived', { label: 'Undo' });
      }));
      el.querySelector('[data-retry]')?.addEventListener('click', () => {
        entry.state.retrying = true; entry.rerender();
        setTimeout(() => { entry.state.retrying = false; if (entry.el.isConnected) entry.rerender(); }, 1200);
      });
    },
  });

  App.register({
    id: 'kit-primitives', title: 'Kit: primitives', group: 'Design system', order: 98,
    interactions: [
      ['tap', 'Icon button / button / FAB', 'Triggers action or ripples.'],
      ['tap', 'Switch row or standalone switch', 'Toggles the switch.'],
      ['tap', 'Checkbox', 'Ticks or unticks the checkbox.'],
      ['tap', 'Filter chip', 'Selects the chip.'],
    ],
    entries: [{ key: 'kit-primitives', label: 'Primitives · buttons, avatars, chips, toggles', params: {} }],
    render(params, entry) {
      const L = (t) => `<div class="kit-label">${t}</div>`;
      return Kit.youPage('Primitives', `
        <p class="sec-foot" style="margin-top:4px">Core primitive components: buttons, avatars, chips, tags, switches and checkboxes, and the theme's chat pattern.</p>

        ${L('Icon buttons')}
        <div class="kit-frame" style="padding:12px;display:flex;align-items:center;gap:12px;background:var(--surface)">
          ${UI.ibtn('bell', 'Mute')}
          ${UI.ibtn('magnifying-glass', 'Search', '', 'accent')}
          ${UI.ibtn('trash', 'Delete', '', 'danger')}
          ${UI.ibtn('eye', 'Show', '', 'sm')}
        </div>

        ${L('Buttons')}
        <div class="kit-frame" style="padding:14px;background:var(--surface);display:flex;flex-direction:column;gap:10px">
          <div style="display:flex;gap:8px;flex-wrap:wrap">
            <button class="btn primary">Primary</button>
            <button class="btn ink">Ink</button>
            <button class="btn secondary">Secondary</button>
            <button class="btn ghost">Ghost</button>
            <button class="btn danger">Danger</button>
          </div>
          <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
            <button class="btn primary"><i class="ph ph-spinner-gap spin"></i>Sending</button>
            <button class="btn secondary" disabled>Disabled</button>
            <button class="btn secondary"><i class="ph ph-plus"></i>With icon</button>
          </div>
        </div>

        ${L('Floating action button')}
        <div class="kit-frame" style="padding:14px;background:var(--surface);display:flex;align-items:center;gap:16px">
          <button class="fab" title="New chat" aria-label="New chat"><i class="ph ph-pencil-simple-line"></i></button>
        </div>

        ${L('Avatars')}
        <div class="kit-frame" style="padding:14px;background:var(--surface);display:flex;flex-direction:column;gap:12px">
          <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
            ${UI.avatar(Data.av(Data.people.nadia), 48, { online: true })}
            ${UI.avatar(Data.av(Data.people.arif), 48)}
            ${UI.avatar({ name: 'Family', seed: 'family', group: true }, 48)}
            ${UI.avatar(Data.av(Data.people.tanvir), 48, { check: true })}
          </div>
          <div style="display:flex;align-items:center;gap:10px">
            ${UI.avatar(Data.av(Data.people.nadia), 32)}
            ${UI.avatar(Data.av(Data.people.nadia), 40)}
            ${UI.avatar(Data.av(Data.people.nadia), 48)}
            ${UI.avatar(Data.av(Data.people.nadia), 56)}
          </div>
        </div>

        ${L('Chips and tags')}
        <div class="kit-frame" style="padding:14px;background:var(--surface);display:flex;flex-direction:column;gap:12px">
          <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
            <span class="chip on">All</span>
            <span class="chip">Unread<span class="chip-n">3</span></span>
            <span class="chip">Groups</span>
          </div>
          <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
            <span class="tag">Default</span>
            <span class="tag accent">E2E</span>
            <span class="tag success">Verified</span>
            <span class="tag warning">Expiring</span>
            <span class="tag danger">Revoked</span>
          </div>
        </div>

        ${L('Switches and checkboxes')}
        <div class="kit-frame" style="padding:14px;background:var(--surface);display:flex;flex-direction:column;gap:6px">
          <div style="display:flex;align-items:center;gap:10px">
            <div class="switch" role="switch" aria-checked="false" aria-label="Off" tabindex="0"></div>
            <div class="switch on" role="switch" aria-checked="true" aria-label="On" tabindex="0"></div>
          </div>
          ${Kit.check('Keep me signed in on this computer', false)}
          ${Kit.check('I have read the Terms', true)}
        </div>

        ${L('Chat pattern')}
        <div class="kit-frame"><div class="timeline" style="height:140px" aria-label="The theme's chat background"></div></div>
      `, { back: false, keep: 'kit-primitives' });
    },
    mount(el, params, entry) {
      Kit.wire(el, null);
      el.querySelectorAll('.switch').forEach((s) => s.addEventListener('click', () => {
        const on = !s.classList.contains('on');
        s.classList.toggle('on', on);
        s.setAttribute('aria-checked', String(on));
      }));
    },
  });

  App.register({
    id: 'kit-shell', title: 'Kit: shell', group: 'Design system', order: 98.5,
    interactions: [
      ['type', 'Search field', '× clears it.'],
      ['tap', 'Dock tab', 'Marks that tab.'],
    ],
    entries: [{ key: 'kit-shell', label: 'Shell · fields, notices, cards, bars, dock', params: {} }],
    render() {
      const L = (t) => `<div class="kit-label">${t}</div>`;
      const H = App.homeParts;
      const search = (value, hint) => `<header class="appbar" style="background:var(--bg);border-bottom:0">${UI.ibtn('arrow-left', 'Close search')}
        <div class="search" style="flex:1;margin:0 8px 0 0">${icon('magnifying-glass')}<input placeholder="${hint}" value="${value}" aria-label="${hint}" autocomplete="off">${value ? UI.ibtn('x', 'Clear search', 'data-search-clear', 'sm') : ''}</div></header>`;
      return Kit.youPage('Shell', `
        <p class="sec-foot" style="margin-top:4px">What pages are built from: fields, choices, notices, codes, cards of rows, the bars at the top and the dock at the bottom.</p>

        ${L('Search field')}
        <div class="kit-frame">${search('', 'Search chats, messages and people')}${search('Nadia', 'Search people')}</div>

        ${L('Text fields')}
        ${Kit.formCard(`${Kit.field({ id: 'ksName', label: 'Name', value: 'Hasan', max: 50, counter: true, hint: 'How people see you' })}
          ${Kit.field({ id: 'ksPhone', label: 'Phone number', prefix: '+880', value: '', hint: '1711 000001', inputmode: 'tel', helper: 'With its country code' })}
          ${Kit.field({ id: 'ksPass', label: 'Password', type: 'password', value: 'secret', eye: true })}
          ${Kit.field({ id: 'ksCode', label: 'Invite or recovery code', hint: 'HLX-INV-… or HLX-REC-…', mono: true, paste: true })}
          ${Kit.field({ id: 'ksDesc', label: 'Description', value: 'Family news and plans.', max: 500, multiline: true, rows: 3 })}
          ${Kit.field({ id: 'ksGroup', label: 'Group name', value: '', error: 'Enter a group name of 1 to 100 characters.', max: 100 })}`)}

        ${L('Segmented control')}
        <div class="pad">${Kit.seg([['create', 'Create'], ['restore', 'Restore']], 'create')}</div>
        <div class="pad" style="margin-top:10px">${Kit.seg([['terms', 'Terms', 'file-text'], ['privacy', 'Privacy', 'shield-check']], 'privacy')}</div>

        ${L('Notices')}
        ${Kit.notice('info', 'Saved on this device. Your phone did not let Orbit change your contacts.')}
        ${Kit.notice('success', 'Recovery backup created.')}
        ${Kit.notice('warning', 'Check that the new device shows the same number. Do not approve a device you are not holding.')}
        ${Kit.notice('error', 'That was not saved. Check your connection and try again.', { label: 'Try again' })}

        ${L('Banners')}
        <div class="banner accent">${icon('address-book', 'fill')}<div class="bn-body"><div class="bn-title">Find your contacts on Orbit</div>
          Orbit compares scrambled versions of your contacts’ numbers to find who is on Orbit. Your contacts never leave your phone.
          <div class="bn-actions"><button class="btn ghost">Allow contacts</button></div></div></div>
        <div class="banner warning">${icon('shield-warning', 'fill')}<div class="bn-body"><div class="bn-title">Safety number changed</div>Your safety number with Nadia Rahman changed. That usually means they got a new phone or reinstalled Orbit. It can also mean someone is interfering. Compare safety numbers with them to be sure.</div></div>

        ${L('Page intro and empty state')}
        <div class="kit-frame">${Kit.intro('Is this your account?', 'Your other device approved this one. Check that this is your account before Orbit gives this phone its keys.')}
          ${UI.empty({ icon: 'archive', title: 'All your chats are archived', text: 'They are kept in Archived chats, out of the way.', action: `<button class="btn secondary" style="margin-top:8px">${icon('archive')}Open archived chats</button>` })}</div>

        ${L('Codes')}
        ${Kit.code('Check number', '72 914', { cls: 'huge' })}
        <div class="card secret-card">${Kit.code('Shown only now', 'K7QD-M2XP-9RWA-H4TF-B8NC-3ZLE', { cls: 'secret', groups: true })}
          <div class="btn-row"><button class="btn secondary">${icon('copy')}Copy</button><button class="btn secondary">${icon('share-network')}Share</button></div></div>

        ${L('QR code')}
        <div class="qr-wrap"><div class="qr-card">${Kit.qr('safety-nadia', 200)}</div></div>

        ${L('Progress')}
        ${Kit.progress(0.4)}
        ${Kit.progress(null)}

        ${L('Section of rows')}
        ${Kit.section('', [
          UI.row({ icon: 'users-three', color: 0, title: 'Group info', sub: 'Members, invite links and group settings', end: 'chevron' }),
          UI.row({ icon: 'images', color: 2, title: 'Media, links and docs', end: 'chevron' }),
          UI.row({ icon: 'timer', color: 5, title: 'Disappearing messages', value: 'Off', end: 'chevron' }),
          UI.row({ icon: 'eraser', title: 'Clear chat', danger: true }),
        ])}
        ${Kit.section('Diagnostics', [Kit.sw('Send crash reports', 'Only the error’s type, the app version and the platform', true)], 'A crash report never contains messages, names, numbers or keys.')}
        ${Kit.danger([UI.row({ icon: 'sign-out', title: 'Sign out all other devices', danger: true })])}

        ${L('App bars')}
        <div class="kit-frame">${UI.appbar({ title: 'Message info' })}</div>
        <div class="kit-frame" style="margin-top:10px">${UI.appbar({ title: 'Join requests', actions: UI.ibtn('dots-three-vertical', 'More options') })}</div>
        <div class="kit-frame" style="margin-top:10px">${H.header(2)}</div>

        ${L('Tab header')}
        <div class="kit-frame">${H.header(0)}</div>

        ${L('Dock')}
        <div class="kit-frame"><div style="position:relative;height:120px">${H.dock('chats')}</div></div>
        <div class="kit-frame" style="margin-top:10px"><div style="position:relative;height:120px">${H.dock('calls')}</div></div>
      `, { back: false, keep: 'kit-shell' });
    },
    mount(el) {
      Kit.wire(el, null);
      el.querySelectorAll('.dock').forEach((d) => d.addEventListener('click', (e) => {
        const b = e.target.closest('.dock-item'); if (!b) return;
        d.querySelectorAll('.dock-item').forEach((x) => x.classList.toggle('on', x === b));
      }));
      el.querySelectorAll('[data-search-clear]').forEach((b) => b.addEventListener('click', () => {
        const s = b.closest('.search'); s.querySelector('input').value = ''; b.remove();
      }));
    },
  });
})();
