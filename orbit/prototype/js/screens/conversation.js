/*
  One conversation, direct or group: header, timeline, composer and the
  message actions. Flutter: ConversationScreen + HelixComposer + timeline.
  Copy and rules follow SCREENS.md (the real app).
*/
(() => {
  const { esc, icon, ibtn, avatar, timeline } = UI;
  const EMOJI = {
    Smileys: '😀 😃 😄 😁 😆 😅 😂 🤣 🙂 😉 😊 😇 🥰 😍 🤩 😘 😋 😜 🤪 🤗 🤭 🤔 😐 😏 😴 😌 😮 😢 😭 😤 😡 🥳 😎 🤓'.split(' '),
    Gestures: '👍 👎 👌 ✌️ 🤞 🤟 🤙 👋 👏 🙌 👐 🤲 🙏 🤝 💪 👀 👆 👇 👉 👈 ✋ 🖐️ 🫶 ☝️'.split(' '),
    'Hearts and symbols': '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 ✨ 🔥 💯 ⭐ 🌟 💫 ✅ ❌ ⚠️ ❓'.split(' '),
    Things: '☕ 🍵 🍚 🍛 🍕 🍔 🎂 🍰 🎉 🎊 🎁 🎈 📷 📱 💻 🎧 📚 ✏️ 🔑 🏠 🚗 ✈️ 🌙 ☀️ 🌧️ 🌊 🌸 🌻'.split(' '),
  };
  const MEMBERS = { 'group:family': ['ammu', 'abbu', 'rumana', 'karim'], 'group:design': ['sadia', 'tanvir', 'arif', 'nadia', 'rumana', 'karim'], 'group:lunch': ['arif', 'tanvir'], 'group:studio': ['sadia', 'tanvir'] };

  function convo(id) {
    if (!Data.conversations[id]) {
      const pid = id.split(':')[1];
      Data.conversations[id] = { peer: id.startsWith('direct:') && Data.people[pid] ? pid : null, group: id.startsWith('group:') ? pid : null, items: [] };
    }
    return Data.conversations[id];
  }
  const chatOf = (id) => Data.chats.find((c) => c.id === id) || Data.archived.find((c) => c.id === id);
  const findMsg = (c, mid) => c.items.find((it) => it.kind === 'msg' && it.m.id === mid)?.m;
  const now = () => { const d = new Date(); return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`; };
  const peerName = (c) => (c.peer ? Data.displayName(Data.people[c.peer]) : 'them');

  function titleOf(id, c) {
    const chat = chatOf(id);
    if (chat) return { title: chat.title, av: chat.avatar, verified: chat.verified };
    if (c.peer) { const p = Data.people[c.peer]; return { title: Data.displayName(p), av: Data.av(p), verified: p.verified }; }
    return { title: 'Chat', av: { name: 'Chat' } };
  }

  // ------------------------------------------------------------------ header
  function header(id, c, st, params) {
    if (st.selected.size) {
      return `<header class="appbar selection">${ibtn('x', 'Cancel selection', 'data-sel-cancel')}<div class="ab-title"><h1>${st.selected.size} selected</h1></div>
        ${ibtn('copy', 'Copy', 'data-sel="copy"')}${ibtn('arrow-bend-up-right', 'Forward', 'data-sel="forward"')}${ibtn('trash', 'Delete', 'data-sel="delete"')}</header>`;
    }
    if (st.searching) {
      return `<header class="appbar">${ibtn('arrow-left', 'Close search', 'data-search-close')}<div class="search" style="flex:1;margin:0 8px 0 0;height:44px">${icon('magnifying-glass')}<input id="inSearch" placeholder="Search this chat" value="${esc(st.query || '')}" aria-label="Search this chat" autocomplete="off">${st.query ? ibtn('x', 'Clear search', 'data-search-clear', 'sm') : ''}</div></header>`;
    }
    const { title, av, verified } = titleOf(id, c);
    const group = !!c.group;
    let sub;
    if (group) {
      const m = MEMBERS[id] || [];
      if (params.left) sub = 'You are no longer a member';
      else if (st.peerTyping) sub = `<span class="typing">${esc(st.peerTyping)}</span>`;
      else if (m.length + 1 <= 4) sub = ['You', ...m.map((x) => Data.displayName(Data.people[x]).split(' ')[0])].join(', ');
      else sub = `${m.length + 1} members`;
    } else {
      const p = c.peer && Data.people[c.peer];
      if (st.peerTyping) sub = '<span class="typing">typing...</span>';
      else if (p && p.online) sub = 'online';
      else if (p && p.id === 'arif') sub = 'last seen today at 08:31';
      else sub = p ? esc(Data.secondary(p) || '') : '';
    }
    const blocked = params.blocked;
    const calls = group || blocked ? '' : ibtn('video-camera', 'Video call', 'data-video') + ibtn('phone', 'Voice call', 'data-voice');
    return `<header class="appbar convo-head">${ibtn('arrow-left', 'Back', 'data-back')}
      <button class="ch-who" data-info title="${group ? 'Group info' : 'Contact info'}">${avatar(av, 40)}<span class="ch-text"><span class="ch-name">${esc(title)}${verified ? '<i class="ph-fill ph-seal-check seal" title="Safety number verified"></i>' : ''}</span><span class="ch-sub" style="display:block">${sub}</span></span></button>
      ${calls}${ibtn('dots-three-vertical', 'More options', 'data-menu')}</header>`;
  }

  // Unconfirmed members (groups): one amber card per person.
  function pendingCards(params) {
    if (!params.pending) return '';
    const admin = params.pending === 'admin';
    return `<div class="pending-card">${icon('shield-warning', 'fill')}<div>
      <div class="pc-title">Confirm Karim Uncle?</div>
      <div class="pc-text">${params.pendingReason === 'link'
        ? 'Karim Uncle joined this group through its invite link, and nothing else vouches for them.'
        : 'Karim Uncle was added by the server roster, but no admin of this group announced it.'} Until you confirm, what you send in this group stays unreadable to them.</div>
      ${admin ? '' : '<div class="pc-text" style="margin-top:6px;color:var(--ink-3)">Only an admin can remove someone. If you do not know them, you can leave the group.</div>'}
      <div class="pc-actions"><button class="btn primary" data-confirm-member>Confirm</button>${admin ? '<button class="btn secondary" data-remove-member>Remove</button>' : ''}</div></div></div>`;
  }

  // ---------------------------------------------------------------- composer
  function composer(id, c, st, params) {
    if (params.blocked === 'byMe') return `<div class="cp-disabled">${icon('prohibit')} You blocked this contact. Open chat settings to unblock.</div>`;
    if (params.blocked === 'byThem') return `<div class="cp-disabled">${icon('prohibit')} ${esc(peerName(c))} has blocked you. You can’t message or call them.</div>`;
    if (params.left) return `<div class="cp-disabled">You can no longer send messages to this group.</div>`;

    let banner = '';
    if (st.reply) {
      const m = findMsg(c, st.reply);
      const who = m?.outgoing ? 'yourself' : (m?.authorName || peerName(c));
      banner = `<div class="cp-banner"><div class="cb-body"><div class="cb-title">${icon('arrow-bend-up-left', 'bold')}Replying to ${esc(who)}</div><div class="cb-text">${esc(previewText(m))}</div></div>${ibtn('x', 'Cancel reply', 'data-cancel-banner')}</div>`;
    }
    if (st.edit) {
      const m = findMsg(c, st.edit);
      banner = `<div class="cp-banner edit"><div class="cb-body"><div class="cb-title">${icon('pencil-simple', 'bold')}Edit message</div><div class="cb-text">${esc(previewText(m))}</div></div>${ibtn('x', 'Cancel edit', 'data-cancel-banner')}</div>`;
    }
    if (st.mention) {
      const q = (st.draft.match(/@(\w*)$/) || [, ''])[1].toLowerCase();
      const ppl = (MEMBERS[id] || []).map((x) => Data.people[x]).filter((p) => Data.displayName(p).toLowerCase().includes(q)).slice(0, 4);
      if (ppl.length) banner += `<div class="mentions">${ppl.map((p) => `<button data-mention="${esc(Data.displayName(p))}">${avatar(Data.av(p), 34)}<span><span class="mn-name" style="display:block">${esc(Data.displayName(p))}</span><span class="mn-sub" style="display:block">${esc(Data.secondary(p) || '')}</span></span></button>`).join('')}</div>`;
    }

    if (st.recording) {
      const locked = st.recording === 'locked';
      return `<div class="composer">${locked ? '' : `<div class="lock-pill" title="Slide up to lock" data-lock>${icon('lock-simple-open')}<span class="chev">${icon('caret-up', 'bold')}</span></div>`}
        <div class="cp-row">${locked ? ibtn('trash', 'Delete recording', 'data-rec-cancel', 'danger') : ''}
          <div class="rec"><span class="rec-dot"></span><span class="rec-time">0:07</span>${locked ? UI.wave(Data.wave.slice(0, 24).reverse(), 1, 24) : `<span class="rec-hint">${icon('caret-left', 'bold')} Slide to cancel</span>`}</div>
          <button class="send-btn ${locked ? '' : 'recording'}" data-rec-send title="${locked ? 'Send recording' : 'Release to send'}" aria-label="${locked ? 'Send recording' : 'Release to send'}">${icon(locked ? 'paper-plane-tilt' : 'microphone', 'fill')}</button>
        </div></div>`;
    }

    const has = (st.draft || '').trim().length > 0;
    let action;
    if (st.edit) action = `<button class="send-btn" data-send title="Save edit" aria-label="Save edit" ${has ? '' : 'disabled style="opacity:.45"'}>${icon('check', 'bold')}</button>`;
    else if (has) action = `<button class="send-btn" data-send title="Send" aria-label="Send">${icon('paper-plane-tilt', 'fill')}</button>`;
    else action = `<button class="send-btn mic" data-mic title="Hold to record a voice message" aria-label="Record a voice message">${icon('microphone', 'fill')}</button>`;
    return `<div class="composer">${banner}<div class="cp-row">
        <div class="field">${ibtn(st.emoji ? 'keyboard' : 'smiley', st.emoji ? 'Keyboard' : 'Emoji', 'data-emoji')}
          <textarea id="draft" rows="1" placeholder="Message" aria-label="Message">${esc(st.draft || '')}</textarea>
          ${ibtn('paperclip', 'Attach', 'data-attach')}${has ? '' : ibtn('camera', 'Camera', 'data-cam')}</div>
        ${action}
      </div></div>${st.emoji ? emojiPanel(st) : ''}`;
  }

  function emojiPanel(st) {
    const tab = st.emojiTab || 'Smileys';
    return `<div class="emoji-panel"><div class="chips" style="padding:8px 10px;border-bottom:1px solid var(--line-2)">${Object.keys(EMOJI).map((k) => `<button class="chip ${tab === k ? 'on' : ''}" data-etab="${k}">${k}</button>`).join('')}</div>
      <div class="emoji-grid">${EMOJI[tab].map((e) => `<button data-e="${e}" aria-label="${e}">${e}</button>`).join('')}</div></div>`;
  }

  function previewText(m) {
    if (!m) return '';
    const c = m.content;
    if (c.type === 'text') return c.text;
    if (c.type === 'media') return c.caption || (c.items[0].isVideo ? 'Video' : 'Photo');
    if (c.type === 'audio') return c.isVoiceNote === false ? c.title : 'Voice message';
    if (c.type === 'document') return c.name;
    if (c.type === 'location') return 'Location';
    if (c.type === 'contact') return c.name;
    if (c.type === 'poll') return `Poll: ${c.question}`;
    return 'Message';
  }

  // In-chat search: a list of matching messages, tap to jump.
  function searchResults(id, c, st) {
    const q = (st.query || '').trim().toLowerCase();
    if (!q) return UI.empty({ icon: 'magnifying-glass', title: 'Search this chat', text: 'Type a word to find messages that contain it.' });
    const hits = c.items.filter((it) => it.kind === 'msg' && it.m.content.type === 'text' && it.m.content.text.toLowerCase().includes(q)).map((it) => it.m);
    if (!hits.length) return UI.empty({ icon: 'magnifying-glass', title: 'No results', text: `Nothing matches “${esc(st.query.trim())}”.` });
    const { title, av } = titleOf(id, c);
    const hl = (t) => { const i = t.toLowerCase().indexOf(q); return `${esc(t.slice(0, i))}<b style="color:var(--accent-ink)">${esc(t.slice(i, i + q.length))}</b>${esc(t.slice(i + q.length))}`; };
    return `<div class="result-list" style="padding-top:6px">${hits.map((m) => {
      const who = m.outgoing ? 'You' : (m.authorName || title.split(' ')[0]);
      return `<button class="chat-row" data-hit="${esc(m.id)}">${avatar(m.outgoing ? { name: Data.me.name, color: 0 } : m.authorName ? { name: m.authorName, color: m.authorColorIndex } : av, 44)}<span class="cr-body"><span class="cr-top"><span class="cr-name"><span class="nm">${esc(who)}</span></span><span class="cr-time">${esc(m.timeLabel)}</span></span><span class="cr-preview" style="white-space:normal;display:block">${hl(m.content.text)}</span></span></button>`;
    }).join('')}</div>`;
  }

  // ------------------------------------------------------------------ screen
  App.register({
    id: 'chat', title: 'Conversation', group: 'Conversation', order: 20,
    interactions: [
      ['tap', 'Header (name or picture)', 'Opens contact info or group info.'],
      ['tap', 'Voice / Video', 'Places a call.'],
      ['tap', '⋮', 'Menu: Search, Contact or Group info, Media links and docs, Chat settings.'],
      ['scroll', 'Timeline', 'A “scroll to latest” button appears 160 px above the bottom, with the unread count.'],
      ['tap', 'Scroll to latest', 'Scrolls to the newest message.'],
      ['swipe-right', 'Their message', 'Past 56 px: reply to it.'],
      ['swipe-left', 'Your message', 'Past 56 px: reply to it.'],
      ['long-press', 'Message', 'Opens the actions view: reactions, the message, and Reply, Copy, Forward, Edit (yours, sent), Message info (yours), Select, Delete for me, Delete for everyone (yours, sent).'],
      ['right-click', 'Message', 'Opens the same actions view.'],
      ['tap', 'Outside the actions view', 'Closes it.'],
      ['tap', 'Reaction in the actions view', 'Adds your reaction, swaps it, or removes it when it is the same one.'],
      ['tap', '+ in the reactions', 'Sheet with every emoji.'],
      ['tap', 'Reaction under a message', 'Sheet: who reacted with what; yours can be removed.'],
      ['tap', 'Photo in a message', 'Opens the media viewer at it.'],
      ['tap', 'View-once message', 'Opens it once; says when it was already opened or when you sent it.'],
      ['tap', 'Voice message play / speed', 'Plays or pauses; speed cycles 1x, 1.5x, 2x.'],
      ['tap', 'Document button', 'Downloads it, or shares it once downloaded.'],
      ['tap', 'Retry on a failed message', 'Sends it again.'],
      ['tap', 'Quoted reply', 'Jumps to the original message.'],
      ['tap', 'Messages while selecting', 'Adds or removes them; the bar offers Copy, Forward, Delete (for me, asks first) and × to stop.'],
      ['type', 'Message box', 'The send button replaces the mic; the box grows up to 128 px.'],
      ['key', 'Enter in the message box', 'Sends when “Enter key sends” is on (on by default on a window, off on a phone); otherwise adds a line. Shift+Enter always adds a line.'],
      ['tap', 'Try again (could not be opened)', 'Opens the conversation again.'],
      ['type', '@ in a group', 'Opens the mention picker; tapping a person inserts @Name.'],
      ['tap', 'Send', 'Sends; ticks go sent, delivered, read. In the demo chat Nadia types, then replies.'],
      ['tap', 'Save edit', 'Replaces the text and marks the message Edited.'],
      ['tap', '× on the reply or edit banner', 'Cancels the reply or the edit.'],
      ['tap', 'Emoji', 'Opens the emoji panel with tabs; tapping an emoji adds it; focusing the text closes the panel.'],
      ['tap', 'Camera', 'Sheet: Take a photo, Record a video, then Send files.'],
      ['tap', 'Paperclip', 'Attach sheet: Document, Camera, Gallery, Audio.'],
      ['hold', 'Microphone', 'Records while held; releasing sends; sliding onto the lock keeps recording hands-free.'],
      ['tap', 'Microphone (not held)', 'Says “Hold the microphone to record a voice message.”'],
      ['tap', 'Send / Delete while recording is locked', 'Sends the recording or throws it away.'],
      ['type', 'Search in chat', 'Lists matching messages as you type; × clears; ← closes.'],
      ['tap', 'Search result', 'Closes search, scrolls to the message and highlights it briefly.'],
      ['tap', 'Confirm / Remove on an unconfirmed member (group)', 'Confirms them, or asks before removing them.'],
      ['auto', 'Composer when blocked or left', 'The composer is replaced by a line saying why you cannot send.'],
    ],
    entries: [
      { key: 'chat', label: 'Direct chat', params: { id: 'direct:nadia' } },
      { key: 'chat-typing', label: 'Composer · typing', params: { id: 'direct:nadia', draft: 'On my way, see you in 10' } },
      { key: 'chat-reply', label: 'Composer · reply', params: { id: 'direct:nadia', reply: 'n8', draft: 'They look amazing!' } },
      { key: 'chat-edit', label: 'Composer · edit', params: { id: 'direct:nadia', edit: 'n5' } },
      { key: 'chat-attach', label: 'Composer · attach sheet', params: { id: 'direct:nadia', attach: true } },
      { key: 'chat-emoji', label: 'Composer · emoji panel', params: { id: 'direct:nadia', emoji: true } },
      { key: 'chat-rec', label: 'Composer · recording (hold)', params: { id: 'direct:nadia', recording: 'hold' } },
      { key: 'chat-rec-lock', label: 'Composer · recording (locked)', params: { id: 'direct:nadia', recording: 'locked' } },
      { key: 'chat-actions', label: 'Message actions · their message', params: { id: 'direct:nadia', actions: 'n6' } },
      { key: 'chat-actions-mine', label: 'Message actions · your message', params: { id: 'direct:nadia', actions: 'n5' } },
      { key: 'chat-select', label: 'Selecting messages', params: { id: 'direct:nadia', select: ['n3', 'n5'] } },
      { key: 'chat-search', label: 'Search in chat', params: { id: 'direct:nadia', searching: true } },
      { key: 'chat-search-q', label: 'Search in chat · results', params: { id: 'direct:nadia', searching: true, query: 'the' } },
      { key: 'chat-kinds', label: 'Message kinds (link, poll, view once…)', params: { id: 'direct:arif' } },
      { key: 'chat-transfer', label: 'Downloads, key change, failed send', params: { id: 'direct:rafiq' } },
      { key: 'chat-new', label: 'New chat (empty)', params: { id: 'direct:sadia' } },
      { key: 'group', label: 'Group chat', params: { id: 'group:family' } },
      { key: 'group-mention', label: 'Group · @mention picker', params: { id: 'group:family', draft: 'Thanks @', mention: true } },
      { key: 'group-pending', label: 'Group · unconfirmed member (admin)', params: { id: 'group:family', pending: 'admin' } },
      { key: 'group-pending-member', label: 'Group · unconfirmed member (member)', params: { id: 'group:family', pending: 'member' } },
      { key: 'group-pending-link', label: 'Group · unconfirmed member who joined by link', params: { id: 'group:family', pending: 'admin', pendingReason: 'link' } },
      { key: 'chat-loading', label: 'Conversation · opening', params: { id: 'direct:nadia', state: 'loading' } },
      { key: 'chat-error', label: 'Conversation · could not be opened', params: { id: 'direct:nadia', state: 'error' } },
      { key: 'group-left', label: 'Group · you left', params: { id: 'group:family', left: true } },
      { key: 'chat-blocked', label: 'Blocked (you blocked them)', params: { id: 'direct:shuvo', blocked: 'byMe' } },
      { key: 'chat-blocked-me', label: 'Blocked (they blocked you)', params: { id: 'direct:shuvo', blocked: 'byThem' } },
    ].map((e) => ({ ...e, base: { screen: 'home', params: { tab: 'chats' } } })),
    render(params, entry) {
      const st = entry.state;
      const id = params.id;
      const c = convo(id);
      if (!st.init) {
        st.init = true; st.draft = params.draft || ''; st.reply = params.reply || null; st.edit = params.edit || null;
        st.emoji = !!params.emoji; st.recording = params.recording || null; st.mention = !!params.mention;
        st.searching = !!params.searching; st.query = params.query || ''; st.selected = new Set(params.select || []);
        if (st.edit) st.draft = previewText(findMsg(c, st.edit));
        if (params.jump) { const m = findMsg(c, params.jump); if (m) { m.highlighted = true; setTimeout(() => { m.highlighted = false; }, 1600); } }
      }
      if (st.searching) return `${header(id, c, st, params)}<div class="scroll" data-keep-scroll="hits" style="background:var(--surface)">${searchResults(id, c, st)}</div>`;
      if (params.state === 'loading') return `${header(id, c, st, params)}${Kit.loading('Opening the conversation…')}`;
      if (params.state === 'error') return `${header(id, c, st, params)}<div class="scroll">${Kit.loadFailed('This conversation could not be opened.')}</div>`;
      let items = c.items.length ? c.items.slice() : [{ kind: 'empty' }];
      if (st.showTyping) items = items.concat([{ kind: 'typing' }]);
      const unread = c.items.find((it) => it.kind === 'unread');
      return `${header(id, c, st, params)}${c.group && !st.selected.size ? pendingCards(params) : ''}
        <div class="timeline" data-keep-scroll="tl"><div class="spacer"></div>${timeline(items, { group: !!c.group, selected: st.selected })}</div>
        <button class="to-bottom hidden" data-to-bottom title="Scroll to latest message${unread ? `, ${unread.count} unread` : ''}" aria-label="Scroll to latest message">${icon('caret-down', 'bold')}${unread ? `<span class="badge">${unread.count}</span>` : ''}</button>
        ${st.selected.size ? '' : composer(id, c, st, params)}`;
    },
    mount(el, params, entry) {
      const st = entry.state; const id = params.id; const c = convo(id);
      const rerender = () => entry.rerender();
      const tl = el.querySelector('.timeline');
      const toBottom = el.querySelector('[data-to-bottom]');
      if (tl) {
        if (!st.scrolled) {
          st.scrolled = true;
          requestAnimationFrame(() => {
            const jumpTo = params.jump && el.querySelector(`[data-msg="${CSS.escape(params.jump)}"]`);
            if (jumpTo) jumpTo.scrollIntoView({ block: 'center' }); else tl.scrollTop = tl.scrollHeight;
          });
        }
        const sync = () => toBottom && toBottom.classList.toggle('hidden', tl.scrollHeight - tl.scrollTop - tl.clientHeight < 160);
        tl.addEventListener('scroll', sync); requestAnimationFrame(sync);
        toBottom?.addEventListener('click', () => tl.scrollTo({ top: tl.scrollHeight, behavior: 'smooth' }));
      }

      el.querySelector('[data-back]')?.addEventListener('click', App.pop);
      const openInfo = () => (c.group ? App.push('group-info', { role: 'admin' }) : c.peer && App.push('contact', { id: c.peer }));
      el.querySelector('[data-info]')?.addEventListener('click', openInfo);
      el.querySelector('[data-voice]')?.addEventListener('click', () => App.push('call', { peer: c.peer, phase: 'outgoing' }));
      el.querySelector('[data-video]')?.addEventListener('click', () => App.push('call', { peer: c.peer, phase: 'outgoing', video: true }));
      el.querySelector('[data-menu]')?.addEventListener('click', () => App.menu([
        { icon: 'magnifying-glass', label: 'Search', run: () => { st.searching = true; rerender(); el.querySelector('#inSearch')?.focus(); } },
        { icon: c.group ? 'users-three' : 'user-circle', label: c.group ? 'Group info' : 'Contact info', run: openInfo },
        { icon: 'images', label: 'Media, links and docs', run: () => App.push('shared', { id, tab: 'media' }) },
        { icon: 'gear-six', label: 'Chat settings', run: () => App.push('chat-settings', { id }) },
      ]));

      // In-chat search
      el.querySelector('[data-search-close]')?.addEventListener('click', () => { st.searching = false; st.query = ''; rerender(); });
      el.querySelector('[data-search-clear]')?.addEventListener('click', () => { st.query = ''; rerender(); el.querySelector('#inSearch')?.focus(); });
      const s = el.querySelector('#inSearch');
      if (s) s.addEventListener('input', () => { st.query = s.value; const pos = s.selectionStart; rerender(); const n = el.querySelector('#inSearch'); n.focus(); n.setSelectionRange(pos, pos); });
      el.querySelectorAll('[data-hit]').forEach((b) => b.addEventListener('click', () => {
        const m = findMsg(c, b.dataset.hit); st.searching = false; st.query = ''; m.highlighted = true; st.scrolled = true; rerender();
        requestAnimationFrame(() => el.querySelector(`[data-msg="${CSS.escape(m.id)}"]`)?.scrollIntoView({ block: 'center' }));
        setTimeout(() => { m.highlighted = false; if (entry.el.isConnected) rerender(); }, 1600);
      }));

      // Selection
      el.querySelector('[data-sel-cancel]')?.addEventListener('click', () => { st.selected.clear(); rerender(); });
      el.querySelectorAll('[data-sel]').forEach((b) => b.addEventListener('click', () => {
        const what = b.dataset.sel; const n = st.selected.size;
        if (what === 'delete') {
          App.dialog({ title: n > 1 ? `Delete ${n} messages?` : 'Delete this message?', text: 'They are removed from this device only.', actions: [{ label: 'Cancel' }, { label: 'Delete for me', kind: 'danger', run: () => { removeForMe([...st.selected]); st.selected.clear(); rerender(); } }] });
          return;
        }
        st.selected.clear(); rerender();
        if (what === 'copy') App.snack('Copied'); else App.push('forward', { n });
      }));

      // Messages: long-press for actions, swipe sideways to reply
      el.querySelectorAll('[data-msg]').forEach((node) => {
        const mid = node.dataset.msg;
        const bubble = node.querySelector('.bubble');
        let t = null, long = false, x0 = 0, y0 = 0, dx = 0, swiping = false, down = false;
        node.addEventListener('pointerdown', (e) => {
          long = false; down = true; x0 = e.clientX; y0 = e.clientY; dx = 0; swiping = false;
          t = setTimeout(() => { long = true; if (st.selected.size) toggleSel(mid); else openActions(mid); }, 450);
        });
        node.addEventListener('pointermove', (e) => {
          if (!down) return;
          const ddx = e.clientX - x0;
          if (!swiping && Math.abs(ddx) > 10 && Math.abs(ddx) > Math.abs(e.clientY - y0)) { swiping = true; clearTimeout(t); }
          if (!swiping || st.selected.size || params.blocked || params.left) return;
          dx = Math.max(0, Math.min(80, node.classList.contains('out') ? -ddx : ddx));
          bubble.style.transition = 'none'; bubble.style.transform = `translateX(${node.classList.contains('out') ? -dx : dx}px)`;
        });
        const up = () => {
          clearTimeout(t); if (!down) return; down = false;
          bubble.style.transition = 'transform 180ms var(--ease)'; bubble.style.transform = '';
          if (swiping && dx >= 56) { const m = findMsg(c, mid); if (m && canReply(m)) { st.reply = mid; st.edit = null; rerender(); el.querySelector('#draft')?.focus(); } }
        };
        ['pointerup', 'pointercancel', 'pointerleave'].forEach((ev) => node.addEventListener(ev, up));
        node.addEventListener('contextmenu', (e) => { e.preventDefault(); openActions(mid); });
        node.addEventListener('click', (e) => {
          if (long || swiping) return;
          if (st.selected.size) { toggleSel(mid); return; }
          const m = findMsg(c, mid);
          if (e.target.closest('.vplay')) { m.content.playing = !m.content.playing; m.content.progress = m.content.playing ? 0.35 : m.content.progress; m.content.positionLabel = m.content.playing ? '0:14' : null; m.content.played = true; rerender(); }
          else if (e.target.closest('.speed')) { m.content.speed = m.content.speed === 1 ? 1.5 : m.content.speed === 1.5 ? 2 : 1; rerender(); }
          else if (e.target.closest('.viewonce')) App.push('media-viewer', m.outgoing ? { viewOnce: 'mine' } : m.content.opened ? { viewOnce: 'opened' } : { i: 0 });
          else if (e.target.closest('.mi')) { const t = e.target.closest('.mi'); App.push('media-viewer', { i: [...t.parentNode.children].indexOf(t) }); }
          else if (e.target.closest('.d-act')) App.snack(m.content.transfer === 'notDownloaded' ? 'Downloading…' : 'Opens the share sheet');
          else if (e.target.closest('.react')) reactionsSheet(m);
          else if (e.target.closest('[data-retry]')) { m.status = 'pending'; rerender(); setTimeout(() => { m.status = 'sent'; if (entry.el.isConnected) rerender(); }, 800); }
          else if (e.target.closest('.quote')) App.snack('Jumps to the original message');
        });
      });
      const toggleSel = (mid) => { st.selected.has(mid) ? st.selected.delete(mid) : st.selected.add(mid); rerender(); };

      const isPlaceholder = (m) => m.content.type === 'placeholder';
      const canReply = (m) => !isPlaceholder(m) && m.content.type !== 'viewOnce';

      function openActions(mid) {
        const m = findMsg(c, mid); if (!m) return;
        const node = el.querySelector(`[data-msg="${CSS.escape(mid)}"]`);
        const deleted = m.content.type === 'placeholder' && m.content.kind === 'deleted';
        const hasText = m.content.type === 'text' || !!m.content.caption;
        const sent = m.status !== 'pending' && m.status !== 'failed';
        const items = [
          canReply(m) && ['reply', 'arrow-bend-up-left', 'Reply'],
          hasText && ['copy', 'copy', 'Copy'],
          !deleted && m.content.type !== 'viewOnce' && (m.content.type === 'text' || m.content.type === 'media') && ['forward', 'arrow-bend-up-right', 'Forward'],
          m.outgoing && sent && (m.content.type === 'text' || m.content.type === 'media') && ['edit', 'pencil-simple', 'Edit'],
          m.outgoing && ['info', 'info', 'Message info'],
          ['select', 'check-circle', 'Select'],
          ['delme', 'trash', 'Delete for me', 'danger'],
          !deleted && m.outgoing && sent && ['delall', 'trash-simple', 'Delete for everyone', 'danger'],
        ].filter(Boolean);
        const showReactions = !isPlaceholder(m);
        const h = App.overlay(`<div class="msg-actions ${m.outgoing ? 'out' : ''}">
          ${showReactions ? `<div class="ma-react">${UI.reactionSet.map((e) => `<button data-r="${e}" class="${m.reactions?.some((r) => r.mine && r.emoji === e) ? 'mine' : ''}" title="React with ${e}" aria-label="React with ${e}">${e}</button>`).join('')}<button class="more" title="More reactions" aria-label="More reactions">${icon('plus', 'bold')}</button></div>` : ''}
          <div class="ma-msg" style="width:100%">${node ? node.outerHTML : ''}</div>
          <div class="ma-menu">${items.map(([k, ic, label, cls]) => `<button data-a="${k}" class="${cls || ''}">${icon(ic)}${label}</button>`).join('')}</div>
        </div>`);
        const scrim = h.wrap.querySelector('.scrim'); scrim.style.background = 'rgba(13,16,25,.5)'; scrim.style.backdropFilter = 'blur(6px)';
        h.wrap.querySelector('.msg-actions').addEventListener('click', (e) => { if (e.target.classList.contains('msg-actions')) h.close(); });
        const react = (e) => {
          m.reactions = m.reactions || [];
          const mine = m.reactions.find((r) => r.mine);
          if (mine) { mine.count--; mine.mine = false; m.reactions = m.reactions.filter((r) => r.count > 0); }
          if (!mine || mine.emoji !== e) { const ex = m.reactions.find((r) => r.emoji === e); if (ex) { ex.count++; ex.mine = true; } else m.reactions.push({ emoji: e, count: 1, mine: true }); }
          rerender();
        };
        h.wrap.querySelectorAll('[data-r]').forEach((b) => b.addEventListener('click', () => { h.close(); react(b.dataset.r); }));
        h.wrap.querySelector('.ma-react .more')?.addEventListener('click', () => {
          h.close();
          const tab = 'Smileys';
          const sh = App.sheet({ title: 'React', body: `<div class="emoji-grid" style="max-height:300px">${Object.values(EMOJI).flat().map((e) => `<button data-e="${e}" aria-label="${e}">${e}</button>`).join('')}</div>` });
          sh.panel.querySelectorAll('[data-e]').forEach((b) => b.addEventListener('click', () => { sh.close(); react(b.dataset.e); }));
          return tab;
        });
        h.wrap.querySelectorAll('[data-a]').forEach((b) => b.addEventListener('click', () => {
          const a = b.dataset.a; h.close();
          if (a === 'reply') { st.reply = mid; st.edit = null; rerender(); el.querySelector('#draft')?.focus(); }
          if (a === 'edit') { st.edit = mid; st.reply = null; st.draft = previewText(m); rerender(); el.querySelector('#draft')?.focus(); }
          if (a === 'copy') App.snack('Copied');
          if (a === 'forward') App.push('forward', { n: 1 });
          if (a === 'info') App.push('message-info', { id });
          if (a === 'select') { st.selected.add(mid); rerender(); }
          if (a === 'delme') App.dialog({ title: 'Delete this message?', text: 'It is removed from this device only.', actions: [{ label: 'Cancel' }, { label: 'Delete for me', kind: 'danger', run: () => { removeForMe([mid]); rerender(); } }] });
          if (a === 'delall') App.dialog({ title: 'Delete for everyone?', text: 'People in this chat will see that it was deleted.', actions: [{ label: 'Cancel' }, { label: 'Delete for everyone', kind: 'danger', run: () => { m.content = { type: 'placeholder', kind: 'deleted' }; m.reactions = []; m.edited = false; rerender(); } }] });
        }));
      }

      function removeForMe(ids) { c.items = c.items.filter((it) => !(it.kind === 'msg' && ids.includes(it.m.id))); }

      function reactionsSheet(m) {
        const rows = (m.reactions || []).flatMap((r) => {
          const ppl = r.mine ? [{ name: 'You', color: 0 }] : [];
          const others = ['Ammu', 'Abbu', 'Rumana Apu', 'Nadia Rahman'].slice(0, r.count - (r.mine ? 1 : 0)).map((n) => ({ name: n }));
          return [...ppl, ...others].map((p) => `<div class="row">${avatar(p, 40)}<span class="rw-body"><span class="rw-title" style="display:block">${esc(p.name)}</span>${p.name === 'You' ? '<span class="rw-sub" style="display:block">Tap to remove</span>' : ''}</span><span style="font-size:22px">${r.emoji}</span></div>`);
        });
        App.sheet({ title: 'Reactions', body: rows.length ? `<div>${rows.join('')}</div>` : '<p style="padding:0 22px;color:var(--ink-3)">No reactions yet.</p>' });
      }

      // ---- Composer
      const draft = el.querySelector('#draft');
      if (draft) {
        const grow = () => { if (!draft.isConnected) return; draft.style.height = 'auto'; draft.style.height = Math.min(Math.max(draft.scrollHeight, 46), 128) + 'px'; };
        requestAnimationFrame(grow);
        draft.addEventListener('input', () => {
          const had = (st.draft || '').trim().length > 0; st.draft = draft.value;
          const has = st.draft.trim().length > 0;
          const wantMention = !!c.group && /@\w*$/.test(st.draft);
          if (had !== has || wantMention !== st.mention || wantMention) { st.mention = wantMention; const pos = draft.selectionStart; rerender(); const n = el.querySelector('#draft'); n.focus(); n.setSelectionRange(pos, pos); }
          else grow();
        });
        // Enter follows "Enter key sends" (You > Chats): on by default on a window, off on a phone (Review 1).
        const enterSends = () => { const v = window.OrbitPrefs && window.OrbitPrefs.chats.enter; return v == null ? App.isWide() : v; };
        draft.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey && enterSends()) { e.preventDefault(); send(); } });
        draft.addEventListener('focus', () => { if (st.emoji) { st.emoji = false; rerender(); el.querySelector('#draft')?.focus(); } });
      }
      el.querySelector('[data-send]')?.addEventListener('click', send);
      el.querySelector('[data-cancel-banner]')?.addEventListener('click', () => { if (st.edit) st.draft = ''; st.reply = null; st.edit = null; st.mention = false; rerender(); });
      el.querySelectorAll('[data-mention]').forEach((b) => b.addEventListener('click', () => { st.draft = st.draft.replace(/@\w*$/, '@' + b.dataset.mention + ' '); st.mention = false; rerender(); el.querySelector('#draft')?.focus(); }));
      el.querySelector('[data-emoji]')?.addEventListener('click', () => { st.emoji = !st.emoji; rerender(); if (!st.emoji) el.querySelector('#draft')?.focus(); });
      el.querySelectorAll('[data-etab]').forEach((b) => b.addEventListener('click', () => { st.emojiTab = b.dataset.etab; rerender(); }));
      el.querySelectorAll('.emoji-panel [data-e]').forEach((b) => b.addEventListener('click', () => { st.draft = (st.draft || '') + b.dataset.e; rerender(); }));
      el.querySelector('[data-cam]')?.addEventListener('click', cameraSheet);
      el.querySelector('[data-attach]')?.addEventListener('click', openAttach);
      el.querySelector('[data-confirm-member]')?.addEventListener('click', () => App.snack('Karim Uncle confirmed.'));
      el.querySelector('[data-remove-member]')?.addEventListener('click', () => App.dialog({ title: 'Remove Karim Uncle?', text: 'Karim Uncle will be taken out of the group. The group key changes, so they cannot read anything new.', actions: [{ label: 'Cancel' }, { label: 'Remove', kind: 'danger' }] }));

      // Voice: hold the mic to record, slide up to lock, release to send
      const mic = el.querySelector('[data-mic]');
      if (mic) {
        let held = false, t = null;
        mic.addEventListener('pointerdown', (e) => { e.preventDefault(); held = false; t = setTimeout(() => { held = true; st.recording = 'hold'; st.liveHold = true; rerender(); }, 220); });
        mic.addEventListener('pointerup', () => { clearTimeout(t); if (!held) App.snack('Hold the microphone to record a voice message.'); });
      }
      if (st.recording === 'hold' && st.liveHold) {
        const up = (e) => {
          document.removeEventListener('pointerup', up);
          if (st.recording !== 'hold' || !entry.el.isConnected) return;
          if (e.target.closest && e.target.closest('[data-lock]')) { st.recording = 'locked'; st.liveHold = false; rerender(); return; }
          st.recording = null; st.liveHold = false;
          addMine({ type: 'audio', durationLabel: '0:04', waveform: Data.wave, progress: 0, speed: 1, played: true });
        };
        document.addEventListener('pointerup', up);
      }
      el.querySelector('[data-lock]')?.addEventListener('click', () => { st.recording = 'locked'; st.liveHold = false; rerender(); });
      el.querySelector('[data-rec-send]')?.addEventListener('click', () => { if (st.recording !== 'locked' && st.liveHold) return; st.recording = null; addMine({ type: 'audio', durationLabel: '0:07', waveform: Data.wave.slice().reverse(), progress: 0, speed: 1, played: true }); });
      el.querySelector('[data-rec-cancel]')?.addEventListener('click', () => { st.recording = null; rerender(); });

      function cameraSheet() {
        App.sheet({ items: [
          { icon: 'camera', label: 'Take a photo', run: () => App.push('send-files') },
          { icon: 'video-camera', label: 'Record a video', run: () => App.push('send-files') },
        ] });
      }
      function openAttach() {
        const tile = (k, ic, color, label) => `<button class="attach-tile av-${color}" data-k="${k}"><span class="at-ico">${icon(ic, 'fill')}</span>${label}</button>`;
        const h = App.sheet({ body: `<div class="attach-grid" style="padding-top:8px">${tile('doc', 'file-text', 3, 'Document')}${tile('camera', 'camera', 5, 'Camera')}${tile('gallery', 'images', 0, 'Gallery')}${tile('audio', 'headphones', 4, 'Audio')}</div>` });
        h.panel.querySelectorAll('[data-k]').forEach((b) => b.addEventListener('click', () => {
          h.close();
          if (b.dataset.k === 'camera') setTimeout(cameraSheet, 80);
          else App.push('send-files');
        }));
      }
      if (params.attach && !st.attachShown) { st.attachShown = true; setTimeout(() => { el.querySelector('[data-attach]')?.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })); openAttach(); }, 50); }
      if (params.actions && !st.actionsShown) { st.actionsShown = true; setTimeout(() => openActions(params.actions), 80); }

      function addMine(content) {
        const m = { id: 'm' + Date.now(), outgoing: true, content, timeLabel: now(), status: 'pending', authorId: 'me', sentAt: 9999 };
        if (st.reply) { const r = findMsg(c, st.reply); m.reply = { authorName: r.outgoing ? 'You' : (r.authorName || peerName(c)), text: previewText(r), authorColorIndex: r.authorColorIndex }; }
        c.items = c.items.filter((it) => it.kind !== 'unread');
        c.items.push({ kind: 'msg', m });
        st.reply = null; st.draft = '';
        rerender();
        const scroll = () => { const t2 = entry.el.querySelector('.timeline'); if (t2) t2.scrollTop = t2.scrollHeight; };
        scroll();
        ['sent', 'delivered', 'read'].forEach((s2, i) => setTimeout(() => { m.status = s2; if (entry.el.isConnected) rerender(); }, 600 + i * 700));
        if (c.peer === 'nadia' && content.type === 'text') {
          setTimeout(() => { st.peerTyping = 'typing...'; st.showTyping = true; if (entry.el.isConnected) { rerender(); scroll(); } }, 2600);
          setTimeout(() => {
            st.peerTyping = null; st.showTyping = false;
            c.items.push({ kind: 'msg', m: { id: 'r' + Date.now(), outgoing: false, content: { type: 'text', text: 'Perfect 😄' }, timeLabel: now(), authorId: 'nadia', sentAt: 10000 } });
            if (entry.el.isConnected) { rerender(); scroll(); }
          }, 4400);
        }
      }

      function send() {
        const text = (st.draft || '').trim(); if (!text) return;
        if (st.edit) { const m = findMsg(c, st.edit); m.content = { ...m.content, text }; m.edited = true; st.edit = null; st.draft = ''; rerender(); return; }
        addMine({ type: 'text', text, mentions: c.group ? (text.match(/@([\w ]+?)(?=\s|$)/g) || []).map((x) => x.slice(1)) : [] });
        setTimeout(() => entry.el.querySelector('#draft')?.focus(), 20);
      }
    },
  });
})();
