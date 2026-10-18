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
        ${L('A button at work')}<div class="btn-row" style="padding-top:4px"><button class="btn primary" disabled><i class="ph ph-spinner-gap spin"></i></button><button class="btn secondary" disabled>Not ready</button></div>
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
})();
