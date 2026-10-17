/*
  Components as HTML-string functions. Each takes the same fields as the
  Flutter view model it stands for (helix_remote_ui/lib/src/view_models.dart),
  so the port is a 1:1 translation:
    UI.chatRow(HelixChatListItem)   -> HelixChatListTile
    UI.message(HelixMessage, pos)   -> HelixMessageBubble
    UI.callRow(HelixCallLogItem)    -> HelixCallLogTile
*/
const UI = (() => {
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  // The theme sets the default icon weight (Bloom light, Mochi duotone, Arcade bold...).
  let themeWeight = '';
  const setIconWeight = (w) => { themeWeight = w || ''; };
  const icon = (name, weight = '') => { const w = weight || themeWeight; return `<i class="ph${w ? '-' + w : ''} ph-${name}" aria-hidden="true"></i>`; };

  /** HelixIconButton: 48 px target, tooltip required. */
  const ibtn = (name, tip, attrs = '', cls = '', weight = '') =>
    `<button class="ibtn ${cls}" title="${esc(tip)}" aria-label="${esc(tip)}" ${attrs}>${icon(name, weight)}</button>`;

  /** Same as helixInitials() in Dart. */
  function initials(name) {
    const words = String(name || '').replace(/~/g, '').split(/\s+/).filter(Boolean);
    if (!words.length) return '#';
    const a = [...words[0]][0];
    if (!/\p{L}/u.test(a)) return '#';
    if (words.length === 1) return a.toUpperCase();
    return (a + [...words[words.length - 1]][0]).toUpperCase();
  }

  /** Same hash as HelixAvatarModel.colorIndexFor, over the 8-colour palette. */
  function colorIndexFor(seed) {
    let h = 0x811c9dc5;
    for (const ch of String(seed)) { h = (Math.imul(h ^ ch.charCodeAt(0), 0x01000193)) & 0x7fffffff; }
    return h % 8;
  }

  /**
   * HelixAvatar. a = { name, seed?, group?, photo? (css class), online?, verified? }
   */
  function avatar(a, size = 48, opts = {}) {
    const ci = a.color ?? colorIndexFor(a.seed || a.name);
    const inner = a.photo ? '' : a.group ? icon('users-three', 'fill') : esc(initials(a.name));
    const extra = (opts.check ? `<span class="av-check">${icon('check', 'bold')}</span>` : '') +
      (opts.online && a.online ? '<span class="av-online"></span>' : '');
    return `<span class="av av-${ci} ${a.photo ? 'photo ' + a.photo : ''} ${opts.cls || ''}" style="--size:${size}px" aria-hidden="true">${inner}${extra}</span>`;
  }

  // ------------------------------------------------------------ chat list
  const previewLabels = {
    image: ['image', 'Photo'], video: ['video-camera', 'Video'], gif: ['gif', 'GIF'], voiceNote: ['microphone', 'Voice message'],
    document: ['file-text', 'Document'], sticker: ['sticker', 'Sticker'], location: ['map-pin', 'Location'], contact: ['user-circle', 'Contact'],
    poll: ['chart-bar-horizontal', 'Poll'], call: ['phone', 'Call'], deleted: ['prohibit', 'This message was deleted'],
    undecryptable: ['lock-simple', "Couldn't decrypt this message"], unsupported: ['arrow-circle-up', 'Needs a newer version of Orbit'],
  };
  const italicKinds = new Set(['deleted', 'undecryptable', 'unsupported']);

  /** Delivery tick for HelixDeliveryStatus. */
  function tick(status) {
    switch (status) {
      case 'pending': return `<i class="ph ph-clock tick" title="Sending" aria-label="Sending"></i>`;
      case 'sent': return `<i class="ph ph-check tick" title="Sent" aria-label="Sent"></i>`;
      case 'delivered': return `<i class="ph ph-checks tick" title="Delivered" aria-label="Delivered"></i>`;
      case 'read': return `<i class="ph-bold ph-checks tick read" title="Read" aria-label="Read"></i>`;
      case 'failed': return `<i class="ph-fill ph-warning-circle tick failed" title="Not sent" aria-label="Not sent"></i>`;
      default: return '';
    }
  }

  function previewHtml(item) {
    if (item.typingLabel) return `<span class="cr-preview typing">${esc(item.typingLabel)}</span>`;
    const p = item.preview;
    if (!p) return '<span class="cr-preview"></span>';
    const [ic, label] = previewLabels[p.kind] || [null, ''];
    const text = p.text || label;
    const parts = [];
    if (p.isDraft) parts.push('<span class="draft">Draft:</span>');
    else {
      if (p.status) parts.push(tick(p.status));
      if (p.senderPrefix) parts.push(`<span class="who">${esc(p.senderPrefix)}:</span>`);
    }
    if (ic && p.kind !== 'text') parts.push(icon(ic));
    parts.push(`<span class="pv-text" ${italicKinds.has(p.kind) ? 'style="font-style:italic"' : ''}>${esc(text)}</span>`);
    return `<span class="cr-preview">${parts.join('')}</span>`;
  }

  /** HelixChatListTile. Rows never show presence or a marked-unread dot (the app sets neither). */
  function chatRow(item, { selected = false, showArchived = false, active = false } = {}) {
    const unread = item.unreadCount > 0;
    let trailing = '';
    if (item.hasMention && unread) trailing += `<span class="badge mention ${item.muted ? 'muted' : ''}" title="You were mentioned">@</span>`;
    if (unread) trailing += `<span class="badge ${item.muted ? 'muted' : ''}">${item.unreadCount > 99 ? '99+' : item.unreadCount}</span>`;
    const flags = (item.muted ? icon('bell-slash') : '') + (item.pinned ? icon('push-pin', 'fill') : '') + (showArchived && item.archived ? icon('archive') : '');
    return `<button class="chat-row ${unread && !item.muted ? 'unread' : ''} ${unread ? 'has-unread' : ''} ${selected || active ? 'selected' : ''}" data-chat="${esc(item.id)}" aria-label="${esc(item.title)}">
      ${avatar(item.avatar, 52, { check: selected })}
      <span class="cr-body">
        <span class="cr-top"><span class="cr-name"><span class="nm">${esc(item.title)}</span>${item.verified ? `<i class="ph-fill ph-seal-check seal" title="Safety number verified"></i>` : ''}</span><span class="cr-time">${esc(item.timeLabel)}</span></span>
        <span class="cr-bottom">${previewHtml(item)}<span class="cr-flags">${flags}${trailing}</span></span>
      </span>
    </button>`;
  }

  // ---------------------------------------------------------- conversation
  const reactionSet = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  function wave(samples, progress = 0, bars = 36) {
    const out = [];
    for (let i = 0; i < bars; i++) {
      const v = samples[Math.floor((i / bars) * samples.length)] ?? 60;
      const h = Math.max(12, Math.round((v / 255) * 100));
      out.push(`<b class="${i / bars < progress ? 'on' : ''}" style="height:${h}%"></b>`);
    }
    return `<span class="wave">${out.join('')}</span>`;
  }

  function meta(m, { onMedia = false } = {}) {
    const bits = [];
    if (m.expiresLabel) bits.push(`<span class="exp" title="Disappearing message">${icon('timer')}${esc(m.expiresLabel)}</span>`);
    if (m.edited) bits.push('<span>Edited</span>');
    bits.push(`<span>${esc(m.timeLabel)}</span>`);
    if (m.outgoing) bits.push(tick(m.status));
    return `<span class="meta ${onMedia ? 'on-media' : ''}">${bits.join('')}</span>`;
  }

  function richText(text, mentions = []) {
    let html = esc(text);
    html = html.replace(/(https?:\/\/[^\s<]+)/g, '<a href="#" onclick="return false">$1</a>');
    mentions.forEach((name) => { html = html.split(esc('@' + name)).join(`<span class="mention">@${esc(name)}</span>`); });
    return html;
  }

  function quoteHtml(q) {
    if (!q) return '';
    const ci = q.authorColorIndex ?? colorIndexFor(q.authorName);
    const [ic, label] = previewLabels[q.kind] || [null, ''];
    const text = q.missing ? 'Original message not available' : (q.text || label);
    return `<span class="quote av-${ci} ${q.missing ? 'missing' : ''}" data-jump="${esc(q.targetId || '')}">
      <span class="q-body"><span class="q-name">${esc(q.authorName)}</span><span class="q-text">${ic && q.kind !== 'text' ? icon(ic) + ' ' : ''}${esc(text)}</span></span>
      ${q.thumb ? `<span class="q-thumb ${q.thumb}"></span>` : ''}
    </span>`;
  }

  function mediaHtml(items) {
    const n = Math.min(items.length, 4);
    const cells = items.slice(0, 4).map((it, i) => {
      const ratio = n === 1 ? `aspect-ratio:${it.width || 4}/${it.height || 3};` : n === 3 && i === 0 ? 'aspect-ratio:2/1;' : 'aspect-ratio:1;';
      let center = '';
      if (it.transfer === 'notDownloaded') center = `<span class="dl">${icon('download-simple', 'bold')}${esc(it.sizeLabel || '')}</span>`;
      else if (it.transfer === 'downloading' || it.transfer === 'uploading') center = `<span class="ring" style="--p:${it.progress ?? 0.3}">${icon('x', 'bold')}</span>`;
      else if (it.transfer === 'failed') center = `<span class="dl">${icon('arrow-clockwise', 'bold')}Retry</span>`;
      else if (it.isVideo) center = `<span class="play">${icon('play', 'fill')}</span>`;
      const dur = it.isVideo && it.durationLabel ? `<span class="dur">${icon('video-camera', 'fill')}${esc(it.durationLabel)}</span>` : it.isGif ? '<span class="dur">GIF</span>' : '';
      const more = i === 3 && items.length > 4 ? `<span class="more">+${items.length - 4}</span>` : '';
      return `<span class="mi ${it.photo || 'ph-a'}" style="${ratio}">${center}${dur}${more}</span>`;
    }).join('');
    return `<span class="media-grid n${n}">${cells}</span>`;
  }

  function contentHtml(m) {
    const c = m.content;
    switch (c.type) {
      case 'text': {
        // Link previews never carry an image in the app.
        const lp = c.linkPreview ? `<span class="linkcard"><span class="lc-body" style="display:block"><span class="lc-title" style="display:block">${esc(c.linkPreview.title)}</span><span class="lc-desc" style="display:block">${esc(c.linkPreview.description || '')}</span><span class="lc-host" style="display:block">${icon('link-simple')} ${esc(c.linkPreview.host)}</span></span></span>` : '';
        return { cls: '', html: lp + richText(c.text, c.mentions) };
      }
      case 'poll':
        return { cls: '', html: richText(`Poll: ${c.question}\n${c.options.map((o) => `- ${o}`).join('\n')}`) };
      case 'media':
        return { cls: 'media', html: mediaHtml(c.items) + (c.caption ? `<div class="caption">${richText(c.caption)}</div>` : ''), metaOnMedia: !c.caption };
      case 'audio': {
        const playIcon = c.playing ? icon('pause', 'fill') : c.transfer === 'notDownloaded' ? icon('download-simple', 'bold') : icon('play', 'fill');
        const isVoice = c.isVoiceNote !== false;
        // Speed chip only while playing or when not 1x; audio files have no dot and no chip.
        const chip = isVoice && (c.playing || c.speed !== 1) ? `<button class="speed" title="Playback speed">${c.speed}x</button>` : '';
        const dot = isVoice && !m.outgoing && !c.played ? '<span class="played" title="Not played yet"></span>' : '';
        return {
          cls: '', html: `<span class="voice"><button class="vplay" title="${c.playing ? 'Pause' : 'Play'}" aria-label="${c.playing ? 'Pause' : 'Play'}">${playIcon}</button>
          <span class="vmid">${isVoice ? '' : `<span class="d-name" style="display:block;font-size:13px;font-weight:560;margin-bottom:2px">${esc(c.title)}</span>`}${wave(c.waveform || [], c.progress)}<span class="vfoot"><span>${esc(c.positionLabel || c.durationLabel)}${dot}</span></span></span>${chip}</span>`,
        };
      }
      case 'document': {
        const act = c.transfer === 'notDownloaded' ? icon('download-simple', 'bold') : c.transfer === 'downloading' || c.transfer === 'uploading' ? icon('x', 'bold') : c.transfer === 'failed' ? icon('arrow-clockwise', 'bold') : icon('arrow-square-out');
        const bar = c.progress != null ? `<span class="bar"><b style="width:${Math.round(c.progress * 100)}%"></b></span>` : '';
        return { cls: '', html: `<span class="doc"><span class="d-ico">${icon('file-text', 'fill')}<span class="d-type">${esc(c.typeLabel)}</span></span><span class="d-body"><span class="d-name" style="display:block">${esc(c.name)}</span><span class="d-sub" style="display:block">${esc(c.sizeLabel)} · ${esc(c.typeLabel)}</span>${bar}</span><span class="d-act">${act}</span></span>${c.caption ? `<div style="margin-top:6px">${richText(c.caption)}</div>` : ''}` };
      }
      case 'location':
        return { cls: '', html: `<span class="loc" style="display:block"><span class="map">${icon('map-pin', 'fill')}</span><span class="l-body" style="display:block"><span class="l-title" style="display:block">${esc(c.label || 'Location')}</span><span class="l-sub" style="display:block">${esc(c.address)}</span></span></span>` };
      case 'contact':
        return { cls: '', html: `<span class="contact" style="display:block"><span class="ct-top">${avatar({ name: c.name }, 40)}<span><span class="ct-name" style="display:block">${esc(c.name)}</span><span class="ct-sub" style="display:block">${esc(c.detail)}</span></span></span></span>` };
      case 'viewOnce': {
        const status = c.opened ? 'Opened' : m.outgoing ? 'Sent' : 'Tap to view';
        return { cls: '', html: `<span class="viewonce ${c.opened ? 'opened' : ''}"><span class="vo-ico">1</span><span><span style="display:block">${c.isVideo ? 'Video' : 'Photo'}</span><span class="mono" style="display:block;font-size:11px;font-weight:450;color:var(--ink-3)">${c.opened ? icon('check') + ' ' : ''}${status}</span></span></span>` };
      }
      case 'placeholder': {
        const map = {
          deleted: ['prohibit', m.outgoing ? 'You deleted this message' : 'This message was deleted', ''],
          undecryptable: ['lock-simple', "Couldn't decrypt this message", 'warn'],
          unsupported: ['arrow-circle-up', 'This message needs a newer version of Orbit', ''],
          expired: ['timer', 'This message has disappeared', ''],
        };
        const [ic, text, extra] = map[c.kind];
        return { cls: `placeholder ${extra}`, html: `${icon(ic)}<span>${text}</span>` };
      }
      default: return { cls: '', html: '' };
    }
  }

  /**
   * HelixMessageBubble. pos: single | first | middle | last.
   * opts: { group, showAvatar, selected }
   */
  function message(m, pos = 'single', opts = {}) {
    const c = contentHtml(m);
    const ci = m.authorColorIndex ?? colorIndexFor(m.authorName || '');
    const showAuthor = opts.group && !m.outgoing && (pos === 'single' || pos === 'first') && m.authorName;
    const withAv = opts.group && !m.outgoing;
    const avHtml = withAv && (pos === 'single' || pos === 'last') ? `<span class="m-av">${avatar({ name: m.authorName, color: ci }, 30)}</span>` : '';
    const fwd = m.forwarded ? `<span class="fwd">${icon('arrow-bend-up-right', 'bold')}Forwarded</span>` : '';
    const reacts = m.reactions && m.reactions.length ? `<div class="reacts">${m.reactions.map((r) => `<button class="react ${r.mine ? 'mine' : ''}" title="${r.mine ? 'Tap to remove your reaction' : 'React'}">${r.emoji}${r.count > 1 ? `<b>${r.count}</b>` : ''}</button>`).join('')}</div>` : '';
    const failed = m.outgoing && m.status === 'failed' ? `<div class="failed-line">${icon('warning-circle', 'fill')} Not sent <button data-retry="${esc(m.id)}">Retry</button></div>` : '';
    const metaHtml = c.cls.includes('placeholder') ? meta({ ...m, edited: false }) : meta(m, { onMedia: c.metaOnMedia });
    return `<div class="msg ${m.outgoing ? 'out' : 'in'} ${pos} av-${ci} ${withAv ? 'with-av' : ''} ${opts.selected ? 'selected' : ''} ${m.highlighted ? 'highlight' : ''}" data-msg="${esc(m.id)}">
      ${showAuthor ? `<div class="author">${esc(m.authorName)}</div>` : ''}
      ${avHtml}
      <div class="bubble ${c.cls}">${fwd}${quoteHtml(m.reply)}${c.html}${metaHtml}</div>
      ${reacts}${failed}
    </div>`;
  }

  /** helixRunPositions(): same rule as Dart (sender + 5 minute gap). */
  function runPositions(msgs) {
    const same = (a, b) => a && b && a.kind === 'msg' && b.kind === 'msg' && a.m.outgoing === b.m.outgoing && (a.m.authorId || '') === (b.m.authorId || '') && Math.abs((b.m.sentAt || 0) - (a.m.sentAt || 0)) <= 5;
    return msgs.map((it, i) => {
      if (it.kind !== 'msg') return null;
      const p = same(msgs[i - 1], it); const n = same(it, msgs[i + 1]);
      return p && n ? 'middle' : p ? 'last' : n ? 'first' : 'single';
    });
  }

  /** Timeline entries: {kind:'msg', m} | {kind:'day', label} | {kind:'unread', count} | {kind:'notice', text, icon, tone} | {kind:'e2e'} | {kind:'typing'} */
  function timeline(items, opts = {}) {
    const pos = runPositions(items);
    return items.map((it, i) => {
      switch (it.kind) {
        case 'msg': return message(it.m, pos[i], { group: opts.group, selected: opts.selected && opts.selected.has(it.m.id) });
        case 'day': return `<div class="day"><span>${esc(it.label)}</span></div>`;
        case 'unread': return `<div class="unread-div">${it.count} unread message${it.count === 1 ? '' : 's'}</div>`;
        case 'notice': return `<div class="notice ${it.tone || ''}">${it.icon ? icon(it.icon, it.tone === 'calllog missed' ? 'fill' : '') : ''}<span>${esc(it.text)}</span></div>`;
        case 'empty': return `<div class="e2e-card">${icon('lock-simple', 'fill')}<span>Messages are end-to-end encrypted. Say hello.</span></div>`;
        case 'typing': return `<div class="msg in single"><div class="bubble typing-bubble"><span></span><span></span><span></span></div></div>`;
        default: return '';
      }
    }).join('');
  }

  // ----------------------------------------------------------------- calls
  // Incoming and outgoing green, missed red, declined grey, failed a red error mark.
  const callIcons = {
    incoming: ['arrow-down-left', 'var(--success)', 'Incoming', 'bold'],
    outgoing: ['arrow-up-right', 'var(--success)', 'Outgoing', 'bold'],
    missed: ['arrow-down-left', 'var(--danger)', 'Missed', 'bold'],
    declined: ['arrow-down-left', 'var(--ink-4)', 'Declined', 'bold'],
    failed: ['warning-circle', 'var(--danger)', 'Failed', 'fill'],
  };

  /** HelixCallLogTile */
  function callRow(c) {
    const [ic, color, label, weight] = callIcons[c.direction];
    const red = c.direction === 'missed' || c.direction === 'failed';
    return `<div class="swipe-wrap"><div class="swipe-bg" style="background:var(--danger);justify-content:flex-end"><span class="sw-end">${icon('trash', 'fill')}Delete</span></div>
    <div class="chat-row call-row" data-call="${esc(c.id)}" role="button" tabindex="0" aria-label="${esc(c.title)}">
      ${avatar(c.avatar, 52)}
      <span class="cr-body">
        <span class="cr-top"><span class="cr-name" style="${red ? 'color:var(--danger)' : ''}"><span class="nm">${esc(c.title)}${c.count > 1 ? ` (${c.count})` : ''}</span></span></span>
        <span class="cr-bottom"><span class="cr-preview"><i class="ph-${weight} ph-${ic}" style="color:${color}" aria-label="${label}"></i>${c.video ? icon('video-camera') : ''}<span class="pv-text mono" style="font-size:12px">${esc(c.timeLabel)}</span></span></span>
      </span>
      ${ibtn(c.video ? 'video-camera' : 'phone', c.video ? 'Video call' : 'Voice call', `data-callback="${esc(c.id)}"`, 'accent')}
    </div></div>`;
  }

  // ------------------------------------------------------------- generic rows
  /** HelixListRow: { icon, color, title, sub, value, end ('chevron'|'switch'|html), on, danger, attrs } */
  function row(r) {
    const ic = r.icon ? `<span class="rw-ico ${r.color != null ? 'av-' + r.color : ''}">${icon(r.icon, r.weight || '')}</span>` : '';
    let end = '';
    if (r.end === 'switch') end = `<span class="switch ${r.on ? 'on' : ''}" role="switch" aria-checked="${!!r.on}"></span>`;
    else if (r.end === 'chevron') end = icon('caret-right');
    else if (r.end) end = r.end;
    const tag = r.tag || 'button';
    return `<${tag} class="row ${r.danger ? 'danger' : ''} ${r.accent ? 'accent' : ''}" ${r.attrs || ''}>${ic}<span class="rw-body"><span class="rw-title" style="display:block">${r.title}</span>${r.sub ? `<span class="rw-sub ${r.subMono ? 'mono' : ''}" style="display:block">${r.sub}</span>` : ''}</span>${r.value || end ? `<span class="rw-end">${r.value ? `<span class="rw-value">${r.value}</span>` : ''}${end}</span>` : ''}</${tag}>`;
  }

  function card(rows, { title, cls = '' } = {}) {
    return `${title ? `<div class="group-title eyebrow">${title}</div>` : ''}<div class="card ${cls}">${rows.join('')}</div>`;
  }

  function appbar({ title, sub, back = true, actions = '', cls = '' }) {
    return `<header class="appbar ${cls}">${back ? ibtn('arrow-left', 'Back', 'data-back') : '<span style="width:8px"></span>'}<div class="ab-title"><h1>${title}</h1>${sub ? `<div class="ab-sub">${sub}</div>` : ''}</div>${actions}</header>`;
  }

  // How the device confirms it is you: Windows Hello on a Windows window, the
  // phone's own lock otherwise. In Flutter: Platform.isWindows.
  const unlock = () => (App.isWide()
    ? { what: 'Windows Hello', full: 'Windows Hello (your face, fingerprint or PIN)', button: 'Use Windows Hello' }
    : { what: 'your fingerprint, face or phone PIN', full: 'your fingerprint, face or phone PIN', button: 'Use fingerprint' });

  function empty({ icon: ic, title, text, action }) {
    return `<div class="empty"><div class="em-art">${icon(ic)}</div><h3>${title}</h3>${text ? `<p>${text}</p>` : ''}${action || ''}</div>`;
  }

  return { unlock, setIconWeight, esc, icon, ibtn, initials, colorIndexFor, avatar, tick, chatRow, previewHtml, message, timeline, runPositions, wave, callRow, row, card, appbar, empty, reactionSet, previewLabels };
})();
