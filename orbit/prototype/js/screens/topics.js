/*
  The pages the You tiles open, in the You style (2026-10-16):
    - a summary card (gradient icon, one-line status, status pills),
    - a live preview where it helps (Privacy: what others see; Notifications:
      your lock screen; Chats: a conversation at your text size),
    - choices inline as segmented controls instead of pop-up lists,
    - a red-edged danger zone at the bottom.
  Pages: Privacy, Notifications, Chats, Storage, Devices, Backup, Account.
*/
(() => {
  const { esc, icon, ibtn, avatar, row } = UI;
  const { sw, wire, confirm, progress } = Kit;
  const base = [{ screen: 'home', params: { tab: 'chats' } }, { screen: 'settings-page', params: {} }];

  // Shared, so a change made on one page shows on the You tiles and survives navigation.
  const P = window.OrbitPrefs = {
    privacy: { lastSeen: 'Everyone', online: 'Everyone', groups: 'Everyone', byNumber: true, byName: true, receipts: true, typing: true, timer: 'Off', lockAfter: '1 min' },
    notify: { messages: true, groups: true, calls: true, sound: true, vibrate: true, previews: false },
    chats: { size: 'Default', enter: false, dl: { photos: 'Wi-Fi', voice: 'Always', videos: 'Never', docs: 'Never' } },
    backup: { auto: true, mobile: false },
  };
  const you = () => window.HelixYouState || { lock: false, recovery: false };
  const get = (path) => path.split('.').reduce((o, k) => o[k], P);
  const set = (path, v) => { const ks = path.split('.'); const last = ks.pop(); ks.reduce((o, k) => o[k], P)[last] = v; };

  // ------------------------------------------------------------- shared parts
  function hero({ ic, title, sub, pills = [], slot = '' }) {
    return `<div class="hero-card"><div class="hc-top"><span class="hc-ico">${icon(ic, 'fill')}</span><div class="hc-text"><div class="hc-title">${title}</div><div class="hc-sub">${sub}</div></div></div>
      ${slot}${pills.length ? `<div class="hc-pills">${pills.map((p) => `<span class="hc-pill ${p.tone || ''}">${icon(p.icon, p.tone ? 'fill' : '')}${p.text}</span>`).join('')}</div>` : ''}</div>`;
  }
  // A setting whose few choices sit inline under its title.
  function segRow(path, title, sub, options, ic, color) {
    const v = get(path);
    return `<div class="segrow"><div class="sr-head">${ic ? `<span class="rw-ico av-${color}">${icon(ic)}</span>` : ''}<span class="rw-body"><span class="rw-title" style="display:block">${title}</span>${sub ? `<span class="rw-sub" style="display:block">${sub}</span>` : ''}</span></div>
      <div class="seg sm" role="radiogroup" aria-label="${esc(title)}">${options.map((o) => `<button role="radio" aria-checked="${o === v}" class="${o === v ? 'on' : ''}" data-pref="${path}" data-v="${esc(o)}">${esc(o)}</button>`).join('')}</div></div>`;
  }
  const swPref = (path, title, sub, ic, color) => row({ icon: ic, color, title, sub, end: 'switch', on: !!get(path), attrs: `data-switch data-pref-bool="${path}"` });
  const section = (title, items, foot) => `${title ? `<div class="group-title eyebrow">${title}</div>` : '<div style="height:14px"></div>'}<div class="card">${items.join('')}</div>${foot ? `<p class="sec-foot">${foot}</p>` : ''}`;
  const danger = (items, foot) => `<div class="group-title eyebrow dz-title">Danger zone</div><div class="card danger-zone">${items.join('')}</div>${foot ? `<p class="sec-foot">${foot}</p>` : ''}`;
  const page = (title, body) => `<header class="appbar flat you-bar">${ibtn('arrow-left', 'Back', 'data-back')}<div class="ab-title"><h1>${title}</h1></div></header><div class="scroll" data-keep-scroll="topic" style="padding-bottom:36px">${body}</div>`;

  function wirePrefs(el, entry) {
    wire(el, entry);
    el.querySelectorAll('[data-pref]').forEach((b) => b.addEventListener('click', () => { set(b.dataset.pref, b.dataset.v); entry.rerender(); }));
    el.querySelectorAll('[data-pref-bool]').forEach((r) => r.addEventListener('toggle', (e) => { set(r.dataset.prefBool, e.detail); entry.rerender(); }));
  }
  const reg = (def) => App.register({ group: 'Settings', order: 60, refreshOnReturn: true, ...def, entries: def.entries.map((e) => ({ base, ...e })) });

  // ================================================================= Privacy
  function privacyPreview() {
    const p = P.privacy;
    const status = p.online === 'Everyone' ? 'online' : p.lastSeen === 'Everyone' ? 'last seen today at 08:12' : '';
    const tick = p.receipts ? '<i class="ph-bold ph-checks" style="color:var(--read)"></i>' : '<i class="ph ph-checks"></i>';
    return `<div class="preview-box"><div class="pv-label">What Nadia sees</div>
      <div class="pv-head">${avatar({ name: Data.me.name, color: 0 }, 32)}<div><div class="pv-name">${esc(Data.me.name)}</div><div class="pv-status">${status || '<span style="opacity:.6">no status shown</span>'}</div></div></div>
      <div class="pv-bubble out">Did you get the photos? <span class="pv-meta">09:41 ${tick}</span></div>
      ${p.typing ? `<div class="pv-typing">${esc(Data.me.name)} is typing<span class="typing-bubble" style="padding:0 0 0 6px;display:inline-flex"><span></span><span></span><span></span></span></div>` : ''}</div>`;
  }
  reg({
    id: 'privacy', title: 'Privacy',
    entries: [{ key: 'privacy', label: 'Privacy', params: {} }, { key: 'privacy-lock', label: 'Privacy · app lock on', params: { lock: true } }],
    render(params, entry) {
      if (params.lock && !entry.state.init) { you().lock = true; }
      entry.state.init = true;
      const p = P.privacy; const lock = you().lock;
      const hidden = [p.lastSeen, p.online].filter((x) => x === 'Nobody').length;
      return page('Privacy', `
        ${hero({ ic: 'shield-check', title: 'Your privacy', sub: hidden ? `${hidden} of 2 statuses hidden` : 'Everyone can see your status',
          pills: [{ icon: 'checks', text: `Receipts ${p.receipts ? 'on' : 'off'}`, tone: p.receipts ? '' : 'accent' }, { icon: 'lock-simple', text: `App lock ${lock ? 'on' : 'off'}`, tone: lock ? 'ok' : 'warn' }, { icon: 'prohibit', text: '1 blocked' }],
          slot: privacyPreview() })}
        ${section('Who can see', [
          segRow('privacy.lastSeen', 'Last seen', '', ['Everyone', 'Nobody'], 'clock', 0),
          segRow('privacy.online', 'Online status', '', ['Everyone', 'Nobody'], 'circle', 3),
          segRow('privacy.groups', 'Who can add me to groups', '', ['Everyone', 'Nobody'], 'users-three', 2),
        ], 'Orbit applies these on its server, to everyone else.')}
        ${section('Messages', [
          swPref('privacy.receipts', 'Read receipts', 'Blue ticks when you have read a message', 'checks', 1),
          swPref('privacy.typing', 'Typing indicator', 'Show people when you are typing', 'chat-dots', 4),
          segRow('privacy.timer', 'Disappearing messages for new chats', '', ['Off', '24 h', '7 d', '90 d'], 'timer', 5),
        ], 'Turning receipts or typing off also hides other people’s from you.')}
        ${section('Being found', [
          swPref('privacy.byNumber', 'By phone number', 'People who have your number can find you', 'phone', 3),
          swPref('privacy.byName', 'By ~Orbit name', 'People who know your ~name can find you', 'at', 1),
        ])}
        ${section('App lock', [
          row({ icon: 'fingerprint', color: 0, title: 'Lock Orbit', sub: App.isWide() ? 'Windows Hello to open Orbit' : 'Fingerprint, face or phone PIN to open Orbit', end: 'switch', on: lock, attrs: 'data-switch data-lock' }),
          ...(lock ? [segRow('privacy.lockAfter', 'Lock again', 'After Orbit has been in the background for', ['Now', '1 min', '5 min', '30 min'])] : []),
        ], lock ? 'Calls still ring while Orbit is locked.' : '')}
        ${section('Blocked', [`<button class="row" data-go="blocked"><span class="av-stack">${avatar(Data.av(Data.people.shuvo), 32)}</span><span class="rw-body"><span class="rw-title" style="display:block">1 blocked person</span><span class="rw-sub" style="display:block">They cannot message or call you</span></span><span class="rw-end">${icon('caret-right')}</span></button>`])}`);
    },
    mount(el, params, entry) {
      wirePrefs(el, entry);
      el.querySelector('[data-lock]').addEventListener('toggle', (e) => { you().lock = e.detail; entry.rerender(); });
    },
  });

  // =========================================================== Notifications
  function lockPreview() {
    const n = P.notify;
    const title = n.previews ? 'Nadia Rahman' : 'Orbit';
    const body = n.previews ? 'Sent the photos from Cox’s Bazar 🌊' : 'New message';
    return `<div class="lockprev"><div class="lp-time">9:41</div><div class="lp-date">Friday, 16 October</div>
      <div class="lp-note"><span class="lp-app"></span><div class="lp-text"><div class="lp-top"><b>${esc(title)}</b><span>now</span></div><div class="lp-body">${esc(body)}</div></div></div>
      <div class="lp-flags">${icon(n.sound ? 'speaker-high' : 'speaker-slash')}${n.sound ? 'Sound' : 'Silent'} · ${icon(n.vibrate ? 'vibrate' : 'device-mobile')}${n.vibrate ? 'Vibrate' : 'No vibration'}</div></div>`;
  }
  reg({
    id: 'notifications', title: 'Notifications',
    entries: [{ key: 'notifications', label: 'Notifications', params: {} }, { key: 'notifications-off', label: 'Notifications · off in phone settings', params: { osOff: true } }],
    render(params, entry) {
      const n = P.notify;
      const on = [n.messages, n.groups, n.calls].filter(Boolean).length;
      const muted = Data.chats.filter((c) => c.muted);
      const alertTile = (k, ic, label) => `<button class="alert-tile ${n[k] ? 'on' : ''}" data-alert="${k}" aria-pressed="${n[k]}">${icon(ic, n[k] ? 'fill' : '')}<span>${label}</span><span class="at-state">${n[k] ? 'On' : 'Off'}</span></button>`;
      return page('Notifications', `
        ${params.osOff ? Kit.notice('error', 'Notifications are turned off for Orbit in your phone’s settings, so nothing here will make a sound.', { label: 'Allow notifications', attr: 'data-snack="Opens the phone’s notification settings"' }) : ''}
        ${hero({ ic: 'bell-ringing', title: 'Notifications', sub: `${on} of 3 alerts on · previews ${n.previews ? 'shown' : 'hidden'}`, slot: lockPreview() })}
        <div class="group-title eyebrow">Alerts</div><div class="alert-tiles">${alertTile('messages', 'chat-circle', 'Messages')}${alertTile('groups', 'users-three', 'Groups')}${alertTile('calls', 'phone', 'Calls')}</div>
        <p class="sec-foot">Turning an alert off still delivers the message. It only stays quiet until you open Orbit.</p>
        ${section('Sound and lock screen', [
          swPref('notify.sound', 'Sound', 'Your phone’s default notification sound', 'speaker-high', 4),
          swPref('notify.vibrate', 'Vibrate', '', 'vibrate', 2),
          swPref('notify.previews', 'Show message previews', 'Who wrote and what they said, on the lock screen', 'eye', 1),
        ])}
        ${section(`Muted chats · ${muted.length}`, muted.map((c) => `<div class="row">${avatar(c.avatar, 40)}<span class="rw-body"><span class="rw-title" style="display:block">${esc(c.title)}</span><span class="rw-sub" style="display:block">Muted</span></span><button class="btn ghost" data-unmute>Unmute</button></div>`), 'Mute a chat from the chat itself.')}`);
    },
    mount(el, params, entry) {
      wirePrefs(el, entry);
      el.querySelectorAll('[data-alert]').forEach((b) => b.addEventListener('click', () => { P.notify[b.dataset.alert] = !P.notify[b.dataset.alert]; entry.rerender(); }));
      el.querySelectorAll('[data-unmute]').forEach((b) => b.addEventListener('click', () => { b.closest('.row').remove(); App.snack('Unmuted'); }));
    },
  });

  // =================================================================== Chats
  const SIZES = { Small: 0.9, Default: 1, Large: 1.15, 'Extra large': 1.3 };
  reg({
    id: 'chats-settings', title: 'Chats',
    entries: [{ key: 'chats-settings', label: 'Chats settings', params: {} }],
    render() {
      const c = P.chats; const s = SIZES[c.size];
      const sizeBtn = (k, i) => `<button class="size-btn ${c.size === k ? 'on' : ''}" data-pref="chats.size" data-v="${k}" aria-label="${k}" title="${k}"><span style="font-size:${13 + i * 4}px">Aa</span><small>${k}</small></button>`;
      const dl = (k, ic, color, label) => segRow(`chats.dl.${k}`, label, '', ['Never', 'Wi-Fi', 'Always'], ic, color);
      return page('Chats', `
        ${hero({ ic: 'chat-centered-text', title: 'Chats', sub: `Text ${c.size.toLowerCase()} · Enter ${c.enter ? 'sends' : 'adds a line'}`,
          slot: `<div class="preview-box chatprev" style="--ps:${s}"><div class="pv-label">Preview</div>
            <div class="pv-bubble in">Are you still coming to the launch on Friday? <span class="pv-meta">21:04</span></div>
            <div class="pv-bubble out">Yes! Wouldn’t miss it. <span class="pv-meta">21:06 <i class="ph-bold ph-checks" style="color:var(--read)"></i></span></div></div>` })}
        <div class="group-title eyebrow">Text size</div><div class="size-row">${Object.keys(SIZES).map(sizeBtn).join('')}</div>
        <p class="sec-foot">Multiplies with your phone’s own text size.</p>
        ${section('Typing', [swPref('chats.enter', 'Enter key sends', 'With a hardware keyboard. Otherwise Enter adds a new line', 'keyboard', 7)])}
        ${section('Download automatically', [dl('photos', 'image', 2, 'Photos'), dl('voice', 'microphone', 4, 'Voice messages'), dl('videos', 'video-camera', 5, 'Videos'), dl('docs', 'file-text', 3, 'Documents')], 'Anything not downloaded automatically downloads when you tap it. Wi-Fi means Wi-Fi only; Always includes mobile data.')}`);
    },
    mount(el, params, entry) { wirePrefs(el, entry); },
  });

  // ================================================================= Storage
  const BIG = [['group:family', 412, 380], ['direct:nadia', 260, 241], ['group:design', 198, 170], ['group:lunch', 64, 51], ['direct:arif', 38, 30]];
  reg({
    id: 'storage', title: 'Storage and data',
    entries: [{ key: 'storage', label: 'Storage and data', params: {} }],
    render() {
      const chat = (id) => Data.chats.find((c) => c.id === id);
      return page('Storage and data', `
        ${hero({ ic: 'hard-drives', title: '1.2 GB on this phone', sub: '184 MB messages and keys · 1.0 GB media',
          slot: `<div class="stor-bar" role="img" aria-label="Storage: 15 percent messages, 85 percent media"><b style="width:15%;background:var(--accent)"></b><b style="width:62%;background:var(--cyan)"></b><b style="width:23%;background:#7C3AED"></b></div>
            <div class="stor-legend"><span><i style="background:var(--accent)"></i>Messages and keys</span><span><i style="background:var(--cyan)"></i>Photos and videos</span><span><i style="background:#7C3AED"></i>Files</span></div>` })}
        <div class="group-title eyebrow">Biggest chats</div>
        <div class="card">${BIG.map(([id, mb, media]) => { const c = chat(id); return `<button class="row" data-free="${id}">${avatar(c.avatar, 40)}<span class="rw-body"><span class="rw-title" style="display:block">${esc(c.title)}</span><span class="mini-bar"><b style="width:${(mb / 412) * 100}%"></b></span></span><span class="rw-value mono">${mb} MB</span></button>`; }).join('')}</div>
        <p class="sec-foot">Tap a chat to free space without deleting its messages.</p>
        ${section('Data use', [
          row({ icon: 'download-simple', color: 1, title: 'Download automatically', sub: 'Photos on Wi-Fi, voice always, videos and documents never', end: 'chevron', attrs: 'data-go="chats-settings"' }),
          row({ icon: 'cloud-arrow-up', color: 2, title: 'Backup over mobile data', sub: P.backup.mobile ? 'Allowed' : 'Wi-Fi only', end: 'chevron', attrs: 'data-go="backup"' }),
        ])}`);
    },
    mount(el, params, entry) {
      wire(el, entry);
      el.querySelectorAll('[data-free]').forEach((b) => b.addEventListener('click', () => {
        const [, mb, media] = BIG.find(([id]) => id === b.dataset.free); const c = Data.chats.find((x) => x.id === b.dataset.free);
        App.sheet({ title: `Free up space in ${c.title}`, text: 'Messages stay. Removed files can be downloaded again while the sender’s copy is on the server.', items: [
          { icon: 'images', label: `Remove photos and videos · ${media} MB`, run: () => App.snack(`${media} MB freed`) },
          { icon: 'file-text', label: `Remove documents · ${mb - media} MB`, run: () => App.snack(`${mb - media} MB freed`) },
        ] });
      }));
    },
  });

  // ================================================================= Devices
  const DEVICES = [{ id: 'd1', name: 'Pixel 8', platform: 'Android', ic: 'device-mobile', self: true, when: 'This device' }, { id: 'd2', name: 'Office PC', platform: 'Windows', ic: 'desktop', when: 'Active 5 minutes ago' }];
  reg({
    id: 'devices', title: 'Devices',
    entries: [{ key: 'devices', label: 'Devices', params: {} }],
    render(params, entry) {
      const st = entry.state; st.list = st.list || DEVICES.map((d) => ({ ...d }));
      const card = (d) => `<button class="dev-card ${d.self ? 'self' : ''}" data-device="${d.id}"><span class="dc-ico">${icon(d.ic, 'fill')}</span><span class="dc-name">${esc(d.name)}</span><span class="dc-sub">${d.platform}</span><span class="tag ${d.self ? 'accent' : ''}">${d.self ? 'This device' : d.when.replace('Active ', '')}</span></button>`;
      return page('Devices', `
        ${hero({ ic: 'devices', title: `${st.list.length} device${st.list.length === 1 ? '' : 's'} signed in`, sub: 'Each can read your new messages', slot: `<div class="dev-strip">${st.list.map(card).join('')}</div>` })}
        <div class="btn-row"><button class="btn primary block" data-go="approve-device">${icon('qr-code')}Link a new device</button></div>
        <div class="group-title eyebrow">Recent security activity</div>
        <div class="card">
          ${row({ icon: 'sign-in', color: 7, title: 'Signed in', sub: 'Pixel 8 - Today, 08:02', tag: 'div' })}
          ${row({ icon: 'device-mobile', color: 7, title: 'A device was added', sub: 'Office PC - Yesterday, 18:40', tag: 'div' })}
          <button class="row accent" data-go="activity"><span class="rw-body"><span class="rw-title">See all activity</span></span><span class="rw-end">${icon('caret-right')}</span></button></div>
        ${st.list.length > 1 ? danger([row({ icon: 'sign-out', title: 'Sign out all other devices', danger: true, attrs: 'data-signout-all' })], 'Signed-out devices lose their messages. This phone stays signed in.') : ''}`);
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelectorAll('[data-device]').forEach((b) => b.addEventListener('click', () => {
        const d = st.list.find((x) => x.id === b.dataset.device);
        App.sheet({ title: d.name, text: `${d.platform} · ${d.when}`, items: [
          { icon: 'pencil-simple', label: 'Rename', run: () => Kit.inputDialog({ title: 'Rename device', label: 'Device name', value: d.name, run: (v) => { d.name = v || d.name; entry.rerender(); } }) },
          ...(d.self ? [] : [
            { icon: 'x-circle', label: 'Remove this device', danger: true, run: () => confirm(`Remove ${d.name}?`, 'It will be signed out and lose its messages. You can sign in on it again later.', 'Remove', () => { st.list = st.list.filter((x) => x !== d); entry.rerender(); }) },
            { icon: 'siren', label: 'Lost or stolen', sub: 'Remove it and note that it is no longer yours', danger: true, run: () => confirm('Lost or stolen?', `${d.name} will be signed out at once. Consider changing your password too.`, 'Remove it', () => { st.list = st.list.filter((x) => x !== d); entry.rerender(); }) },
          ]),
        ] });
      }));
      el.querySelector('[data-signout-all]')?.addEventListener('click', () => confirm('Sign out all other devices?', 'Every device except this one will be signed out and lose its messages.', 'Sign them out', () => { st.list = st.list.filter((x) => x.self); entry.rerender(); App.snack('Signed out 1 other device.'); }));
    },
  });

  // ================================================================== Backup
  reg({
    id: 'backup', title: 'Backup',
    entries: [
      { key: 'backup', label: 'Backup', params: {} },
      { key: 'backup-running', label: 'Backup · backing up', params: { running: true } },
      { key: 'backup-failed', label: 'Backup · last backup failed', params: { failed: true } },
    ],
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, running: !!params.running, failed: !!params.failed, p: 0.62 });
      const b = P.backup; const rec = you().recovery;
      const ring = st.running ? `<span class="b-ring run" style="--p:${st.p}"><span>${Math.round(st.p * 100)}%</span></span>`
        : st.failed ? `<span class="b-ring bad">${icon('warning', 'fill')}</span>` : `<span class="b-ring ok">${icon('check', 'bold')}</span>`;
      const title = st.running ? 'Backing up…' : st.failed ? 'The last backup did not finish' : `Backed up ${st.justNow ? 'just now' : '5 hours ago'}`;
      const sub = st.failed ? 'You were on mobile data and backups wait for Wi-Fi' : '12,480 messages · 3.1 MB, encrypted';
      return page('Backup', `
        <div class="hero-card backup-hero">${ring}<div class="hc-text"><div class="hc-title">${title}</div><div class="hc-sub">${sub}</div></div></div>
        <div class="btn-row"><button class="btn primary block" data-backup ${st.running ? 'disabled style="opacity:.6"' : ''}>${icon('cloud-arrow-up')}${st.failed ? 'Try again' : 'Back up now'}</button></div>
        <p class="sec-foot">Your chats and references to your files, encrypted on this phone with a key only your devices have. Files themselves, unsent and view-once messages are not included.</p>
        ${section('Automatic', [swPref('backup.auto', 'Back up every day', 'While Orbit is open, and when a new device joins', 'arrows-clockwise', 0), swPref('backup.mobile', 'Use mobile data', 'Otherwise backups wait for Wi-Fi', 'cell-signal-full', 4)])}
        <div class="group-title eyebrow">Move your history</div>
        <div class="stiles" style="padding-top:0"><button class="stile" data-go="restore-history"><span class="rw-ico av-2">${icon('cloud-arrow-down')}</span><span class="st-title">Restore</span><span class="st-meta">From your backup</span></button>
          <button class="stile" data-go="transfer"><span class="rw-ico av-0">${icon('devices')}</span><span class="st-title">Send to a device</span><span class="st-meta">1 waiting</span></button></div>
        <div class="group-title eyebrow">Recovery backup</div>
        <div class="card rec-card ${rec ? 'ok' : ''}"><div class="row" style="min-height:72px"><span class="rw-ico ${rec ? 'av-3' : 'av-4'}">${icon('key', 'fill')}</span><span class="rw-body"><span class="rw-title" style="display:block">${rec ? 'Recovery backup made' : 'No recovery backup yet'}</span><span class="rw-sub" style="display:block">${rec ? 'Opens only with the secret you saved' : 'For when you lose every device. Only a secret you keep opens it.'}</span></span>${rec ? `<span class="tag success">${icon('check', 'bold')}Today</span>` : '<button class="btn secondary" style="height:38px" data-go="recovery">Create</button>'}</div></div>
        ${danger([row({ icon: 'trash', title: 'Delete my server backup', danger: true, attrs: 'data-delete' })], 'Deletes the copy on the server only. Your devices keep their messages.')}`);
    },
    mount(el, params, entry) {
      const st = entry.state; wirePrefs(el, entry);
      el.querySelector('[data-backup]').addEventListener('click', () => {
        st.running = true; st.failed = false; st.p = 0.1; entry.rerender();
        const tick = () => { if (!entry.el.isConnected) return; st.p = Math.min(1, st.p + 0.3); if (st.p >= 1) { st.running = false; st.justNow = true; } entry.rerender(); if (st.running) setTimeout(tick, 450); };
        setTimeout(tick, 450);
      });
      el.querySelector('[data-delete]').addEventListener('click', () => confirm('Delete the server backup?', 'Orbit deletes the encrypted backup it keeps for you. A new one is made on the next run if daily backup is on.', 'Delete', () => App.snack('Server backup deleted')));
    },
  });

  // ================================================================= Account
  reg({
    id: 'account', title: 'Account',
    entries: [
      { key: 'account', label: 'Account', params: {} },
      { key: 'account-nopass', label: 'Account · no password set', params: { noPassword: true } },
    ],
    render(params) {
      const pass = !params.noPassword;
      return page('Account', `
        <div class="hero-card"><div class="hc-top">${avatar({ name: Data.me.name, color: 0 }, 48)}<div class="hc-text"><div class="hc-title">${esc(Data.me.name)}</div><div class="hc-sub">${esc(Data.me.masked)} · ~${esc(Data.me.helixName)}</div></div></div>
          <div class="hc-pills"><span class="hc-pill ${pass ? 'ok' : 'warn'}">${icon(pass ? 'check-circle' : 'warning-circle', 'fill')}${pass ? 'Password set' : 'No password'}</span><span class="hc-pill">${icon('devices')}2 devices</span><span class="hc-pill">${icon('calendar-blank')}Since Sep 2026</span></div></div>
        ${section('Sign-in', [
          row({ icon: 'password', color: 0, title: pass ? 'Change password' : 'Set a password', sub: pass ? 'Changed 3 weeks ago' : 'Sign in on a new phone without another device', end: 'chevron', attrs: `data-go="password" data-params='${JSON.stringify({ set: !pass })}'` }),
          row({ icon: 'clock-counter-clockwise', color: 7, title: 'Security activity', sub: 'Sign-ins, new devices and key changes', end: 'chevron', attrs: 'data-go="activity"' }),
        ], 'Your password never leaves this phone. Orbit only receives a key made from it.')}
        ${section('Your data', [row({ icon: 'export', color: 2, title: 'Export my data', sub: 'Account details, devices and settings. No messages: the server never had them readable.', end: 'chevron', attrs: 'data-export' })])}
        ${danger([
          row({ icon: 'sign-out', title: 'Sign out', sub: 'Removes this phone and deletes its messages', danger: true, attrs: 'data-signout' }),
          row({ icon: 'trash', title: 'Delete my account', sub: 'Permanent, for every device', danger: true, attrs: 'data-delete' }),
        ])}`);
    },
    mount(el, params, entry) {
      wire(el, entry);
      el.querySelector('[data-export]').addEventListener('click', () => App.snack('Opens the share sheet with orbit-account.json'));
      el.querySelector('[data-signout]').addEventListener('click', () => confirm('Sign out?', 'This removes Orbit from this phone and deletes its messages, keys and history. Your other devices stay signed in.', 'Sign out', () => App.reset('signin', { step: 'phone' })));
      el.querySelector('[data-delete]').addEventListener('click', () => App.dialog({ title: 'Delete your account?', text: 'Your account, devices and server data are deleted for good. Want a copy of your account data first?', actions: [{ label: 'Cancel' }, { label: 'Export first', run: () => App.snack('Export saved') }, { label: 'Continue', kind: 'danger', run: () => App.push('delete-account') }] }));
    },
  });
})();
