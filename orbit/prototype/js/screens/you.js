/*
  "You": the Settings and Profile experience, redesigned (2026-10-16, design
  first). Your avatar on Chats and Calls opens it.
    - Orbit ID pass: who you are, in the logo's gradient, with your code.
    - Privacy checkup: only what needs attention, with a one-tap fix.
    - Topic tiles with live status; Account, Help and Advanced as rows.
  The profile editor shows a live preview of the pass as you type.
*/
(() => {
  const { esc, icon, ibtn, avatar, row } = UI;
  const { field, wire, qr, notice } = Kit;
  const base = { screen: 'home', params: { tab: 'chats' } };

  const S = { recovery: false, lock: false };
  window.HelixYouState = S; // the recovery page marks its check done
  const CHECKS = () => [
    { key: 'backup', ok: true, icon: 'cloud-check', title: 'Chat backup', okText: 'Backed up 5 hours ago', go: 'backup' },
    { key: 'devices', ok: true, icon: 'devices', title: 'Linked devices', okText: '2 devices, both signed in by you', go: 'devices' },
    { key: 'password', ok: true, icon: 'password', title: 'Password', okText: 'Set. You can sign in on a new phone', go: 'password' },
    { key: 'recovery', ok: S.recovery, icon: 'key', title: 'Recovery backup', okText: 'Made today', badText: 'No recovery backup yet', fix: 'Fix', go: 'recovery' },
    { key: 'lock', ok: S.lock, icon: 'lock-simple', title: 'App lock', okText: 'On. Locks after 1 minute', badText: 'App lock is off', fix: 'Turn on' },
  ];

  // The pass: the one bold, branded surface outside calls.
  function pass({ name = Data.me.name, about = Data.me.about, helixName = Data.me.helixName, photo, actions = true, compact = false } = {}) {
    return `<div class="pass ${compact ? 'compact' : ''} ${actions ? 'tappable' : ''}" ${actions ? 'role="button" tabindex="0" data-pass aria-label="Edit your profile"' : ''}>
      <span class="pass-ring" aria-hidden="true"></span>
      <div class="pass-top"><span class="pass-eyebrow">Orbit ID · ${esc(Data.me.server)}</span><span class="pass-chip">${icon('lock-simple', 'fill')}E2E</span></div>
      <div class="pass-main">${avatar({ name: name || 'You', seed: 'me', color: 0, photo }, compact ? 52 : 64)}
        <div class="pass-who"><div class="pass-name">${esc(name || 'Add your name')}</div>${about ? `<div class="pass-about">${esc(about)}</div>` : ''}</div></div>
      <div class="pass-meta"><span>${helixName ? `~${esc(helixName)}` : 'No ~name yet'}</span><span>${esc(Data.me.masked)}</span></div>
      <div class="pass-foot"><span class="pass-net">${icon('devices')} 2 devices</span>
        ${actions ? `<div class="pass-actions"><button class="pass-btn" data-share title="Share your Orbit code" aria-label="Share your Orbit code">${icon('qr-code')}</button><span class="pass-edit">${icon('pencil-simple')}Edit profile${icon('caret-right', 'bold')}</span></div>` : ''}</div>
    </div>`;
  }

  function checkup(showAll) {
    const list = CHECKS();
    const ok = list.filter((c) => c.ok).length;
    const bad = list.filter((c) => !c.ok);
    const items = (showAll ? list : bad).map((c) => `<div class="ck-item ${c.ok ? 'ok' : 'warn'}">${icon(c.ok ? 'check-circle' : 'warning-circle', 'fill')}
      <span class="ck-text"><span class="ck-t">${c.ok ? c.title : c.badText}</span>${c.ok ? `<span class="ck-s">${c.okText}</span>` : ''}</span>
      ${c.ok ? (c.go ? ibtn('caret-right', `Open ${c.title}`, `data-go="${c.go}"`, 'sm') : '') : `<button class="btn ${c.key === 'lock' ? 'primary' : 'secondary'} ck-fix" data-fix="${c.key}">${c.fix}</button>`}</div>`).join('');
    if (!bad.length && !showAll) {
      return `<div class="checkup good"><div class="ck-head"><span class="ck-title">${icon('shield-check', 'fill')} Privacy checkup</span><span class="ck-score">${ok} of ${list.length}</span></div>
        <div class="ck-bar"><b style="width:100%"></b></div><p class="ck-done">Everything that keeps your account safe is in place.</p><button class="ck-all" data-all>See all checks</button></div>`;
    }
    return `<div class="checkup"><div class="ck-head"><span class="ck-title">${icon('shield-warning', 'fill')} Privacy checkup</span><span class="ck-score">${ok} of ${list.length}</span></div>
      <div class="ck-bar"><b style="width:${(ok / list.length) * 100}%"></b></div>${items}
      ${showAll ? '' : `<button class="ck-all" data-all>See all ${list.length} checks</button>`}</div>`;
  }

  const pref = (fn, fallback) => { try { return fn(window.OrbitPrefs); } catch (_) { return fallback; } };
  const TILES = () => [
    ['appearance', 'palette', 6, 'Appearance', (App.getTheme && App.getTheme().name) || 'Orbit'],
    ['privacy', 'lock-simple', 3, 'Privacy', pref((p) => `Receipts ${p.privacy.receipts ? 'on' : 'off'}`, 'Receipts on')],
    ['notifications', 'bell', 4, 'Notifications', pref((p) => `Sound ${p.notify.sound ? 'on' : 'off'}`, 'Sound on')],
    ['chats-settings', 'chat-centered-text', 1, 'Chats', pref((p) => `Text ${p.chats.size.toLowerCase()}`, 'Text default')],
    ['devices', 'devices', 2, 'Devices', '2 linked'],
    ['backup', 'cloud-arrow-up', 0, 'Backup', '5 h ago'],
  ];
  const ROWS = [['account', 'user-circle', 7, 'Account', 'Number, password, sign out, delete'], ['storage', 'database', 6, 'Storage and data', '1.2 GB on this phone'], ['about', 'question', 5, 'Help and about', 'Version, terms, privacy policy'], ['advanced', 'wrench', 7, 'Advanced', 'Server details and connection']];
  const SEARCHABLE = () => [...TILES().map(([go, ic, c, t, m]) => [go, ic, c, t, m]), ...ROWS, ['profile', 'identification-card', 0, 'Edit profile', 'Name, about, photo, ~name'], ['recovery', 'key', 4, 'Recovery backup', 'A backup only your secret opens'], ['password', 'password', 0, 'Change password', 'Sign in on a new phone'], ['blocked', 'prohibit', 7, 'Blocked', 'People who cannot reach you']];

  App.register({
    id: 'settings-page', title: 'You', group: 'You (settings and profile)', order: 58,
    entries: [
      { key: 'settings', label: 'You · checkup needs attention', params: { checkup: 'attention' } },
      { key: 'you-allgood', label: 'You · all checks pass', params: { allGood: true } },
      { key: 'you-share', label: 'You · share your Orbit code', params: { share: true } },
      { key: 'settings-search', label: 'You · search settings', params: { setQuery: 'pass' } },
    ].map((e) => ({ ...e, base })),
    refreshOnReturn: true,
    render(params, entry) {
      const st = entry.state;
      if (!st.init) { st.init = true; st.searching = !!params.setQuery; st.q = params.setQuery || ''; if (params.allGood) { S.recovery = true; S.lock = true; } if (params.checkup === 'attention') { S.recovery = false; S.lock = false; } }
      if (st.searching) {
        const q = st.q.trim().toLowerCase();
        const hits = q ? SEARCHABLE().filter(([, , , t, s]) => `${t} ${s}`.toLowerCase().includes(q)) : [];
        return `<header class="appbar">${ibtn('arrow-left', 'Close search', 'data-search-close')}<div class="search" style="flex:1;margin:0 8px 0 0;height:44px">${icon('magnifying-glass')}<input id="youQ" placeholder="Search settings" value="${esc(st.q)}" aria-label="Search settings" autocomplete="off"></div></header>
          <div class="scroll">${!q ? UI.empty({ icon: 'magnifying-glass', title: 'Search settings', text: 'Try “receipts”, “backup” or “password”.' })
            : hits.length ? `<div style="height:12px"></div><div class="card">${hits.map(([go, ic, c, t, s]) => row({ icon: ic, color: c, title: t, sub: s, end: 'chevron', attrs: `data-go="${go}"` })).join('')}</div>`
              : UI.empty({ icon: 'magnifying-glass-minus', title: `No settings match “${esc(st.q.trim())}”`, text: 'Try a different word.' })}</div>`;
      }
      return `<header class="appbar flat you-bar">${ibtn('arrow-left', 'Back', 'data-back')}<div class="ab-title"><h1>You</h1></div>${ibtn('magnifying-glass', 'Search settings', 'data-search')}</header>
        <div class="scroll" data-keep-scroll="you" style="padding-bottom:36px">
          ${pass()}
          ${checkup(false)}
          <div class="stiles">${TILES().map(([go, ic, c, t, m]) => `<button class="stile" data-go="${go}"><span class="rw-ico av-${c}">${icon(ic)}</span><span class="st-title">${t}</span><span class="st-meta">${m}</span></button>`).join('')}</div>
          <div class="card" style="margin-top:12px">${ROWS.map(([go, ic, c, t, s]) => row({ icon: ic, color: c, title: t, sub: s, end: 'chevron', attrs: `data-go="${go}"` })).join('')}</div>
          <p class="you-foot">Orbit 2.0.0 · ${esc(Data.me.host)}</p>
        </div>`;
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelector('[data-search]')?.addEventListener('click', () => { st.searching = true; entry.rerender(); entry.el.querySelector('#youQ')?.focus(); });
      el.querySelector('[data-search-close]')?.addEventListener('click', () => { st.searching = false; st.q = ''; entry.rerender(); });
      const q = el.querySelector('#youQ');
      if (q) q.addEventListener('input', () => { st.q = q.value; const p = q.selectionStart; entry.rerender(); const n = entry.el.querySelector('#youQ'); n.focus(); n.setSelectionRange(p, p); });
      el.querySelector('[data-share]')?.addEventListener('click', (e) => { e.stopPropagation(); shareSheet(); });
      const passEl = el.querySelector('[data-pass]');
      if (passEl) {
        passEl.addEventListener('click', () => App.push('profile'));
        passEl.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); App.push('profile'); } });
      }
      el.querySelectorAll('[data-fix]').forEach((b) => b.addEventListener('click', () => {
        if (b.dataset.fix === 'recovery') App.push('recovery', { tab: 'create' });
        if (b.dataset.fix === 'lock') App.dialog({ title: 'Turn on app lock?', text: `Orbit will ask for ${UI.unlock().what} when you open it. Calls still ring while it is locked.`, actions: [{ label: 'Cancel' }, { label: 'Turn on', kind: 'primary', run: () => { S.lock = true; entry.rerender(); App.snack('App lock is on'); } }] });
      }));
      el.querySelectorAll('[data-all]').forEach((b) => b.addEventListener('click', () => {
        const h = App.sheet({ title: 'Privacy checkup', text: 'What keeps your account and your messages safe, and what still needs a moment.', body: `<div style="padding:0 6px 6px">${checkup(true)}</div>` });
        h.panel.querySelectorAll('[data-go]').forEach((g) => g.addEventListener('click', () => { h.close(); App.push(g.dataset.go); }));
        h.panel.querySelectorAll('[data-fix]').forEach((f) => f.addEventListener('click', () => { h.close(); el.querySelector(`[data-fix="${f.dataset.fix}"]`)?.click(); }));
      }));
      if (params.share && !st.shareShown) { st.shareShown = true; setTimeout(shareSheet, 60); }
    },
  });

  // Your code: let people start a chat with you by scanning it.
  function shareSheet() {
    const link = `helix.agiletechbd.com/u/${Data.me.helixName}`;
    const h = App.sheet({ body: `<div class="share-sheet">
      <div class="pass mini"><span class="pass-ring" aria-hidden="true"></span><div class="pass-main">${avatar({ name: Data.me.name, color: 0 }, 44)}<div class="pass-who"><div class="pass-name">${esc(Data.me.name)}</div><div class="pass-about mono">~${esc(Data.me.helixName)}</div></div></div></div>
      <div class="qr-wrap" style="padding-top:20px"><div class="qr-card">${qr('my-helix-code', 200)}</div></div>
      <p class="sec-foot" style="text-align:center;margin:12px 24px 0">Anyone who scans this can message you. Your number stays hidden.</p>
      <div class="lk-url" style="margin:14px var(--gutter) 0;text-align:center">${esc(link)}</div>
      <div class="btn-row"><button class="btn secondary" data-copy>${icon('copy')}Copy link</button><button class="btn primary" data-sharelink>${icon('share-network')}Share</button></div>
      <div class="btn-row" style="padding-top:8px"><button class="btn ghost block" data-scan>${icon('scan')}Scan someone’s code</button></div></div>` });
    h.panel.querySelector('[data-copy]').addEventListener('click', () => { h.close(); App.snack('Link copied'); });
    h.panel.querySelector('[data-sharelink]').addEventListener('click', () => { h.close(); App.snack('Opens the share sheet'); });
    h.panel.querySelector('[data-scan]').addEventListener('click', () => { h.close(); App.push('scan', { id: 'arif', mode: 'contact' }); });
  }

  // ------------------------------------------------------------- edit profile
  function nameState(v) {
    const n = v.replace(/^~/, '').trim().toLowerCase();
    if (!n) return null;
    if (n === Data.me.helixName) return ['ok', 'This is your ~name'];
    if (n.length < 3) return ['bad', 'Names are at least 3 characters.'];
    if (!/^[a-z]/.test(n)) return ['bad', 'Names start with a letter.'];
    if (!/^[a-z0-9._]+$/.test(n)) return ['bad', 'Use only letters, numbers, dots and underscores.'];
    if (/admin|support|helix|official/.test(n) || ['nadia', 'arif', 'sadia'].includes(n)) return ['bad', 'That name is not available. Try another.'];
    return ['ok', `~${n} is available`];
  }

  App.register({
    id: 'profile', title: 'Edit profile', group: 'You (settings and profile)', order: 58,
    entries: [
      { key: 'profile', label: 'Edit profile', params: {} },
      { key: 'profile-taken', label: 'Edit profile · ~name taken', params: { helixName: 'nadia' } },
      { key: 'profile-new', label: 'Edit profile · new account (empty)', params: { blank: true } },
    ].map((e) => ({ ...e, base: [base, { screen: 'settings-page', params: {} }] })),
    render(params, entry) {
      const st = entry.state;
      if (!st.init) Object.assign(st, { init: true, name: params.blank ? '' : Data.me.name, about: params.blank ? '' : Data.me.about, helixName: params.blank ? '' : (params.helixName || Data.me.helixName), photo: false });
      const ns = nameState(st.helixName);
      const vis = (ic, what, who, tag) => `<div class="row" style="min-height:52px">${`<span class="rw-ico" style="background:var(--field)">${icon(ic)}</span>`}<span class="rw-body"><span class="rw-title" style="display:block;font-size:14px">${what}</span><span class="rw-sub" style="display:block">${who}</span></span>${tag}</div>`;
      return `<header class="appbar">${ibtn('arrow-left', 'Back', 'data-back')}<div class="ab-title"><h1>Edit profile</h1></div><button class="btn ghost" data-save style="margin-right:4px">Save</button></header>
        <div class="scroll" data-keep-scroll="prof" style="padding-bottom:36px">
          <div class="live-preview"><span class="eyebrow">Live preview</span>${pass({ name: st.name, about: st.about, helixName: ns && ns[0] === 'ok' ? st.helixName.replace(/^~/, '').toLowerCase() : Data.me.helixName && !params.blank ? Data.me.helixName : '', photo: st.photo ? 'ph-a' : '', actions: false, compact: true })}</div>
          <div class="pad" style="display:flex;gap:8px;margin-top:4px"><button class="btn secondary" style="flex:1" data-photo>${icon('image')}${st.photo ? 'Change photo' : 'Choose a photo'}</button>${st.photo ? `<button class="btn ghost" style="color:var(--danger)" data-unphoto>Remove</button>` : ''}</div>
          <div class="pad" style="margin-top:18px">
            ${field({ id: 'pfName', label: 'Name', value: st.name, max: 50, counter: true, hint: 'How people see you' })}
            ${field({ id: 'pfAbout', label: 'About', value: st.about, max: 139, counter: true, hint: 'A line about you' })}
            ${field({ id: 'pfHelix', label: '~Orbit name', prefix: '~', value: st.helixName.replace(/^~/, ''), mono: true, hint: 'anna.k', error: ns && ns[0] === 'bad' ? ns[1] : '', helper: ns && ns[0] === 'ok' ? `<span style="color:var(--success)">${icon('check-circle', 'fill')} ${ns[1]}</span>` : '3 to 32 letters, numbers, dots or underscores, starting with a letter.' })}
          </div>
          <div class="group-title eyebrow">Who sees what</div>
          <div class="card">
            ${vis('user', 'Name, about and photo', 'People you have messaged', '<span class="tag success">' + icon('lock-simple', 'fill') + 'Encrypted</span>')}
            ${vis('at', '~Orbit name', 'Anyone can look it up to message you', '<span class="tag">Public</span>')}
            ${vis('phone', 'Phone number', 'Never shown. Only people who already have it can find you', '<span class="tag accent">Hidden</span>')}
          </div>
          ${st.helixName ? `<div class="card" style="margin-top:12px">${row({ icon: 'trash', title: 'Remove my ~name', sub: 'People can still message you by number', danger: true, attrs: 'data-unclaim' })}</div>` : ''}
        </div>`;
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      const live = (id, key) => { const n = el.querySelector(id); n.addEventListener('input', () => { st[key] = n.value; const p = n.selectionStart; entry.rerender(); const m = entry.el.querySelector(id); m.focus(); m.setSelectionRange(p, p); }); };
      live('#pfName', 'name'); live('#pfAbout', 'about'); live('#pfHelix', 'helixName');
      el.querySelector('[data-photo]').addEventListener('click', () => { st.photo = true; entry.rerender(); });
      el.querySelector('[data-unphoto]')?.addEventListener('click', () => { st.photo = false; entry.rerender(); });
      el.querySelector('[data-unclaim]')?.addEventListener('click', () => Kit.confirm('Remove your ~name?', `People will no longer find you by ~${st.helixName}. Someone else may claim it.`, 'Remove', () => { st.helixName = ''; entry.rerender(); }));
      el.querySelector('[data-save]').addEventListener('click', () => {
        const ns = nameState(st.helixName);
        if (ns && ns[0] === 'bad') { App.snack('Fix your ~name first'); return; }
        if (!st.name.trim()) { App.snack('Enter the name people should see.'); return; }
        Data.me.name = st.name.trim(); Data.me.about = st.about.trim(); if (st.helixName) Data.me.helixName = st.helixName.replace(/^~/, '').toLowerCase();
        App.pop(); App.snack('Profile saved');
      });
    },
  });
})();
