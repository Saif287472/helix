/*
  People: the people search page (/home/people), contact info
  (/home/people/:id), safety number and scan. Flutter: PeopleSearchScreen,
  ContactInfoScreen, SafetyNumberScreen, SafetyScanScreen. Copy from SCREENS.md.
*/
(() => {
  const { esc, icon, ibtn, avatar, row } = UI;
  const { section, sw, intro, notice, qr, wire, confirm, inputDialog } = Kit;
  const TRUST = { nadia: 'verified', rafiq: 'keyChanged', sadia: 'noKey' };
  const trustOf = (id) => TRUST[id] || 'unverified';
  const COMMON = { ammu: ['group:family'], abbu: ['group:family'], rumana: ['group:family'], karim: ['group:family'], sadia: ['group:design', 'group:studio'], tanvir: ['group:design', 'group:studio', 'group:lunch'], arif: ['group:design', 'group:lunch'], nadia: ['group:design'] };
  const chatTitle = (cid) => (Data.chats.find((c) => c.id === cid) || {}).title || 'Group';
  const DIGITS = '37201 84619 05532 77148 26093 51870 94426 13085 60317 48852 29714 06639'.split(' ');

  function keyBanner(p, review) {
    const n = Data.displayName(p);
    return `<div class="banner warning" style="margin-top:14px">${icon('shield-warning', 'fill')}<div class="bn-body"><div class="bn-title">Safety number changed</div>Your safety number with ${esc(n)} changed. That usually means they got a new phone or reinstalled Orbit. It can also mean someone is interfering. Compare safety numbers with them to be sure.${review ? `<div class="bn-actions"><button class="btn ghost" data-go="safety" data-params='{"id":"${p.id}"}'>Review</button></div>` : ''}</div></div>`;
  }

  // ------------------------------------------------------------ contact info
  App.register({
    id: 'contact', title: 'Contact info', group: 'People', order: 40,
    interactions: [
      ['tap', 'Message / Voice call / Video call', 'Opens the chat or places the call.'],
      ['tap', 'Rename', 'Dialog for a name only you see; then asks to save it in the phone’s contacts too.'],
      ['tap', 'Mute', 'Switch on: sheet with 8 hours, 1 week, Always. Off: unmutes.'],
      ['tap', 'Disappearing messages', 'Sheet: Off, 24 hours, 7 days, 90 days.'],
      ['tap', 'Safety number', 'Opens it; says to send a message first when there is no key yet.'],
      ['tap', 'Group in common', 'Opens that group chat.'],
      ['tap', 'Block / Unblock', 'Block asks first (Orbit tells them); unblock happens at once.'],
      ['tap', 'Report', 'Sheet of reasons, then an optional note, then Reported.'],
    ],
    entries: [
      { key: 'contact', label: 'Contact info', params: { id: 'nadia' } },
      { key: 'contact-keychanged', label: 'Contact info · safety number changed', params: { id: 'rafiq' } },
      { key: 'contact-nokey', label: 'Contact info · no safety number yet', params: { id: 'sadia' } },
      { key: 'contact-blocked', label: 'Contact info · blocked', params: { id: 'shuvo' } },
      { key: 'contact-number', label: 'Contact info · known only by number', params: { id: 'unknown' } },
    ].map((e) => ({ ...e, base: [{ screen: 'home', params: { tab: 'chats' } }, { screen: 'chat', params: { id: `direct:${e.params.id}` } }] })),
    render(params, entry) {
      const p = Data.people[params.id] || Data.people.nadia;
      const st = entry.state;
      if (!st.init) Object.assign(st, { init: true, blocked: !!p.blocked, muted: p.id === 'karim', disappearing: p.id === 'nadia' ? '7 days' : 'Off', nickname: p.names.nickname || '' });
      const n = Data.displayName(p);
      const trust = trustOf(p.id);
      const trustSub = { verified: `<span style="color:var(--success)">${icon('seal-check', 'fill')} Verified</span>`, keyChanged: `<span style="color:var(--warning)">${icon('warning', 'fill')} Safety number changed</span>`, unverified: 'Not verified', noKey: 'Available after your first message' }[trust];
      const common = COMMON[p.id] || [];
      const hasNumber = !!p.names.number;
      const body = `
        <div class="hero">${avatar(Data.av(p), 112)}<div class="h-name">${esc(n)}${trust === 'verified' ? '<i class="ph-fill ph-seal-check seal" title="Verified"></i>' : ''}</div>
          <div class="h-sub">${esc(Data.secondary(p) || '')}</div>
          ${st.blocked ? '<div style="color:var(--danger);font-weight:600;font-size:13.5px;margin-top:4px">Blocked</div>' : ''}
          ${p.about ? `<div class="h-about">${esc(p.about)}</div>` : ''}</div>
        <div class="tiles">
          <button class="tile" data-msg>${icon('chat-circle')}Message</button>
          <button class="tile" data-voice>${icon('phone')}Voice call</button>
          <button class="tile" data-video>${icon('video-camera')}Video call</button></div>
        ${trust === 'keyChanged' ? keyBanner(p, true) : ''}
        ${section('Name', [
          row({ icon: 'pencil-simple', color: 0, title: 'Rename', sub: st.nickname ? esc(st.nickname) : 'Choose a name only you see', end: 'chevron', attrs: 'data-rename' }),
          ...(hasNumber ? [row({ icon: 'phone', color: 3, title: `<span class="mono">${esc(p.names.number)}</span>`, sub: 'Phone number', tag: 'div' })] : []),
          ...(p.names.helixName ? [row({ icon: 'at', color: 1, title: `~${esc(p.names.helixName)}`, sub: 'Orbit name', tag: 'div' })] : []),
        ], hasNumber ? 'Renaming also saves the name in your phone’s contacts.' : '')}
        ${section('Chat', [
          row({ icon: 'images', color: 2, title: 'Media, links and docs', end: 'chevron', attrs: `data-go="shared" data-params='{"id":"direct:${p.id}"}'` }),
          row({ icon: 'bell-slash', color: 4, title: 'Mute notifications', sub: st.muted ? 'Always' : '', end: 'switch', on: st.muted, attrs: 'data-switch data-mute' }),
          row({ icon: 'timer', color: 5, title: 'Disappearing messages', value: st.disappearing, end: 'chevron', attrs: 'data-disappear' }),
        ])}
        ${section('Encryption', [row({ icon: 'shield-check', color: 3, title: 'Verify safety number', sub: trustSub, end: 'chevron', attrs: 'data-safety' })], `Messages and calls with ${esc(n)} are end-to-end encrypted. Only the two of you can read them.`)}
        ${common.length ? section(common.length === 1 ? '1 group in common' : `${common.length} groups in common`, common.map((cid) => row({ icon: 'users-three', color: 0, weight: 'fill', title: esc(chatTitle(cid)), end: 'chevron', attrs: `data-open-chat="${cid}"` }))) : ''}
        ${section('', [
          st.blocked ? row({ icon: 'prohibit', title: `Unblock ${esc(n)}`, attrs: 'data-block' }) : row({ icon: 'prohibit', title: `Block ${esc(n)}`, danger: true, attrs: 'data-block' }),
          row({ icon: 'flag', title: `Report ${esc(n)}`, danger: true, attrs: 'data-report' }),
        ])}`;
      return Kit.page({ title: 'Contact info', body });
    },
    mount(el, params, entry) {
      const p = Data.people[params.id] || Data.people.nadia; const n = Data.displayName(p);
      const st = entry.state; const rerender = () => entry.rerender();
      wire(el, entry);
      el.querySelector('[data-msg]').addEventListener('click', () => App.push('chat', { id: `direct:${p.id}` }));
      el.querySelector('[data-voice]').addEventListener('click', () => App.push('call', { peer: p.id, phase: 'outgoing' }));
      el.querySelector('[data-video]').addEventListener('click', () => App.push('call', { peer: p.id, phase: 'outgoing', video: true }));
      el.querySelector('[data-rename]').addEventListener('click', () => inputDialog({ title: 'Rename', label: 'Name', value: st.nickname || n, max: 60, run: (v) => {
        st.nickname = v.trim(); rerender();
        if (p.names.number) App.dialog({ title: 'Save in your phone contacts too?', text: 'Orbit needs permission to change your contacts to keep this name there as well.', actions: [{ label: 'Not now', run: () => App.snack('Saved.') }, { label: 'Allow', kind: 'primary', run: () => App.snack('Saved, and updated in your contacts.') }] });
        else App.snack('Saved.');
      } }));
      el.querySelector('[data-mute]').addEventListener('toggle', (e) => {
        if (e.detail) App.sheet({ title: 'Mute notifications', items: ['8 hours', '1 week', 'Always'].map((o) => ({ icon: 'bell-slash', label: o, run: () => { st.muted = true; rerender(); } })), onClose: () => { if (!st.muted) rerender(); } });
        else { st.muted = false; rerender(); }
      });
      el.querySelector('[data-disappear]').addEventListener('click', () => App.sheet({
        title: 'Disappearing messages', text: 'New messages in this chat are deleted from both phones after the time you choose. Earlier messages are not changed.',
        items: ['Off', '24 hours', '7 days', '90 days'].map((o) => ({ icon: 'timer', label: o, on: st.disappearing === o, run: () => { st.disappearing = o; rerender(); } })),
      }));
      el.querySelector('[data-safety]').addEventListener('click', () => (trustOf(p.id) === 'noKey' ? App.snack('Send a message first. A safety number needs both of your keys.') : App.push('safety', { id: p.id })));
      el.querySelectorAll('[data-open-chat]').forEach((b) => b.addEventListener('click', () => App.push('chat', { id: b.dataset.openChat })));
      el.querySelector('[data-block]').addEventListener('click', () => {
        if (st.blocked) { st.blocked = false; rerender(); App.snack('Unblocked.'); return; }
        App.dialog({ title: `Block ${n}?`, text: 'They will not be able to message or call you. Orbit tells them that you blocked them.', actions: [{ label: 'Cancel' }, { label: 'Block', kind: 'primary', run: () => { st.blocked = true; rerender(); App.snack('Blocked.'); } }] });
      });
      el.querySelector('[data-report]').addEventListener('click', () => App.sheet({
        title: `Report ${n}`, text: 'Orbit only learns who you reported and why. No messages are sent with the report.',
        items: ['Spam', 'Abuse or harassment', 'Pretending to be someone else', 'Something else'].map((o) => ({ icon: 'flag', label: o, run: () => inputDialog({ title: 'Add a note (optional)', label: 'What happened?', max: 500, confirmLabel: 'Report', run: () => App.snack('Reported. No messages were sent with the report.') }) })),
      }));
    },
  });

  // ----------------------------------------------------------- safety number
  App.register({
    id: 'safety', title: 'Safety number', group: 'People', order: 40,
    interactions: [
      ['tap', 'Scan their code', 'Opens the scanner.'],
      ['tap', 'Mark as verified / not verified', 'Toggles the verified mark.'],
    ],
    entries: [
      { key: 'safety', label: 'Safety number · verified', params: { id: 'nadia' } },
      { key: 'safety-unverified', label: 'Safety number · not verified', params: { id: 'arif' } },
      { key: 'safety-changed', label: 'Safety number · changed', params: { id: 'rafiq' } },
      { key: 'safety-none', label: 'Safety number · none yet', params: { id: 'sadia' } },
    ].map((e) => ({ ...e, base: [{ screen: 'home', params: { tab: 'chats' } }, { screen: 'contact', params: { id: e.params.id } }] })),
    render(params, entry) {
      const p = Data.people[params.id] || Data.people.nadia; const n = Data.displayName(p);
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, verified: trustOf(p.id) === 'verified' });
      if (trustOf(p.id) === 'noKey') return Kit.page({ title: 'Safety number', body: UI.empty({ icon: 'shield', title: 'No safety number yet', text: 'Send a message first. A safety number needs both of your keys.' }) });
      const body = `${trustOf(p.id) === 'keyChanged' && !st.verified ? keyBanner(p, false) : ''}
        <div class="qr-wrap"><div class="qr-card">${qr(`safety-${p.id}`, 200)}</div></div>
        <div class="safety">${DIGITS.map((d) => `<span>${d}</span>`).join('')}${st.verified ? `<span class="sf-verified">${icon('shield-check', 'fill')}Verified</span>` : ''}</div>
        <p class="sec-foot" style="font-size:13px;margin-top:14px">To check that your chat with ${esc(n)} is private, compare this number with the one on their phone, or scan their QR code. If they match, nobody can be listening in.</p>
        <div class="btn-row" style="flex-direction:column"><button class="btn primary block" data-go="scan" data-params='{"id":"${p.id}"}'>${icon('qr-code')}Scan their code</button>
        <button class="btn secondary block" data-toggle-verified>${st.verified ? 'Mark as not verified' : 'Mark as verified'}</button></div>`;
      return Kit.page({ title: 'Safety number', body });
    },
    mount(el, params, entry) {
      wire(el, entry);
      el.querySelector('[data-toggle-verified]')?.addEventListener('click', () => { entry.state.verified = !entry.state.verified; entry.rerender(); });
    },
  });

  App.register({
    id: 'scan', title: 'Scan code', group: 'People', order: 40, night: true,
    interactions: [
      ['auto', 'Camera', 'Scans a code held in the frame.'],
      ['tap', 'Simulate a match / a mismatch (prototype only)', 'Match: verified, back to the safety number. Mismatch: explains.'],
    ],
    entries: [
      { key: 'scan', label: 'Scan code', params: { id: 'arif' } },
      { key: 'scan-nocamera', label: 'Scan code · no camera', params: { id: 'arif', noCamera: true } },
      { key: 'scan-contact', label: 'Scan someone’s Orbit code', params: { id: 'arif', mode: 'contact' } },
    ].map((e) => ({ ...e, base: [{ screen: 'home', params: { tab: 'chats' } }, { screen: 'safety', params: { id: 'arif' } }] })),
    render(params) {
      const head = `<header class="appbar" style="background:#06080F;border-bottom:0;color:#fff">${ibtn('arrow-left', 'Back', 'data-back')}<div class="ab-title"><h1>Scan code</h1></div></header>`;
      if (params.noCamera) return `${head}<div class="scanner"><div class="sc-hint">${icon('camera-slash')}<br>This device has no camera to scan with. Compare the numbers on both phones instead.</div></div>`;
      return `${head}<div class="scanner"><div class="scan-frame"><span class="corner c1"></span><span class="corner c2"></span><span class="corner c3"></span><span class="corner c4"></span><span class="beam"></span></div>
        <div class="sc-hint">${params.mode === 'contact' ? 'Point the camera at someone’s Orbit code to start a chat' : 'Point the camera at the code on their phone'}</div>
        <div style="display:flex;gap:10px"><button class="btn secondary" data-match style="background:#1B2236;border-color:#2B3550;color:#fff">Simulate a match</button><button class="btn secondary" data-mismatch style="background:#1B2236;border-color:#2B3550;color:#fff">Simulate a mismatch</button></div></div>`;
    },
    mount(el) {
      el.querySelector('[data-back]').addEventListener('click', App.pop);
      el.querySelectorAll('.appbar .ibtn').forEach((b) => { b.style.color = '#fff'; });
      el.querySelector('[data-match]')?.addEventListener('click', () => { App.pop(); App.snack('Verified. Your chat is private.'); });
      el.querySelector('[data-mismatch]')?.addEventListener('click', () => App.dialog({ title: 'That code does not match', text: 'The code on their phone is not the one Orbit expects for this chat. Make sure you scanned the right person’s code, and compare the numbers instead if you are unsure.', actions: [{ label: 'OK', kind: 'primary' }] }));
    },
  });

  // ------------------------------------------------- people search (own page)
  App.register({
    id: 'people', title: 'People', group: 'People', order: 40,
    interactions: [
      ['type', 'Search', 'Filters people as you type.'],
      ['tap', 'Person', 'Opens a chat with them.'],
    ],
    entries: [{ key: 'people', label: 'People search (from a contact link)', params: {}, base: { screen: 'home', params: { tab: 'chats' } } }],
    render(params, entry) {
      const st = entry.state; st.q = st.q || '';
      const known = Object.values(Data.people).filter((p) => p.id !== 'unknown' && !p.blocked && Data.displayName(p).toLowerCase().includes(st.q.toLowerCase()));
      return `<header class="appbar">${ibtn('arrow-left', 'Back', 'data-back')}<div class="search" style="flex:1;margin:0 8px 0 0;height:44px">${icon('magnifying-glass')}<input id="pq" placeholder="Name, number or ~Orbit name" value="${esc(st.q)}" aria-label="Name, number or ~Orbit name" autocomplete="off"></div></header>
        <div class="scroll" style="padding-bottom:30px"><div class="list-label"><span class="eyebrow">${st.q ? 'People' : 'People on Orbit'}</span></div>
        ${known.map((p) => `<button class="chat-row" data-person="${p.id}">${avatar(Data.av(p), 52)}<span class="cr-body"><span class="cr-name"><span class="nm">${esc(Data.displayName(p))}</span></span><span class="cr-preview mono" style="font-size:12px">${esc(Data.secondary(p) || '')}</span></span></button>`).join('') || UI.empty({ icon: 'magnifying-glass', title: 'No matches', text: `Nobody you know matches “${esc(st.q)}”.` })}</div>`;
    },
    mount(el, params, entry) {
      wire(el, entry);
      const q = el.querySelector('#pq');
      q.addEventListener('input', () => { entry.state.q = q.value; const pos = q.selectionStart; entry.rerender(); const n = entry.el.querySelector('#pq'); n.focus(); n.setSelectionRange(pos, pos); });
      el.querySelectorAll('[data-person]').forEach((b) => b.addEventListener('click', () => App.push('chat', { id: `direct:${b.dataset.person}` })));
    },
  });
})();
