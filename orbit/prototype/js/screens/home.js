/*
  Home: three swipeable tabs (Chats, Calls, Settings) under a floating dock,
  with the round "new" button beside it. Flutter: HomeScreen + HelixDock.
  Copy and behaviour follow SCREENS.md (the real app).
*/
(() => {
  const { esc, icon, ibtn, avatar, chatRow, callRow, row, card, empty } = UI;
  const TABS = ['chats', 'calls'];

  // Your avatar, top-left of each tab: opens Settings (the dock has no Settings tab).
  const meButton = () => {
    const you = window.HelixYouState;
    const attention = you && (!you.recovery || !you.lock);
    return `<button class="me-pic" data-settings title="Your profile and settings" aria-label="Your profile and settings${attention ? ', privacy checkup needs attention' : ''}"><span class="me-ring">${avatar({ name: Data.me.name, seed: 'me', color: 0 }, 36)}</span>${attention ? '<span class="me-dot" aria-hidden="true"></span>' : ''}</button>`;
  };
  // The app's wordmark replaces the tab titles; the dock says which tab you are on.
  const wordmark = '<h1 class="wordmark">Orbit</h1>';
  const S = { pinned: new Set(['direct:nadia', 'group:family']), contacts: 'ask' };

  // ============================================================ People panel
  // The shared PeoplePanel seam: Chats search (mode chats) and Calls search (mode calls).
  function peoplePanel(q, mode, st) {
    const query = q.trim();
    const all = Object.values(Data.people).filter((p) => p.id !== 'unknown');
    const groups = Data.chats.filter((c) => c.id.startsWith('group:'));
    const personRow = (p) => {
      const sub = p.blocked ? '<span style="color:var(--danger)">Blocked</span>' : esc(Data.secondary(p) || p.about || '');
      const calls = mode === 'calls' ? ibtn('phone', `Voice call ${Data.displayName(p)}`, `data-place="${p.id}"`, 'accent') + ibtn('video-camera', `Video call ${Data.displayName(p)}`, `data-place-video="${p.id}"`, 'accent') : '';
      return `<div class="chat-row" data-person="${esc(p.id)}" role="button" tabindex="0">${avatar(Data.av(p), 52)}<span class="cr-body"><span class="cr-top"><span class="cr-name"><span class="nm">${esc(Data.displayName(p))}</span>${p.verified ? '<i class="ph-fill ph-seal-check seal"></i>' : ''}</span></span><span class="cr-bottom"><span class="cr-preview mono" style="font-size:12px">${sub}</span></span></span>${calls}</div>`;
    };

    let html = '';
    if (!query) {
      if (S.contacts === 'ask' || S.contacts === 'denied') {
        html += `<div class="banner accent">${icon('address-book', 'fill')}<div class="bn-body"><div class="bn-title">Find your contacts on Orbit</div>
          Orbit compares scrambled versions of your contacts’ numbers to find who is on Orbit. Your contacts never leave your phone.
          <div class="bn-actions"><button class="btn ghost" data-allow-contacts>${S.contacts === 'denied' ? 'Open settings' : 'Allow contacts'}</button></div></div></div>`;
      } else {
        const sub = { checking: 'Checking your contacts...', limit: 'Today’s limit for checking contacts is used up. Orbit will try again tomorrow.', done: '7 contacts are on Orbit.' }[S.contacts] || 'Check which of your contacts are on Orbit.';
        html += `<div class="card" style="margin-top:8px">${row({ icon: 'arrows-clockwise', color: 0, title: 'Refresh contacts', sub, attrs: 'data-refresh-contacts' })}</div>`;
      }
      const known = ['nadia', 'arif', 'sadia', 'tanvir', 'ammu', 'abbu', 'rumana', 'karim'].map((id) => Data.people[id]);
      html += `<div class="list-label"><span class="eyebrow">People on Orbit<span class="count">${known.length}</span></span></div>${known.map(personRow).join('')}`;
      return html;
    }

    const lc = query.toLowerCase();
    const digits = query.replace(/[^\d+]/g, '');
    const looksNumber = /^[+\d][\d\s-]*$/.test(query) && digits.replace('+', '').length >= 3;
    const isHelixName = query.startsWith('~') && query.length > 1;
    const lookupRow = (label, ic) => `<button class="chat-row" data-lookup="${esc(label)}"><span class="av" style="--size:52px;background:var(--accent-soft);color:var(--accent)">${icon(ic, 'bold')}</span>
      <span class="cr-body"><span class="cr-name"><span class="nm">Find ${esc(label)} on Orbit</span></span><span class="cr-preview">${ic === 'at' ? 'Looks up this ~Orbit name once.' : 'Only a scrambled version of the number is sent.'}</span></span></button>`;
    if (st.lookup) {
      const states = {
        searching: ['spinner-gap', 'Looking on Orbit...', ''],
        none: ['user-circle-dashed', 'Not on Orbit', 'Nobody on Orbit matches that, or they do not let people find them this way.'],
        self: ['user-circle', 'That is you', 'This is your own account.'],
        limit: ['hourglass-medium', 'Too many lookups', 'You have looked up as many numbers as Orbit allows today. Try again tomorrow.'],
        offline: ['wifi-slash', 'No connection', 'Check your connection and try again.'],
      };
      const [ic, t, sub] = states[st.lookup];
      html += `<div class="lookup-state"><span class="ls-ico">${icon(ic)}</span><span><span class="ls-title" style="display:block">${t}</span>${sub ? `<span class="ls-sub" style="display:block">${sub}</span>` : ''}</span></div>`;
    } else if (isHelixName) html += lookupRow(query, 'at');
    else if (looksNumber) {
      const complete = query.trim().startsWith('+') && digits.length >= 12;
      html += complete ? lookupRow(query.trim(), 'dots-nine')
        : `<div class="hint-line">${icon('info')}<span>To find someone by number, type the whole number, starting with the country code, like +880 1711 000001.</span></div>`;
    }
    const gHits = groups.filter((g) => g.title.toLowerCase().includes(lc));
    const pHits = all.filter((p) => Data.displayName(p).toLowerCase().includes(lc) || (p.names.number || '').replace(/\D/g, '').includes(lc.replace(/\D/g, '') || 'x'));
    if (gHits.length) html += `<div class="list-label"><span class="eyebrow">Groups</span></div>${gHits.map((g) => `<button class="chat-row" data-chat="${esc(g.id)}">${avatar(g.avatar, 52)}<span class="cr-body"><span class="cr-name"><span class="nm">${esc(g.title)}</span></span><span class="cr-preview">Group</span></span></button>`).join('')}`;
    if (pHits.length) html += `<div class="list-label"><span class="eyebrow">People</span></div>${pHits.map(personRow).join('')}`;
    if (!html && !looksNumber && !isHelixName) html += empty({ icon: 'magnifying-glass', title: 'No matches', text: `Nobody you know matches “${esc(query)}”.` });
    return html;
  }

  // ================================================================ Chats tab
  function chatsHeader(st) {
    if (st.selected.size) {
      return `<header class="appbar selection">${ibtn('x', 'Cancel selection', 'data-sel-cancel')}
        <div class="ab-title"><h1>${st.selected.size} selected</h1></div>
        ${ibtn('archive', 'Archive chats', 'data-sel="archive"')}${ibtn('trash', 'Delete chats', 'data-sel="delete"')}${ibtn('dots-three-vertical', 'More options', 'data-sel="more"')}</header>`;
    }
    return `<div class="tab-head"><div class="tab-head-top">${wordmark}
      <div class="tab-actions">${ibtn('magnifying-glass', 'Search', 'data-search-open')}${ibtn('dots-three-vertical', 'More options', 'data-chats-menu')}${meButton()}</div></div></div>`;
  }

  function chatSearch(st) {
    const q = (st.query || '').trim();
    const lc = q.toLowerCase();
    let html = '';
    if (q) {
      const chats = Data.chats.concat(Data.archived).filter((c) => c.title.toLowerCase().includes(lc));
      if (chats.length) html += `<div class="list-label"><span class="eyebrow">Chats</span></div>${chats.map((c) => chatRow(c, { showArchived: true })).join('')}`;
    }
    html += peoplePanel(st.query || '', 'chats', st);
    if (q) {
      const hits = [];
      Object.entries(Data.conversations).forEach(([cid, conv]) => conv.items.forEach((it) => {
        const t = it.kind === 'msg' && it.m.content.type === 'text' ? it.m.content.text : '';
        if (t && t.toLowerCase().includes(lc)) hits.push({ chat: Data.chats.find((c) => c.id === cid), m: it.m });
      }));
      const hl = (t) => { const i = t.toLowerCase().indexOf(lc); return i < 0 ? esc(t) : `${esc(t.slice(0, i))}<b style="color:var(--accent-ink)">${esc(t.slice(i, i + lc.length))}</b>${esc(t.slice(i + lc.length))}`; };
      if (hits.length) html += `<div class="list-label"><span class="eyebrow">Messages</span></div>${hits.map(({ chat, m }) =>
        `<button class="chat-row" data-chat="${esc(chat.id)}" data-jump="${esc(m.id)}">${avatar(chat.avatar, 52)}<span class="cr-body"><span class="cr-top"><span class="cr-name"><span class="nm">${esc(chat.title)}</span></span><span class="cr-time">${esc(m.timeLabel)}</span></span><span class="cr-bottom"><span class="cr-preview"><span class="who">${m.outgoing ? 'You' : esc(m.authorName || chat.title.split(' ')[0])}:</span><span class="pv-text">${hl(m.content.text)}</span></span></span></span></button>`).join('')}`;
    }
    return html;
  }

  function chatsPane(params, st) {
    if (st.searching) {
      return `<div class="pane-col">
        <header class="appbar" style="background:var(--bg);border-bottom:0">${ibtn('arrow-left', 'Close search', 'data-search-close')}
          <div class="search" style="flex:1;margin:0 8px 0 0">${icon('magnifying-glass')}<input id="chatSearch" placeholder="Search chats, messages and people" value="${esc(st.query || '')}" aria-label="Search chats, messages and people" autocomplete="off" enterkeyhint="search">${st.query ? ibtn('x', 'Clear search', 'data-search-clear', 'sm') : ''}</div></header>
        <div class="scroll" data-keep-scroll="chat-search" style="padding-bottom:40px">${chatSearch(st)}</div></div>`;
    }
    if (params.empty) {
      return `<div class="pane-col">${chatsHeader(st)}<div class="scroll">${empty({ icon: 'chats-circle', title: 'No chats yet', text: 'Search for a name or a number to start a secure conversation. Anyone on Orbit can message you unless you block them.', action: `<button class="btn primary" data-search-open style="margin-top:8px">${icon('magnifying-glass', 'bold')}Find people</button>` })}</div></div>`;
    }
    const list = Data.chats.map((c) => ({ ...c, pinned: S.pinned.has(c.id) }));
    // Filters (user decision 2026-10-16): All, Unread, Groups. Local only: no engine change.
    const FILTERS = { all: () => true, unread: (c) => c.unreadCount > 0, groups: (c) => c.id.startsWith('group:') };
    const filter = st.filter || 'all';
    const shown = list.filter(FILTERS[filter]);
    const count = (k) => list.filter(FILTERS[k]).length;
    const chips = `<div class="chips chat-filters" role="tablist" aria-label="Filter chats">${[['all', 'All'], ['unread', 'Unread'], ['groups', 'Groups']].map(([k, l]) =>
      `<button class="chip ${filter === k ? 'on' : ''}" role="tab" aria-selected="${filter === k}" data-filter="${k}">${l}${k === 'all' ? '' : `<span class="chip-n">${count(k)}</span>`}</button>`).join('')}</div>`;
    const ordered = [...shown.filter((c) => c.pinned), ...shown.filter((c) => !c.pinned)];
    const rows = ordered.map((c) => `<div class="swipe-wrap"><div class="swipe-bg"><span class="sw-start">${icon('push-pin', 'fill')}${c.pinned ? 'Unpin' : 'Pin'}</span><span class="sw-end">${icon('archive', 'fill')}Archive</span></div>${chatRow(c, { selected: st.selected.has(c.id) })}</div>`).join('');
    const none = filter === 'unread'
      ? empty({ icon: 'checks', title: 'No unread chats', text: 'You’re all caught up. New messages show up here until you read them.' })
      : empty({ icon: 'users-three', title: 'No groups yet', text: 'Start a group from the menu, or join one with a link.', action: `<button class="btn primary" data-new-group style="margin-top:8px">${icon('users-three', 'bold')}New group</button>` });
    return `<div class="pane-col">${chatsHeader(st)}${chips}
      <div class="scroll" data-keep-scroll="chats" style="padding-bottom:120px">
        ${rows || none}
      </div></div>`;
  }

  // ================================================================ Calls tab
  function callsPane(params, st) {
    if (st.callSearching) {
      return `<div class="pane-col"><header class="appbar" style="background:var(--bg);border-bottom:0">${ibtn('arrow-left', 'Close search', 'data-call-search-close')}
        <div class="search" style="flex:1;margin:0 8px 0 0">${icon('magnifying-glass')}<input id="callSearch" placeholder="Search people" value="${esc(st.callQuery || '')}" aria-label="Search people" autocomplete="off" enterkeyhint="search">${st.callQuery ? ibtn('x', 'Clear search', 'data-call-search-clear', 'sm') : ''}</div></header>
        <div class="scroll" data-keep-scroll="call-search" style="padding-bottom:40px">${peoplePanel(st.callQuery || '', 'calls', st)}</div></div>`;
    }
    const head = `<div class="tab-head"><div class="tab-head-top">${wordmark}<div class="tab-actions">${ibtn('magnifying-glass', 'Search', 'data-call-search-open')}${meButton()}</div></div></div>`;
    if (params.callsEmpty) {
      return `<div class="pane-col">${head}<div class="scroll">${quick()}${empty({ icon: 'phone', title: 'No calls yet', text: 'Calls you make and receive will show up here.' })}</div></div>`;
    }
    return `<div class="pane-col">${head}
      <div class="scroll" data-keep-scroll="calls" style="padding-bottom:120px">${quick()}
        <div class="list-label"><span class="eyebrow">Recent</span></div>${Data.calls.map(callRow).join('')}
      </div></div>`;
  }

  function quick() {
    const recents = [Data.people.nadia, Data.people.ammu];
    return `<div class="quick">
      <button class="quick-item" data-call-search-open title="Call"><span class="q-ico">${icon('phone-plus')}</span><span class="q-lbl">Call</span></button>
      <button class="quick-item" data-dialpad title="Keypad"><span class="q-ico">${icon('dots-nine', 'bold')}</span><span class="q-lbl">Keypad</span></button>
      ${recents.map((p) => `<button class="quick-item" data-place="${p.id}" title="Call ${esc(Data.displayName(p))}">${avatar(Data.av(p), 56)}<span class="q-lbl">${esc(Data.displayName(p).split(' ')[0])}</span></button>`).join('')}
    </div>`;
  }

  // ===================================================================== dock
  function dock(tab, st) {
    const item = (t, ic, label) => `<button class="dock-item ${tab === t ? 'on' : ''}" data-tab="${t}" title="${label}" aria-label="${label}">${icon(ic, tab === t ? 'fill' : '')}<span class="lbl">${label}</span></button>`;
    const fab = tab === 'chats' ? ['chat-circle-dots', 'New chat'] : ['phone-plus', 'New call'];
    const hide = st.selected.size || st.searching || st.callSearching;
    return `<div class="dock-area ${hide ? 'hidden' : ''}"><nav class="dock" aria-label="Main">${item('chats', 'chats-circle', 'Chats')}${item('calls', 'phone', 'Calls')}</nav>
      <button class="fab" data-fab title="${fab[1]}" aria-label="${fab[1]}">${icon(fab[0], 'bold')}</button></div>`;
  }

  // =============================================================== the screen
  App.register({
    id: 'home', title: 'Chats', group: 'Home', order: 10, refreshOnReturn: true,
    interactions: [
      ['tap', 'Dock tab', 'Switches between Chats and Calls.'],
      ['swipe', 'Tabs', 'Swipes between Chats and Calls.', 'phone'],
      ['tap', 'Profile picture', 'Opens You.'],
      ['tap', 'Round button', 'Chats: opens the search to start a chat. Calls: opens the people search to call.'],
      ['tap', 'Filter chip', 'All, Unread or Groups.'],
      ['tap', '⋮', 'Menu: New group, Join a group with a link, Archived chats (N).'],
      ['tap', 'Chat row', 'Opens the chat. On a window it opens on the right and the row stays marked.'],
      ['swipe-right', 'Chat row', 'Pins or unpins it.'],
      ['swipe-left', 'Chat row', 'Archives it, with Undo.'],
      ['long-press', 'Chat row', 'Starts selecting; tap more rows to add or remove them.'],
      ['right-click', 'Chat row', 'Starts selecting.'],
      ['tap', 'Selection bar', 'Archive (with Undo), Delete (asks), ⋮ for Pin, Mute (sheet), Mark as read; × stops.'],
      ['type', 'Search', 'Finds chats, people and messages as you type; × clears; ← closes.'],
      ['key', 'Enter in the search', 'Looks up a full number or ~name: searching, then the result or why not.'],
      ['tap', 'Allow contacts / Refresh contacts', 'Checking, then how many contacts are on Orbit.'],
      ['tap', 'Person in the search', 'Chats: opens a chat with them. Calls: calls them.'],
      ['long-press', 'Person in the search', 'Opens their contact info.'],
      ['tap', 'Call row', 'Opens the call details.'],
      ['tap', 'Call icon on a call row', 'Calls back the same way.'],
      ['long-press', 'Call row', 'Sheet: Voice call, Video call, Delete from call history.'],
      ['right-click', 'Call row', 'The same sheet.'],
      ['swipe-left', 'Call row', 'Asks to delete it from the call history.'],
      ['tap', 'Quick row: Call / Keypad / a recent person', 'Opens the people search, the keypad, or calls them.'],
      ['tap', 'Keypad digits', 'Types the number; ⌫ deletes; the call button turns on at 6 digits and hands the number to the search.'],
      ['long-press', 'Keypad 0', 'Types +.'],
    ],
    entries: [
      { key: 'chats', label: 'Chats', params: { tab: 'chats' } },
      { key: 'chats-groups', label: 'Chats · Groups filter', params: { tab: 'chats', filter: 'groups' } },
      { key: 'chats-unread', label: 'Chats · Unread filter', params: { tab: 'chats', filter: 'unread' } },
      { key: 'chats-menu', label: 'Chats · menu (Archived chats)', params: { tab: 'chats', menu: true } },
      { key: 'chats-select', label: 'Chats · selection mode', params: { tab: 'chats', select: ['direct:arif', 'group:design'] } },
      { key: 'chats-search', label: 'Chats · search (contacts card)', params: { tab: 'chats', searching: true } },
      { key: 'chats-search-synced', label: 'Chats · search (contacts allowed)', params: { tab: 'chats', searching: true, contacts: 'done' } },
      { key: 'chats-search-q', label: 'Chats · search results', params: { tab: 'chats', searching: true, query: 'ar' } },
      { key: 'chats-search-num', label: 'Chats · find a number', params: { tab: 'chats', searching: true, query: '+880 1711 000002' } },
      { key: 'chats-search-short', label: 'Chats · number without country code', params: { tab: 'chats', searching: true, query: '01711 000002' } },
      { key: 'chats-search-none', label: 'Chats · lookup: not on Orbit', params: { tab: 'chats', searching: true, query: '+880 1711 000002', lookup: 'none' } },
      { key: 'chats-empty', label: 'Chats · empty (new account)', params: { tab: 'chats', empty: true } },
      { key: 'calls', label: 'Calls', params: { tab: 'calls' } },
      { key: 'calls-search', label: 'Calls · new call (search)', params: { tab: 'calls', callSearching: true, contacts: 'done' } },
      { key: 'calls-empty', label: 'Calls · empty', params: { tab: 'calls', callsEmpty: true } },
    ],
    render(params, entry) {
      const st = entry.state;
      if (!st.init) {
        st.init = true; st.tab = params.tab || 'chats';
        st.searching = !!params.searching; st.query = params.query || '';
        st.callSearching = !!params.callSearching; st.callQuery = '';
        st.selected = new Set(params.select || []);
        st.lookup = params.lookup || null; st.setQuery = params.setQuery || ''; st.filter = params.filter || 'all';
        S.contacts = params.contacts || (params.searching || params.callSearching ? 'ask' : S.contacts);
      }
      return `<div class="pager" style="--idx:${TABS.indexOf(st.tab)}">
          <div class="pane" data-pane="chats">${chatsPane(params, st)}</div>
          <div class="pane" data-pane="calls">${callsPane(params, st)}</div>
        </div>${dock(st.tab, st)}`;
    },
    mount(el, params, entry) {
      const st = entry.state;
      const rerender = () => entry.rerender();
      const focus = (sel) => setTimeout(() => { const n = el.querySelector(sel); if (n) { n.focus(); n.setSelectionRange(n.value.length, n.value.length); } }, 30);
      const setTab = (t) => { st.tab = t; rerender(); };
      const liveInput = (sel, key, extra) => {
        const n = el.querySelector(sel); if (!n) return;
        n.addEventListener('input', () => { st[key] = n.value; st.lookup = null; const pos = n.selectionStart; rerender(); const m = el.querySelector(sel); m.focus(); m.setSelectionRange(pos, pos); });
        if (extra) n.addEventListener('keydown', extra);
      };

      el.querySelectorAll('[data-tab]').forEach((b) => b.addEventListener('click', () => setTab(b.dataset.tab)));
      el.querySelectorAll('[data-settings]').forEach((b) => b.addEventListener('click', () => App.push('settings-page')));
      el.querySelector('[data-fab]')?.addEventListener('click', () => {
        if (st.tab === 'chats') { st.searching = true; st.query = ''; rerender(); focus('#chatSearch'); }
        else { st.callSearching = true; rerender(); focus('#callSearch'); }
      });

      // ---- Pager swipe (horizontal drags that do not start on a swipeable row or a field)
      const pager = el.querySelector('.pager');
      let sx = 0, sy = 0, dragging = false, dx = 0;
      pager.addEventListener('pointerdown', (e) => { if (App.isWide() || e.target.closest('.swipe-wrap, input, .quick, .chips')) return; sx = e.clientX; sy = e.clientY; dragging = true; dx = 0; });
      pager.addEventListener('pointermove', (e) => {
        if (!dragging) return;
        dx = e.clientX - sx;
        if (Math.abs(dx) < 8 || Math.abs(dx) < Math.abs(e.clientY - sy)) return;
        pager.style.transition = 'none';
        pager.style.transform = `translateX(calc(${-TABS.indexOf(st.tab) * 100}% + ${dx}px))`;
      });
      const end = () => {
        if (!dragging) return; dragging = false;
        pager.style.transition = ''; pager.style.transform = '';
        const i = TABS.indexOf(st.tab);
        if (dx < -70 && i < TABS.length - 1) setTab(TABS[i + 1]); else if (dx > 70 && i > 0) setTab(TABS[i - 1]);
      };
      ['pointerup', 'pointerleave', 'pointercancel'].forEach((ev) => pager.addEventListener(ev, end));

      // ---- Chats
      const openChat = (id, jump) => App.push('chat', { id, jump });
      el.querySelectorAll('[data-chat]').forEach((b) => {
        let timer = null, long = false;
        b.addEventListener('pointerdown', () => { long = false; if (st.searching) return; timer = setTimeout(() => { if (b.dataset.swiping) return; long = true; st.selected.add(b.dataset.chat); rerender(); }, 450); });
        ['pointerup', 'pointerleave', 'pointercancel'].forEach((ev) => b.addEventListener(ev, () => clearTimeout(timer)));
        b.addEventListener('contextmenu', (e) => { e.preventDefault(); if (!st.searching) { st.selected.add(b.dataset.chat); rerender(); } });
        b.addEventListener('click', () => {
          if (long) return;
          if (st.selected.size) { st.selected.has(b.dataset.chat) ? st.selected.delete(b.dataset.chat) : st.selected.add(b.dataset.chat); rerender(); return; }
          openChat(b.dataset.chat, b.dataset.jump);
        });
      });
      el.querySelector('[data-sel-cancel]')?.addEventListener('click', () => { st.selected.clear(); rerender(); });
      el.querySelectorAll('[data-sel]').forEach((b) => b.addEventListener('click', () => {
        const n = st.selected.size; const what = b.dataset.sel;
        const ids = [...st.selected];
        if (what === 'more') {
          const allPinned = ids.every((id) => S.pinned.has(id));
          const anyMuted = ids.some((id) => Data.chats.find((c) => c.id === id)?.muted);
          const allMuted = ids.every((id) => Data.chats.find((c) => c.id === id)?.muted);
          const anyUnread = ids.some((id) => Data.chats.find((c) => c.id === id)?.unreadCount);
          App.menu([
            { icon: 'push-pin', label: allPinned ? 'Unpin' : 'Pin', run: () => { ids.forEach((id) => allPinned ? S.pinned.delete(id) : S.pinned.add(id)); st.selected.clear(); rerender(); } },
            { icon: 'bell-slash', label: allMuted ? 'Unmute' : anyMuted ? 'Mute or unmute' : 'Mute', run: () => muteSheet(anyMuted, () => { st.selected.clear(); rerender(); }) },
            ...(anyUnread ? [{ icon: 'checks', label: 'Mark as read', run: () => { st.selected.clear(); rerender(); } }] : []),
          ]);
          return;
        }
        if (what === 'delete') {
          App.dialog({ title: n > 1 ? `Delete ${n} chats?` : 'Delete this chat?', text: 'The messages are removed from this device. People you chatted with keep their copies.', actions: [{ label: 'Cancel' }, { label: 'Delete', kind: 'danger', run: () => { st.selected.clear(); rerender(); } }] });
          return;
        }
        st.selected.clear(); rerender();
        App.snack('Chat archived', { label: 'Undo' });
      }));
      el.querySelector('[data-chats-menu]')?.addEventListener('click', () => App.menu([
        { icon: 'users-three', label: 'New group', run: () => App.push('group-new') },
        { icon: 'link-simple', label: 'Join a group with a link', run: () => App.push('group-join', { phase: 'input' }) },
        '-',
        { icon: 'archive', label: `Archived chats${Data.archived.length ? ` (${Data.archived.length})` : ''}`, run: () => App.push('archived') },
      ]));
      el.querySelectorAll('[data-filter]').forEach((b) => b.addEventListener('click', () => { st.filter = b.dataset.filter; rerender(); }));
      if (params.menu && !st.menuShown) { st.menuShown = true; setTimeout(() => { const b = el.querySelector('[data-chats-menu]'); if (!b) return; b.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })); b.click(); }, 60); }
      el.querySelector('[data-new-group]')?.addEventListener('click', () => App.push('group-new'));
      el.querySelectorAll('[data-search-open]').forEach((b) => b.addEventListener('click', () => { st.searching = true; st.query = ''; rerender(); focus('#chatSearch'); }));
      el.querySelector('[data-search-close]')?.addEventListener('click', () => { st.searching = false; st.query = ''; st.lookup = null; rerender(); });
      el.querySelector('[data-search-clear]')?.addEventListener('click', () => { st.query = ''; st.lookup = null; rerender(); focus('#chatSearch'); });
      liveInput('#chatSearch', 'query', (e) => { if (e.key === 'Enter') el.querySelector('[data-lookup]')?.click(); });
      el.querySelectorAll('[data-lookup]').forEach((b) => b.addEventListener('click', () => {
        st.lookup = 'searching'; rerender();
        setTimeout(() => { if (!entry.el.isConnected) return; st.lookup = 'none'; rerender(); }, 1100);
      }));
      el.querySelector('[data-allow-contacts]')?.addEventListener('click', () => {
        S.contacts = 'checking'; rerender();
        setTimeout(() => { S.contacts = 'done'; if (entry.el.isConnected) rerender(); }, 1300);
      });
      el.querySelector('[data-refresh-contacts]')?.addEventListener('click', () => {
        S.contacts = 'checking'; rerender();
        setTimeout(() => { S.contacts = 'done'; if (entry.el.isConnected) rerender(); }, 1300);
      });
      el.querySelectorAll('[data-person]').forEach((b) => {
        let t = null;
        b.addEventListener('pointerdown', () => { t = setTimeout(() => { b.dataset.long = '1'; App.push('contact', { id: b.dataset.person }); }, 500); });
        ['pointerup', 'pointerleave'].forEach((ev) => b.addEventListener(ev, () => clearTimeout(t)));
        b.addEventListener('click', (e) => {
          if (e.target.closest('[data-place], [data-place-video]')) return;
          if (b.dataset.long) { delete b.dataset.long; return; }
          if (st.tab === 'calls') App.push('call', { peer: b.dataset.person, phase: 'outgoing' });
          else openChat(`direct:${b.dataset.person}`);
        });
      });

      // Row swipe: start = pin/unpin, end = archive (chats) or delete (calls)
      el.querySelectorAll('.swipe-wrap').forEach((w) => {
        const r = w.querySelector('.chat-row'); const bg = w.querySelector('.swipe-bg');
        const isCall = r.classList.contains('call-row');
        let x0 = 0, y0 = 0, on = false, d = 0, horiz = false;
        r.addEventListener('pointerdown', (e) => { if (e.target.closest('.ibtn')) return; x0 = e.clientX; y0 = e.clientY; on = true; d = 0; horiz = false; });
        r.addEventListener('pointermove', (e) => {
          if (!on) return; d = e.clientX - x0;
          if (isCall && d > 0) d = 0;
          if (!horiz && Math.abs(d) > 10 && Math.abs(d) > Math.abs(e.clientY - y0)) { horiz = true; r.dataset.swiping = '1'; }
          if (!horiz) return;
          r.style.transition = 'none'; r.style.transform = `translateX(${d}px)`;
          if (!isCall) bg.style.background = 'var(--accent)';
          bg.querySelector('.sw-start') && (bg.querySelector('.sw-start').style.opacity = d > 0 ? 1 : 0);
          bg.querySelector('.sw-end').style.opacity = d < 0 ? 1 : 0;
        });
        const done = () => {
          if (!on) return; on = false; r.style.transition = 'transform 200ms var(--ease)'; r.style.transform = ''; delete r.dataset.swiping;
          if (!horiz) return;
          r.addEventListener('click', (ev) => ev.stopImmediatePropagation(), { once: true, capture: true });
          const width = r.offsetWidth;
          if (isCall) {
            if (d < -width * 0.3) { const c = Data.calls.find((x) => x.id === r.dataset.call); App.dialog({ title: 'Delete from call history?', text: c.count > 1 ? `These ${c.count} calls with ${c.title} will be removed from your call history.` : `This call with ${c.title} will be removed from your call history.`, actions: [{ label: 'Cancel' }, { label: 'Delete', kind: 'danger' }] }); }
            return;
          }
          const id = r.dataset.chat;
          if (d > width * 0.3) { S.pinned.has(id) ? S.pinned.delete(id) : S.pinned.add(id); setTimeout(rerender, 200); }
          if (d < -width * 0.3) App.snack('Chat archived', { label: 'Undo' });
        };
        ['pointerup', 'pointercancel', 'pointerleave'].forEach((ev) => r.addEventListener(ev, done));
      });

      // ---- Calls
      el.querySelectorAll('[data-call-search-open]').forEach((b) => b.addEventListener('click', () => { st.callSearching = true; rerender(); focus('#callSearch'); }));
      el.querySelector('[data-call-search-close]')?.addEventListener('click', () => { st.callSearching = false; st.callQuery = ''; st.lookup = null; rerender(); });
      el.querySelector('[data-call-search-clear]')?.addEventListener('click', () => { st.callQuery = ''; rerender(); focus('#callSearch'); });
      liveInput('#callSearch', 'callQuery', (e) => { if (e.key === 'Enter') el.querySelector('[data-lookup]')?.click(); });
      el.querySelectorAll('[data-place]').forEach((b) => b.addEventListener('click', (e) => { e.stopPropagation(); App.push('call', { peer: b.dataset.place, phase: 'outgoing' }); }));
      el.querySelectorAll('[data-place-video]').forEach((b) => b.addEventListener('click', (e) => { e.stopPropagation(); App.push('call', { peer: b.dataset.placeVideo, phase: 'outgoing', video: true }); }));
      el.querySelectorAll('[data-callback]').forEach((b) => b.addEventListener('click', (e) => {
        e.stopPropagation(); const c = Data.calls.find((x) => x.id === b.dataset.callback);
        App.push('call', { peer: c.peer, phase: 'outgoing', video: c.video });
      }));
      el.querySelectorAll('[data-call]').forEach((b) => {
        let t = null, long = false;
        b.addEventListener('pointerdown', (e) => { if (e.target.closest('.ibtn')) return; long = false; t = setTimeout(() => { long = true; callSheet(b.dataset.call); }, 450); });
        ['pointerup', 'pointerleave', 'pointercancel'].forEach((ev) => b.addEventListener(ev, () => clearTimeout(t)));
        b.addEventListener('contextmenu', (e) => { e.preventDefault(); callSheet(b.dataset.call); });
        b.addEventListener('click', (e) => { if (long || e.target.closest('.ibtn')) return; App.push('call-detail', { id: b.dataset.call }); });
      });
      el.querySelector('[data-dialpad]')?.addEventListener('click', () => openDialPad((num) => { st.tab = 'calls'; st.callSearching = true; st.callQuery = num; rerender(); }));

    },
  });

  function muteSheet(withUnmute, after) {
    App.sheet({ title: 'Mute notifications', items: [
      { icon: 'bell-slash', label: '8 hours', run: after }, { icon: 'bell-slash', label: '1 week', run: after }, { icon: 'bell-slash', label: 'Always', run: after },
      ...(withUnmute ? [{ icon: 'speaker-high', label: 'Unmute', run: after }] : []),
    ] });
  }

  function callSheet(id) {
    const c = Data.calls.find((x) => x.id === id);
    App.sheet({ title: c.title, items: [
      { icon: 'phone', label: 'Voice call', run: () => App.push('call', { peer: c.peer, phase: 'outgoing' }) },
      { icon: 'video-camera', label: 'Video call', run: () => App.push('call', { peer: c.peer, phase: 'outgoing', video: true }) },
      { icon: 'trash', label: 'Delete from call history', danger: true, run: () => App.dialog({ title: 'Delete from call history?', text: `This call with ${c.title} will be removed from your call history.`, actions: [{ label: 'Cancel' }, { label: 'Delete', kind: 'danger' }] }) },
    ] });
  }

  // Dial pad: it never calls by itself; it hands the number to the people search.
  function openDialPad(onFind) {
    const keys = [['1', ''], ['2', 'ABC'], ['3', 'DEF'], ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'], ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ'], ['*', ''], ['0', '+'], ['#', '']];
    const h = App.sheet({ body: `<div style="padding:4px 22px 0">
      <div id="dpNum" class="mono" style="height:56px;display:flex;align-items:center;justify-content:center;font-size:28px;font-weight:500;letter-spacing:0.04em;color:var(--ink-4)">Enter a number</div>
      <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:6px">${keys.map(([k, l]) => `<button class="dp-key" data-k="${k}" style="height:62px;border-radius:20px;border:1px solid var(--line);background:var(--surface);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:1px"><span style="font-size:24px;font-weight:500">${k}</span><span class="mono" style="font-size:9.5px;color:var(--ink-4);letter-spacing:0.12em;min-height:11px">${l}</span></button>`).join('')}</div>
      <div style="display:flex;align-items:center;justify-content:center;gap:28px;margin-top:16px">
        <span style="width:48px"></span>
        <button class="fab" id="dpCall" style="width:64px;height:64px;background:var(--call-accept);box-shadow:none" aria-label="Find on Orbit" title="Find on Orbit" disabled>${icon('phone', 'fill')}</button>
        <span id="dpDelWrap" style="width:48px">${ibtn('backspace', 'Delete digit', 'id="dpDel" style="visibility:hidden"')}</span></div></div>` });
    let num = '';
    const call = h.panel.querySelector('#dpCall');
    const show = () => {
      const n = h.panel.querySelector('#dpNum');
      n.textContent = num || 'Enter a number'; n.style.color = num ? 'var(--ink)' : 'var(--ink-4)'; n.style.fontSize = num ? '28px' : '18px';
      h.panel.querySelector('#dpDel').style.visibility = num ? 'visible' : 'hidden';
      const ok = num.replace(/\D/g, '').length >= 6;
      call.disabled = !ok; call.style.opacity = ok ? 1 : 0.4;
    };
    show();
    h.panel.querySelectorAll('.dp-key').forEach((b) => {
      let t = null, long = false;
      b.addEventListener('pointerdown', () => { long = false; if (b.dataset.k === '0') t = setTimeout(() => { long = true; num += '+'; show(); }, 500); });
      ['pointerup', 'pointerleave'].forEach((ev) => b.addEventListener(ev, () => clearTimeout(t)));
      b.addEventListener('click', () => { if (long) return; num += b.dataset.k; show(); });
    });
    h.panel.querySelector('#dpDel').addEventListener('click', () => { num = num.slice(0, -1); show(); });
    call.addEventListener('click', () => { h.close(); onFind(num); });
  }

  // ============================================================ Archived chats
  App.register({
    id: 'archived', title: 'Archived chats', group: 'Home', order: 10,
    interactions: [
      ['tap', 'Chat row', 'Opens the chat.'],
      ['swipe-left', 'Chat row', 'Unarchives it, with Undo.'],
      ['long-press', 'Chat row', 'Starts selecting; the bar offers Unarchive (with Undo), Delete (asks), ⋮ for Mute and Mark as read.'],
    ],
    entries: [
      { key: 'archived', label: 'Archived chats', params: {}, base: { screen: 'home', params: { tab: 'chats' } } },
      { key: 'archived-empty', label: 'Archived chats · empty', params: { empty: true }, base: { screen: 'home', params: { tab: 'chats' } } },
    ],
    render(params, entry) {
      const st = entry.state; st.selected = st.selected || new Set();
      const head = st.selected.size
        ? `<header class="appbar selection">${ibtn('x', 'Cancel selection', 'data-sel-cancel')}<div class="ab-title"><h1>${st.selected.size} selected</h1></div>${ibtn('tray-arrow-up', 'Unarchive chats', 'data-unarchive')}${ibtn('trash', 'Delete chats', 'data-del')}${ibtn('dots-three-vertical', 'More options', 'data-more')}</header>`
        : UI.appbar({ title: 'Archived chats' });
      const body = params.empty ? empty({ icon: 'archive', title: 'No archived chats', text: 'Chats you archive stay here until you unarchive them.' })
        : Data.archived.map((c) => `<div class="swipe-wrap"><div class="swipe-bg" style="background:var(--accent);justify-content:flex-end"><span class="sw-end">${icon('tray-arrow-up', 'fill')}Unarchive</span></div>${chatRow(c, { selected: st.selected.has(c.id) })}</div>`).join('');
      return `${head}<div class="scroll" style="padding-top:6px">${body}</div>`;
    },
    mount(el, params, entry) {
      const st = entry.state; const rerender = () => entry.rerender();
      el.querySelector('[data-back]')?.addEventListener('click', App.pop);
      el.querySelector('[data-sel-cancel]')?.addEventListener('click', () => { st.selected.clear(); rerender(); });
      el.querySelector('[data-unarchive]')?.addEventListener('click', () => { st.selected.clear(); rerender(); App.snack('Chat unarchived', { label: 'Undo' }); });
      el.querySelector('[data-del]')?.addEventListener('click', () => App.dialog({ title: st.selected.size > 1 ? `Delete ${st.selected.size} chats?` : 'Delete this chat?', text: 'The messages are removed from this device. People you chatted with keep their copies.', actions: [{ label: 'Cancel' }, { label: 'Delete', kind: 'danger', run: () => { st.selected.clear(); rerender(); } }] }));
      el.querySelector('[data-more]')?.addEventListener('click', () => App.menu([{ icon: 'bell-slash', label: 'Mute…', run: () => muteSheet(true, () => { st.selected.clear(); rerender(); }) }, { icon: 'checks', label: 'Mark as read' }]));
      el.querySelectorAll('[data-chat]').forEach((b) => {
        let t = null, long = false;
        b.addEventListener('pointerdown', () => { long = false; t = setTimeout(() => { if (b.dataset.swiping) return; long = true; st.selected.add(b.dataset.chat); rerender(); }, 450); });
        ['pointerup', 'pointerleave', 'pointercancel'].forEach((ev) => b.addEventListener(ev, () => clearTimeout(t)));
        b.addEventListener('click', () => { if (long) return; if (st.selected.size) { st.selected.has(b.dataset.chat) ? st.selected.delete(b.dataset.chat) : st.selected.add(b.dataset.chat); rerender(); return; } App.push('chat', { id: b.dataset.chat }); });
      });
      // Swipe a row left to unarchive it (the same gesture that archived it).
      el.querySelectorAll('.swipe-wrap').forEach((w) => {
        const r = w.querySelector('.chat-row'); const label = w.querySelector('.sw-end');
        let x0 = 0, y0 = 0, on = false, d = 0, horiz = false;
        r.addEventListener('pointerdown', (e) => { x0 = e.clientX; y0 = e.clientY; on = true; d = 0; horiz = false; });
        r.addEventListener('pointermove', (e) => {
          if (!on) return; d = Math.min(0, e.clientX - x0);
          if (!horiz && Math.abs(d) > 10 && Math.abs(d) > Math.abs(e.clientY - y0)) { horiz = true; r.dataset.swiping = '1'; }
          if (!horiz) return;
          r.style.transition = 'none'; r.style.transform = `translateX(${d}px)`; label.style.opacity = d < 0 ? 1 : 0;
        });
        const done = () => {
          if (!on) return; on = false; r.style.transition = 'transform 200ms var(--ease)'; r.style.transform = ''; delete r.dataset.swiping;
          if (!horiz) return;
          r.addEventListener('click', (ev) => ev.stopImmediatePropagation(), { once: true, capture: true });
          if (d < -r.offsetWidth * 0.3) App.snack('Chat unarchived', { label: 'Undo' });
        };
        ['pointerup', 'pointercancel', 'pointerleave'].forEach((ev) => r.addEventListener(ev, done));
      });
    },
  });
})();
