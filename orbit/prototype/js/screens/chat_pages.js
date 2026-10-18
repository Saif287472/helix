/*
  Conversation sub-pages: forward, message info, media viewer (+ video player),
  send files, shared media, chat settings. Flutter: features/conversation/
  presentation/*. Copy from SCREENS.md.
*/
(() => {
  const { esc, icon, ibtn, avatar, row } = UI;
  const { section, sw, field, wire, confirm, notice } = Kit;
  const chatBase = (id = 'direct:nadia') => [{ screen: 'home', params: { tab: 'chats' } }, { screen: 'chat', params: { id } }];
  const titleOf = (id) => (Data.chats.find((c) => c.id === id) || {}).title || 'Chat';
  const avOf = (id) => (Data.chats.find((c) => c.id === id) || {}).avatar || { name: 'Chat' };

  // ------------------------------------------------------------------ forward
  App.register({
    id: 'forward', title: 'Forward', group: 'Conversation pages', order: 25,
    interactions: [
      ['tap', 'Chat row', 'Picks or unpicks it; several can be picked.'],
      ['type', 'Search', 'Filters the chats as you type.'],
      ['tap', 'Send to N chats', 'Sends, closes, and says “Forwarded”.'],
    ],
    entries: [
      { key: 'forward', label: 'Forward message', params: { n: 1 } },
      { key: 'forward-picked', label: 'Forward · chats picked', params: { n: 2, sel: ['group:family', 'direct:arif'] } },
    ].map((e) => ({ ...e, base: chatBase() })),
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, sel: new Set(params.sel || []), q: '' });
      const q = st.q.toLowerCase();
      const rows = Data.chats.filter((c) => c.title.toLowerCase().includes(q)).map((c) => `<button class="chat-row" style="height:64px" data-t="${esc(c.id)}">${avatar(c.avatar, 44)}<span class="cr-body"><span class="cr-name"><span class="nm">${esc(c.title)}</span></span></span><span class="pick ${st.sel.has(c.id) ? 'on' : ''}" style="border-radius:7px">${icon('check', 'bold')}</span></button>`).join('');
      const n = st.sel.size;
      return `${UI.appbar({ title: params.n > 1 ? `Forward ${params.n} messages` : 'Forward message' })}
        <div class="search" style="margin-top:10px">${icon('magnifying-glass')}<input id="fq" placeholder="Search chats and people" value="${esc(st.q)}" aria-label="Search chats and people" autocomplete="off"></div>
        <div class="scroll" data-keep-scroll="fw">${rows || UI.empty({ icon: 'magnifying-glass', title: 'No results' })}</div>
        ${n ? `<div class="bottom-bar"><button class="btn primary block" data-send>${st.busy ? '<i class="ph ph-spinner-gap spin"></i>' : icon('paper-plane-tilt', 'fill')}Send to ${n === 1 ? '1 chat' : `${n} chats`}</button></div>` : ''}`;
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelectorAll('[data-t]').forEach((b) => b.addEventListener('click', () => { st.sel.has(b.dataset.t) ? st.sel.delete(b.dataset.t) : st.sel.add(b.dataset.t); entry.rerender(); }));
      const q = el.querySelector('#fq'); q.addEventListener('input', () => { st.q = q.value; const p = q.selectionStart; entry.rerender(); const m = entry.el.querySelector('#fq'); m.focus(); m.setSelectionRange(p, p); });
      el.querySelector('[data-send]')?.addEventListener('click', () => { st.busy = true; entry.rerender(); setTimeout(() => { App.pop(); App.snack('Forwarded'); }, 700); });
    },
  });

  // ------------------------------------------------------------- message info
  App.register({
    id: 'message-info', title: 'Message info', group: 'Conversation pages', order: 25,
    interactions: [],
    entries: [
      { key: 'message-info', label: 'Message info (direct)', params: { id: 'direct:nadia' }, base: chatBase('direct:nadia') },
      { key: 'message-info-group', label: 'Message info (group)', params: { id: 'group:family' }, base: chatBase('group:family') },
      { key: 'message-info-gone', label: 'Message info · not found', params: { gone: true }, base: chatBase() },
    ],
    render(params) {
      if (params.gone) return Kit.page({ title: 'Message info', body: UI.empty({ icon: 'chat-circle-slash', title: 'Message not found', text: 'It may have been deleted.' }) });
      const group = params.id.startsWith('group:');
      const text = group ? 'Me too, landing Thursday night ✈️' : 'Here it is. The colour pages are 14 to 22';
      const people = group ? [['ammu', 'Read Sunday, 18:41'], ['abbu', 'Read Sunday, 18:52'], ['rumana', 'Delivered Sunday, 18:40'], ['karim', 'Not delivered yet']] : [['nadia', 'Read yesterday, 21:12']];
      return Kit.page({ title: 'Message info', body: `
        <div class="timeline" style="flex:none;padding:18px 14px;border-bottom:1px solid var(--line-2)">${UI.message({ id: 'x', outgoing: true, content: { type: 'text', text }, timeLabel: group ? '18:40' : '21:09', status: 'read' }, 'single')}</div>
        ${section('', [row({ icon: 'paper-plane-tilt', color: 0, title: 'Sent', sub: group ? 'Sunday, 18:40' : 'Yesterday, 21:09', tag: 'div' })])}
        ${section(group ? 'Recipients' : '', people.map(([id, s]) => `<div class="row">${avatar(Data.av(Data.people[id]), 40)}<span class="rw-body"><span class="rw-title" style="display:block">${esc(Data.displayName(Data.people[id]))}</span><span class="rw-sub" style="display:block">${s.startsWith('Read') ? `<span style="color:var(--read)">${icon('checks', 'bold')}</span> ` : s.startsWith('Delivered') ? `${icon('checks')} ` : ''}${s}</span></span></div>`))}` });
    },
    mount(el, params, entry) { wire(el, entry); },
  });

  // ------------------------------------------------------- media viewer / video
  const ITEMS = [
    { photo: 'ph-e', time: 'Today, 09:40' }, { photo: 'ph-c', time: 'Today, 09:40' }, { photo: 'ph-b', video: true, time: 'Today, 09:40' },
    { photo: 'ph-d', time: 'Today, 09:40' }, { photo: 'ph-a', time: 'Today, 09:40' }, { photo: 'ph-f', time: 'Today, 09:40' },
  ];
  App.register({
    id: 'media-viewer', title: 'Media viewer', group: 'Conversation pages', order: 25, night: true,
    interactions: [
      ['swipe-left', 'Picture', 'Next item.', 'phone'],
      ['swipe-right', 'Picture', 'Previous item.', 'phone'],
      ['tap', 'Previous / Next buttons', 'Previous or next item; the arrow keys do the same.', 'window'],
      ['key', '← / →', 'Previous or next item.', 'window'],
      ['tap', 'Play / Pause (video)', 'Plays or pauses; the controls hide after 3 s of playing.'],
      ['tap', 'Video', 'Shows or hides the controls.'],
      ['tap', 'Speed', 'Cycles 1x, 1.5x, 2x.'],
      ['tap', 'Share', 'Opens the system share sheet.'],
      ['tap', 'Open video (cannot play)', 'Opens the video in another app.'],
      ['tap', 'Play again (video played to the end)', 'Plays the video from the start.'],
      ['auto', 'Video buffering', 'A spinner where the play button is until the video can play.'],
    ],
    entries: [
      { key: 'media-viewer', label: 'Media viewer', params: { i: 0 } },
      { key: 'media-video', label: 'Video player', params: { i: 2 } },
      { key: 'media-video-failed', label: 'Video player · cannot play', params: { i: 2, failed: true } },
      { key: 'media-not-here', label: 'Media viewer · not on this device', params: { missing: true } },
      { key: 'media-cannot-show', label: 'Media viewer · picture cannot be shown', params: { cannotShow: true } },
      { key: 'media-video-buffering', label: 'Video player · buffering', params: { i: 2, buffering: true } },
      { key: 'media-video-ended', label: 'Video player · played to the end', params: { i: 2, ended: true } },
      { key: 'media-viewonce-opened', label: 'View once · already opened', params: { viewOnce: 'opened' } },
      { key: 'media-viewonce-mine', label: 'View once · your own', params: { viewOnce: 'mine' } },
    ].map((e) => ({ ...e, base: chatBase() })),
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, i: params.i || 0, playing: false, speed: 1, ctrl: true });
      const back = `<header class="appbar">${ibtn('arrow-left', 'Back', 'data-back')}<div class="ab-title"><h1 style="font-size:16px">${params.viewOnce === 'mine' ? 'View once' : 'Nadia Rahman'}</h1><div class="ab-sub">${params.missing || params.viewOnce ? '' : `${ITEMS[st.i].time} (${st.i + 1} of ${ITEMS.length})`}</div></div>${params.missing || params.viewOnce ? '' : ibtn('share-network', 'Share', 'data-share')}</header>`;
      const msg = (t) => `${back}<div class="mv-stage"><p style="color:#C9D0DF;text-align:center;max-width:260px;line-height:1.5">${t}</p></div>`;
      if (params.missing) return msg('This file is not on your device yet.');
      if (params.cannotShow) return msg('This picture cannot be shown.');
      if (params.viewOnce === 'opened') return msg('This view-once message has already been opened.');
      if (params.viewOnce === 'mine') return msg('You cannot open a view-once message you sent.');
      const it = ITEMS[st.i];
      let stage;
      if (it.video) {
        stage = params.failed
          ? `<div style="text-align:center;color:#C9D0DF;padding:24px">${icon('warning-circle')}<p style="line-height:1.5">This video cannot be played.</p><button class="btn secondary" style="background:#1B2236;border-color:#2B3550;color:#fff" data-snack="Opens the share sheet">Open video</button></div>`
          : params.buffering ? `<div class="mv-img ${it.photo}" data-tap></div><span class="vp-big" role="status" aria-label="Loading the video"><i class="ph ph-spinner-gap spin"></i></span>`
          : params.ended && !st.replayed ? `<div class="mv-img ${it.photo}" data-tap></div><button class="vp-big" data-replay title="Play again" aria-label="Play again">${icon('arrow-counter-clockwise', 'bold')}</button>`
          : `<div class="mv-img ${it.photo}" data-tap></div>${st.ctrl ? `<button class="vp-big" data-play title="${st.playing ? 'Pause' : 'Play'}" aria-label="${st.playing ? 'Pause' : 'Play'}">${icon(st.playing ? 'pause' : 'play', 'fill')}</button>
            <div class="vp-ctrl"><span>${st.playing ? '0:07' : '0:00'}</span><input type="range" min="0" max="24" value="${st.playing ? 7 : 0}" aria-label="Seek"><span>0:24</span><button class="speedb" data-speed title="Playback speed">${st.speed}x</button></div>` : ''}`;
      } else stage = `<div class="mv-img ${it.photo}"></div>`;
      // A window has no swipe: previous and next buttons sit at the sides (and the arrow keys work).
      const nav = App.isWide() ? `${st.i > 0 ? ibtn('caret-left', 'Previous', 'data-step="-1"', 'mv-nav prev') : ''}${st.i < ITEMS.length - 1 ? ibtn('caret-right', 'Next', 'data-step="1"', 'mv-nav next') : ''}` : '';
      return `${back}<div class="mv-stage" data-swipe>${stage}${nav}<div class="mv-dots">${ITEMS.map((_, j) => `<b class="${j === st.i ? 'on' : ''}"></b>`).join('')}</div></div>${st.i === 0 ? '<div class="mv-cap">Sunset at Inani beach 🌅</div>' : '<div style="height:34px"></div>'}`;
    },
    mount(el, params, entry) {
      const st = entry.state; el.classList.add('viewer-page'); wire(el, entry);
      el.querySelector('[data-share]')?.addEventListener('click', () => App.snack('Opens the share sheet'));
      el.querySelector('[data-play]')?.addEventListener('click', () => { st.playing = !st.playing; entry.rerender(); if (st.playing) setTimeout(() => { if (entry.el.isConnected && st.playing) { st.ctrl = false; entry.rerender(); } }, 3000); });
      el.querySelector('[data-tap]')?.addEventListener('click', () => { st.ctrl = !st.ctrl; entry.rerender(); });
      el.querySelector('[data-replay]')?.addEventListener('click', () => { st.replayed = true; st.playing = true; entry.rerender(); });
      el.querySelector('[data-speed]')?.addEventListener('click', () => { st.speed = st.speed === 1 ? 1.5 : st.speed === 1.5 ? 2 : 1; entry.rerender(); });
      const step = (d) => { const i = Math.max(0, Math.min(ITEMS.length - 1, st.i + d)); if (i === st.i) return; st.i = i; st.playing = false; st.ctrl = true; entry.rerender(); };
      el.querySelectorAll('[data-step]').forEach((b) => b.addEventListener('click', () => step(+b.dataset.step)));
      if (!st.keys) {
        st.keys = (e) => { if (!entry.el.isConnected) { document.removeEventListener('keydown', st.keys); return; } if (e.key === 'ArrowLeft') step(-1); if (e.key === 'ArrowRight') step(1); };
        document.addEventListener('keydown', st.keys);
      }
      const sw2 = el.querySelector('[data-swipe]');
      if (sw2) {
        let x0 = null;
        sw2.addEventListener('pointerdown', (e) => { if (e.target.closest('input, button')) return; x0 = e.clientX; });
        sw2.addEventListener('pointerup', (e) => { if (x0 == null) return; const d = e.clientX - x0; x0 = null; if (Math.abs(d) < 50) return; st.i = Math.max(0, Math.min(ITEMS.length - 1, st.i + (d < 0 ? 1 : -1))); st.playing = false; st.ctrl = true; entry.rerender(); });
      }
    },
  });

  // --------------------------------------------------------------- send files
  App.register({
    id: 'send-files', title: 'Send files', group: 'Conversation pages', order: 25,
    interactions: [
      ['tap', '× on a file', 'Removes it from what will be sent.'],
      ['tap', 'View once', 'Turns view once on or off.'],
      ['type', 'Caption', 'Adds a caption.'],
      ['tap', 'Send', 'Sends and returns to the chat.'],
    ],
    entries: [
      { key: 'send-files', label: 'Send files', params: {} },
      { key: 'send-files-empty', label: 'Send files · nothing left', params: { empty: true } },
    ].map((e) => ({ ...e, base: chatBase() })),
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, viewOnce: false, files: params.empty ? [] : [
        { name: 'IMG_2041.jpg', size: '2.4 MB', photo: 'ph-e' }, { name: 'VID_0310.mp4', size: '18.1 MB', photo: 'ph-b', video: true }, { name: 'Invoice October.pdf', size: '312 KB', icon: 'file-pdf' },
      ] });
      const n = st.files.length;
      if (!n) return Kit.page({ title: 'Send file', body: UI.empty({ icon: 'paperclip', title: 'Nothing to send', text: 'Go back and pick a file.' }) });
      const media = st.files.some((f) => f.photo);
      return `${UI.appbar({ title: n === 1 ? 'Send file' : `Send ${n} files` })}
        <div class="scroll" style="padding-bottom:16px"><div style="height:14px"></div><div class="card">${st.files.map((f, i) => `<div class="row file-row">${f.photo ? `<span class="rw-ico thumb ${f.photo}" style="display:grid;place-items:center;color:#fff">${f.video ? icon('play', 'fill') : ''}</span>` : `<span class="rw-ico thumb av-3">${icon(f.icon, 'fill')}</span>`}<span class="rw-body"><span class="rw-title" style="display:block">${esc(f.name)}</span><span class="rw-sub mono" style="display:block">${f.size}</span></span>${ibtn('x', `Remove ${f.name}`, `data-rm="${i}"`)}</div>`).join('')}</div>
        ${media ? section('', [row({ icon: 'number-circle-one', color: 0, title: 'View once', sub: 'Photos and videos disappear after they are opened.', end: 'switch', on: st.viewOnce, attrs: 'data-switch data-vo' })]) : ''}
        <p class="sec-foot" style="display:flex;gap:6px">${icon('shield-check')}<span>Location details are removed from photos and videos before they are sent.</span></p></div>
        <div class="bottom-bar"><div class="field" style="flex:1;min-height:48px;border-radius:24px;background:var(--field);display:flex;align-items:center;padding:0 16px"><input placeholder="Add a caption" aria-label="Add a caption" style="flex:1;border:0;outline:0;background:none;font-size:15px"></div><button class="send-btn" data-send title="Send" aria-label="Send">${st.busy ? '<i class="ph ph-spinner-gap spin"></i>' : icon('paper-plane-tilt', 'fill')}</button></div>`;
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelectorAll('[data-rm]').forEach((b) => b.addEventListener('click', () => { st.files.splice(+b.dataset.rm, 1); entry.rerender(); }));
      el.querySelector('[data-vo]')?.addEventListener('toggle', (e) => { st.viewOnce = e.detail; });
      el.querySelector('[data-send]')?.addEventListener('click', () => { st.busy = true; entry.rerender(); setTimeout(() => App.pop(), 600); });
    },
  });

  // ------------------------------------------------------------- shared media
  App.register({
    id: 'shared', title: 'Media, links and docs', group: 'Conversation pages', order: 25,
    interactions: [
      ['tap', 'Media / Links / Docs', 'Switches the tab.'],
      ['tap', 'Photo or video', 'Opens the media viewer at it.'],
      ['tap', 'Back to the chat (empty state)', 'Returns to the chat.'],
    ],
    entries: [
      { key: 'shared', label: 'Media, links and docs', params: { id: 'direct:nadia', tab: 'media' } },
      { key: 'shared-docs', label: 'Shared · docs', params: { id: 'direct:nadia', tab: 'docs' } },
      { key: 'shared-links', label: 'Shared · links', params: { id: 'direct:nadia', tab: 'links' } },
      { key: 'shared-empty', label: 'Shared · nothing yet', params: { id: 'direct:arif', tab: 'media', empty: true } },
      { key: 'shared-docs-empty', label: 'Shared · no documents yet', params: { id: 'direct:arif', tab: 'docs', empty: true } },
      { key: 'shared-links-empty', label: 'Shared · no links yet', params: { id: 'direct:arif', tab: 'links', empty: true } },
    ].map((e) => ({ ...e, base: chatBase(e.params.id) })),
    render(params, entry) {
      const st = entry.state; st.tab = st.tab || params.tab;
      const tabs = `<div class="tabs">${[['media', 'Media'], ['docs', 'Docs'], ['links', 'Links']].map(([k, l]) => `<button class="${st.tab === k ? 'on' : ''}" data-tab3="${k}">${l}</button>`).join('')}</div>`;
      let body;
      // Each tab has its own empty state (Review 1).
      if (params.empty) {
        body = {
          media: UI.empty({ icon: 'images', title: 'No media yet', text: 'Photos and videos you share in this chat show up here.' }),
          docs: UI.empty({ icon: 'file-text', title: 'No documents yet', text: 'Files you share in this chat show up here.' }),
          links: UI.empty({ icon: 'link-simple', title: 'No links yet', text: 'Web links sent in this chat show up here.' }),
        }[st.tab];
      }
      else if (st.tab === 'media') body = `<div class="sm-grid">${['ph-e', 'ph-c', 'ph-b', 'ph-d', 'ph-a', 'ph-f', 'ph-c', 'ph-e', 'ph-d'].map((p, i) => `<span class="mi ${p}" data-open="${i % 6}">${i === 2 || i === 7 ? `<span class="dur">${icon('play-circle', 'fill')}0:24</span>` : ''}</span>`).join('')}</div>`;
      else if (st.tab === 'docs') body = `<div style="height:12px"></div><div class="card">${[['Launch deck v3.pdf', '4.2 MB · PDF · Yesterday'], ['Venue floor plan.png', '880 KB · PNG · 3 Oct']].map(([n, d]) => row({ icon: 'file-text', color: 3, weight: 'fill', title: esc(n), sub: d, attrs: 'data-snack="Opens the share sheet"' })).join('')}</div>`;
      else body = `<div style="height:12px"></div><div class="card">${[['https://helix.agiletechbd.com/blog/v2', 'helix.agiletechbd.com, today'], ['https://maps.google.com/?q=Inani+Beach', 'maps.google.com, yesterday']].map(([u, d]) => `<div class="row">${`<span class="rw-ico av-1">${icon('link-simple')}</span>`}<span class="rw-body"><span class="rw-title mono" style="display:block;font-size:12.5px;word-break:break-all">${esc(u)}</span><span class="rw-sub" style="display:block">${d}</span></span>${ibtn('chat-circle', 'Show in chat', 'data-pop')}</div>`).join('')}</div>`;
      return `${UI.appbar({ title: titleOf(params.id) })}${tabs}<div class="scroll">${body}</div>`;
    },
    mount(el, params, entry) {
      wire(el, entry);
      el.querySelectorAll('[data-tab3]').forEach((b) => b.addEventListener('click', () => { entry.state.tab = b.dataset.tab3; entry.rerender(); }));
      el.querySelectorAll('[data-open]').forEach((b) => b.addEventListener('click', () => App.push('media-viewer', { i: +b.dataset.open })));
      el.querySelectorAll('[data-pop]').forEach((b) => b.addEventListener('click', App.pop));
    },
  });

  // ------------------------------------------------------------ chat settings
  App.register({
    id: 'chat-settings', title: 'Chat settings', group: 'Conversation pages', order: 25,
    interactions: [
      ['tap', 'Mute notifications', 'Sheet: 8 hours, 1 week, Always, and Unmute while muted.'],
      ['tap', 'Disappearing messages', 'Sheet: Off, 5 minutes, 1 hour, 1 day, 1 week, 90 days.'],
      ['tap', 'Clear chat', 'Asks first, then removes the messages from this device.'],
      ['tap', 'Block / Unblock', 'Block asks first; unblock happens at once.'],
    ],
    entries: [
      { key: 'chat-settings', label: 'Chat settings (direct)', params: { id: 'direct:nadia' } },
      { key: 'chat-settings-group', label: 'Chat settings (group)', params: { id: 'group:family' } },
      { key: 'chat-settings-blocked', label: 'Chat settings · blocked', params: { id: 'direct:shuvo' } },
    ].map((e) => ({ ...e, base: chatBase(e.params.id) })),
    render(params, entry) {
      const id = params.id; const group = id.startsWith('group:');
      const pid = id.split(':')[1]; const p = Data.people[pid];
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, muted: false, disappearing: group ? '1 week' : 'Off', blocked: !!(p && p.blocked) });
      const title = group ? titleOf(id) : Data.displayName(p);
      const sub = group ? '5 members' : p.online ? 'online' : Data.secondary(p) || '';
      return Kit.page({ title: 'Chat settings', body: `
        <div class="hero">${avatar(group ? avOf(id) : Data.av(p), 72)}<div class="h-name">${esc(title)}</div><div class="h-sub">${esc(sub)}</div></div>
        ${section('', [
          group ? row({ icon: 'users-three', color: 0, title: 'Group info', sub: 'Members, invite links and group settings', end: 'chevron', attrs: 'data-go="group-info" data-params=\'{"role":"admin"}\'' })
            : row({ icon: 'user-circle', color: 0, title: 'Contact info', sub: 'Name, number and safety number', end: 'chevron', attrs: `data-go="contact" data-params='{"id":"${pid}"}'` }),
          row({ icon: 'images', color: 2, title: 'Media, links and docs', end: 'chevron', attrs: `data-go="shared" data-params='{"id":"${id}","tab":"media"}'` }),
          row({ icon: 'bell-slash', color: 4, title: 'Mute notifications', sub: st.muted ? 'Muted' : 'Off', end: 'chevron', attrs: 'data-mute' }),
          row({ icon: 'timer', color: 5, title: 'Disappearing messages', value: st.disappearing, end: 'chevron', attrs: 'data-dm' }),
        ])}
        ${section('', [
          row({ icon: 'eraser', title: 'Clear chat', danger: true, attrs: 'data-clear' }),
          ...(group ? [] : [st.blocked ? row({ icon: 'prohibit', title: `Unblock ${esc(title)}`, attrs: 'data-block' }) : row({ icon: 'prohibit', title: `Block ${esc(title)}`, danger: true, attrs: 'data-block' })]),
        ])}` });
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      const pid = params.id.split(':')[1]; const n = Data.people[pid] ? Data.displayName(Data.people[pid]) : '';
      el.querySelector('[data-mute]').addEventListener('click', () => App.sheet({ title: 'Mute notifications', items: [
        ...['8 hours', '1 week', 'Always'].map((o) => ({ icon: 'bell-slash', label: o, run: () => { st.muted = true; entry.rerender(); } })),
        ...(st.muted ? [{ icon: 'speaker-high', label: 'Unmute', run: () => { st.muted = false; entry.rerender(); } }] : []),
      ] }));
      el.querySelector('[data-dm]').addEventListener('click', () => App.sheet({ title: 'Disappearing messages', items: ['Off', '5 minutes', '1 hour', '1 day', '1 week', '90 days'].map((o) => ({ icon: 'timer', label: o, on: st.disappearing === o, run: () => { st.disappearing = o; entry.rerender(); } })) }));
      el.querySelector('[data-clear]').addEventListener('click', () => confirm('Clear this chat?', 'All messages are removed from this device. The chat stays in your list.', 'Clear', () => App.snack('Chat cleared')));
      el.querySelector('[data-block]')?.addEventListener('click', () => {
        if (st.blocked) { st.blocked = false; entry.rerender(); return; }
        confirm(`Block ${n}?`, 'They will not be able to message or call you, and Orbit tells them that you blocked them. You can unblock them here at any time.', 'Block', () => { st.blocked = true; entry.rerender(); });
      });
    },
  });
})();
