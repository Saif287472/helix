/*
  Console components as HTML strings, one function per Flutter widget the
  port will have (ConsolePageHeader, ConsoleMetric, ConsoleUserCard,
  ConsoleReportCard, ConsoleAuditRow, ConsoleInviteCard, ConsoleSettingRow,
  ConsoleField...). Data in, actions out.
*/
const UI = (() => {
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const icon = (name, weight = '') => `<i class="ph${weight ? '-' + weight : ''} ph-${name}" aria-hidden="true"></i>`;
  const ibtn = (name, tip, attrs = '', cls = '', weight = '') =>
    `<button type="button" class="ibtn ${cls}" title="${esc(tip)}" aria-label="${esc(tip)}" ${attrs}>${icon(name, weight)}</button>`;

  // ------------------------------------------------------------- accounts
  const accountById = (id) => DATA.accounts.find((a) => a.id === id) || null;
  const shortId = (id) => String(id || '').slice(0, 8);
  const accountTitle = (a) => a.displayName || a.helixName || 'No Helix name';
  const accountHandle = (a) => a.helixName ? `@${a.helixName}` : 'No Helix name';
  const firstName = (a) => accountTitle(a).split(/\s+/)[0];

  function day(iso) {
    if (!iso) return 'Never';
    const d = new Date(`${String(iso).slice(0, 10)}T00:00:00`);
    if (Number.isNaN(d.getTime())) return String(iso);
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  }
  const capitalize = (s) => String(s || '').charAt(0).toUpperCase() + String(s || '').slice(1);

  function initials(name) {
    const words = String(name || '').replace(/~/g, '').split(/\s+/).filter(Boolean);
    if (!words.length) return '#';
    const a = [...words[0]][0];
    if (!/\p{L}/u.test(a)) return '#';
    if (words.length === 1) return a.toUpperCase();
    return (a + [...words[words.length - 1]][0]).toUpperCase();
  }
  function colorIndexFor(seed) {
    let h = 0x811c9dc5;
    for (const ch of String(seed)) { h = (Math.imul(h ^ ch.charCodeAt(0), 0x01000193)) & 0x7fffffff; }
    return h % 8;
  }
  function avatar(a, size = 32) {
    const name = typeof a === 'string' ? a : accountTitle(a);
    const ci = (typeof a === 'object' && a.color != null) ? a.color : colorIndexFor(name);
    return `<span class="av av-${ci}" style="--size:${size}px;--avatar-r:${Math.round(size * 0.28)}px" aria-hidden="true">${esc(initials(name))}</span>`;
  }

  const btn = (label, kind = 'secondary', { icon: ic = '', attrs = '', sm = false, disabled = false, cls = '' } = {}) =>
    `<button type="button" class="btn ${kind} ${sm ? 'sm' : ''} ${cls}" ${disabled ? 'disabled' : ''} ${attrs}>${ic ? icon(ic) : ''}${label}</button>`;
  const copyBtn = (value, label = 'Copy') => ibtn('copy', `${label} ${value}`, `data-copy="${esc(value)}"`, 'sm');

  const STATUS = {
    active: ['ok', 'Active'], suspended: ['bad', 'Suspended'],
    open: ['warn', 'Open'], resolved: ['ok', 'Resolved'], dismissed: ['mute', 'Dismissed'],
    used: ['mute', 'Used'], cancelled: ['mute', 'Cancelled'], expired: ['mute', 'Expired'],
    revoked: ['mute', 'Revoked'], ok: ['ok', 'Operational'], warn: ['warn', 'Degraded'], bad: ['bad', 'Down'],
    online: ['ok', 'Online'], live: ['ok', 'Live streaming'], paused: ['mute', 'Stream paused'],
    ready: ['ok', 'Ready'], notready: ['warn', 'Not ready'],
  };
  function statusPill(status, label) {
    const [tone, text] = STATUS[status] || ['mute', status];
    return `<span class="pill ${tone}"><span class="pd"></span>${esc(label || text)}</span>`;
  }
  const tag = (text, tone = '') => `<span class="tag ${tone}">${esc(text)}</span>`;
  const pill = (text, tone = 'mute', ic = '') => `<span class="pill ${tone}">${ic ? icon(ic) : ''}${esc(text)}</span>`;
  const stateDot = (tone = 'ok') => `<span class="state-dot ${tone}" aria-hidden="true"></span>`;

  const PLATFORM = {
    android: ['android-logo', 'Android'], windows: ['windows-logo', 'Windows'],
    macos: ['apple-logo', 'macOS'], ios: ['apple-logo', 'iOS'], cli: ['terminal-window', 'CLI'],
  };
  const platform = (p) => PLATFORM[p] || [p, p];

  // ----------------------------------------------------------------- layout
  function pageHead({ eyebrow, title, sub, actions = '', back = false }) {
    return `${back ? `<div class="backbar"><button class="backbtn" data-back>${icon('arrow-left')}Back</button></div>` : ''}
      <header class="pg-head">
        ${eyebrow ? `<div class="pg-eyebrow">${eyebrow}</div>` : ''}
        <div class="pg-title-row">
          <div style="min-width:0"><h1 class="pg-title">${title}</h1>${sub ? `<p class="pg-sub">${sub}</p>` : ''}</div>
          ${actions ? `<div class="pg-actions">${actions}</div>` : ''}
        </div>
      </header>`;
  }

  function page({ eyebrow, title, sub, actions = '', back = false, body, tabs = '', cls = '' }) {
    return `${pageHead({ eyebrow, title, sub, actions, back })}${tabs}
      <div class="scroll ${cls}" data-keep-scroll="page"><div class="pg-body">${body}</div></div>`;
  }

  const searchbar = (id, placeholder, value = '') =>
    `<label class="searchbar">${icon('magnifying-glass')}<input id="${id}" type="search" placeholder="${esc(placeholder)}" value="${esc(value)}" autocomplete="off" /></label>`;

  const OPS = [['reports', 'Reports', 'flag'], ['audit', 'Audit', 'scroll'], ['logs', 'Logs', 'terminal-window'], ['config', 'Config', 'sliders-horizontal']];
  function opsTabs(active, openReports = 0) {
    return `<div class="ops-wrap"><div class="ops-tabs" role="tablist" aria-label="Operations">
      ${OPS.map(([id, label, ic]) => `<button class="ops-tab ${id === active ? 'on' : ''}" role="tab" aria-selected="${id === active}" data-opstab="${id}">${icon(ic)}<span>${label}</span>${id === 'reports' && openReports ? `<span class="ot-count">${openReports}</span>` : ''}</button>`).join('')}
    </div></div>`;
  }

  function fchips(items, active) {
    return `<div class="chips" role="group">${items.map(([v, label, n], i) => {
      const on = active != null ? v === active : i === 0;
      return `<button class="fchip ${on ? 'on' : ''}" data-filter="${esc(v)}" aria-pressed="${on}">${esc(label)}${n != null ? ` <span class="n">${n}</span>` : ''}</button>`;
    }).join('')}</div>`;
  }

  const section = (title, note = '') =>
    `<div class="sec-label">${esc(title)}${note ? `<span class="spacer"></span><span class="sl-note">${note}</span>` : ''}</div>`;

  const banner = ({ tone = 'accent', ic = 'info', title, text = '', actions = '' }) =>
    `<div class="banner ${tone}">${icon(ic)}<div class="bn-body"><div class="bn-title">${title}</div>${text ? `<div class="bn-text">${text}</div>` : ''}${actions ? `<div class="bn-actions">${actions}</div>` : ''}</div></div>`;

  const kv = (k, v, { mono = false } = {}) =>
    `<div class="kv"><span class="k">${esc(k)}</span><span class="v ${mono ? 'mono' : ''}">${v}</span></div>`;

  const prop = (k, v, { mono = true } = {}) =>
    `<div class="prop"><span class="prop-k">${esc(k)}</span><span class="prop-v ${mono ? 'mono' : ''}">${v}</span></div>`;

  const num = (n) => Number(n).toLocaleString('en-US');

  // --------------------------------------------------------------- overview
  function metric({ label, value, sub, icon: ic, tone = '' }) {
    return `<div class="mcard ${tone}">
      <div class="mc-top"><span class="mc-label">${esc(label)}</span><span class="mc-ico">${icon(ic)}</span></div>
      <div class="mc-value">${value}</div>
      <div class="mc-sub">${sub}</div>
    </div>`;
  }

  function healthRow({ name, sub, tone = 'ok', text, ic }) {
    return `<div class="health-row">
      <span class="hr-ico">${icon(ic)}</span>
      <span class="hr-body"><span class="hr-name">${esc(name)}</span><span class="hr-sub">${esc(sub)}</span></span>
      <span class="hr-end ${tone}">${stateDot(tone)}${esc(text)}</span>
    </div>`;
  }

  // ------------------------------------------------------------------ users
  function userCard(a, { selected = false } = {}) {
    const reports = a.openReports
      ? `<span class="uc-report">${icon('flag')}${a.openReports} open report${a.openReports === 1 ? '' : 's'}</span>` : '';
    return `<div class="user-card ${selected ? 'on' : ''}" role="button" tabindex="0" data-user="${esc(a.id)}">
      ${avatar(a, 34)}
      <div class="uc-body">
        <div class="uc-top"><span class="uc-name">${esc(accountTitle(a))}</span>${statusPill(a.status)}</div>
        <div class="uc-sub">${esc(a.phone)} <span class="uc-handle">${esc(accountHandle(a))}</span></div>
        <div class="uc-meta"><span>${a.activeDevices} device${a.activeDevices === 1 ? '' : 's'}</span><span>Joined ${esc(day(a.createdAt))}</span>${reports}</div>
      </div>
      <span class="uc-chev">${icon('caret-right')}</span>
    </div>`;
  }

  function deviceRow(d) {
    const [ic, label] = platform(d.platform);
    return `<div class="device-row">
      <span class="dv-ico">${icon(ic)}</span>
      <span class="dv-body">
        <span class="dv-name">${esc(d.name)} <span class="dv-plat">${esc(label)}</span></span>
        <span class="dv-sub">${d.active ? `Last seen ${esc(day(d.lastSeenOn))}` : `Revoked ${esc(day(d.revokedAt))} · last seen ${esc(day(d.lastSeenOn))}`}</span>
      </span>
      ${d.active
        ? `${statusPill('active')}<button class="btn secondary sm" data-revoke="${esc(d.id)}" data-device-name="${esc(d.name)}">Revoke</button>`
        : statusPill('revoked')}
    </div>`;
  }

  function openReportsPill(a) {
    return a.openReports ? `<span class="pill warn">${icon('flag')}${a.openReports} open</span>` : '';
  }

  // ---------------------------------------------------------------- reports
  const CATEGORY = {
    spam: ['Spam', 'megaphone'], abuse: ['Abuse', 'shield-warning'],
    impersonation: ['Impersonation', 'user-focus'], other: ['Other', 'dots-three-circle'],
  };
  function reportCard(r) {
    const subject = accountById(r.subject);
    const reporter = accountById(r.reporter);
    const cat = CATEGORY[r.category] || [capitalize(r.category), 'flag'];
    const open = r.status === 'open';
    return `<article class="report-card" data-report="${esc(r.id)}" data-status="${esc(r.status)}">
      <div class="rc-top">
        <span class="rc-ico">${icon(cat[1])}</span>
        <span class="rc-cat">${esc(cat[0])}</span>
        ${statusPill(r.status)}
        <span class="spacer"></span>
        <span class="rc-time">${esc(r.createdAt)}</span>
      </div>
      <div class="rc-who">
        <span>Account <button class="linkbtn mono" data-open-account="${esc(r.subject)}">${esc(shortId(r.subject))}</button></span>
        <span class="rc-sep">·</span>
        <span>reported by <span class="mono">${esc(shortId(r.reporter))}</span></span>
        ${subject ? `<span class="rc-name">${esc(accountTitle(subject))}</span>` : ''}
      </div>
      <p class="rc-note">${esc(r.note)}</p>
      <div class="rc-foot">
        <span class="rc-id mono">${esc(r.id)}</span>
        <span class="spacer"></span>
        <button class="btn ghost sm" data-open-account="${esc(r.subject)}">Open account</button>
        ${open ? `<button class="btn secondary sm" data-dismiss="${esc(r.id)}">Dismiss</button>
        <button class="btn primary sm" data-resolve="${esc(r.id)}">Resolve</button>` : `<span class="rc-closed">${r.status === 'resolved' ? 'Resolved' : 'Dismissed'} · closed</span>`}
      </div>
    </article>`;
  }

  // ------------------------------------------------------------------ audit
  const AUDIT_KIND = (action) => action.startsWith('admin.') ? 'access'
    : /^(account|report|device|invite)\./.test(action) ? 'moderation' : 'system';
  const AUDIT_LABEL = { access: 'Access', moderation: 'Moderation', system: 'System' };
  function auditDetails(e) {
    const parts = [];
    if (e.target) parts.push(`Target <span class="mono">${esc(shortId(e.target))}</span>`);
    Object.entries(e.details || {}).forEach(([k, v]) => {
      parts.push(`${esc(k.replace(/_/g, ' '))}: <span class="mono">${esc(v)}</span>`);
    });
    return parts.join(' · ') || 'No further detail';
  }
  function auditRow(e) {
    const kind = AUDIT_KIND(e.action);
    return `<div class="audit-row" data-kind="${kind}">
      <span class="au-ico ${kind}">${icon(kind === 'access' ? 'sign-in' : kind === 'moderation' ? 'shield-check' : 'gear-six')}</span>
      <div class="au-main">
        <div class="au-top"><code>${esc(e.action)}</code><span class="pill ${kind === 'access' ? 'info' : kind === 'moderation' ? 'warn' : 'mute'}">${AUDIT_LABEL[kind]}</span></div>
        <div class="au-sub">${auditDetails(e)}</div>
      </div>
      <time class="au-time mono">${esc(e.at)}</time>
    </div>`;
  }

  // ---------------------------------------------------------------- invites
  function inviteCard(v) {
    const open = v.status === 'open';
    const usedBy = v.redeemedBy ? accountById(v.redeemedBy) : null;
    return `<article class="inv-card" data-invite="${esc(v.id)}" data-status="${esc(v.status)}">
      <span class="iv-ico">${icon('ticket')}</span>
      <div class="iv-body">
        <div class="iv-top"><span class="iv-id mono">${esc(shortId(v.id))}</span>${statusPill(v.status)}${v.fresh ? '<span class="pill info">New</span>' : ''}</div>
        <div class="iv-sub">Created ${esc(v.createdAt)} · ${open ? `expires ${esc(v.expiresAt)}` : `expired ${esc(v.expiresAt)}`} · issued by ${esc(v.issuer)}</div>
        ${usedBy ? `<div class="iv-sub">Used by ${esc(accountTitle(usedBy))} · <span class="mono">${esc(shortId(usedBy.id))}</span></div>` : ''}
      </div>
      ${open ? `<button class="btn secondary sm" data-cancel-invite="${esc(v.id)}">Cancel</button>` : `<span class="iv-end">${esc(capitalize(v.status))}</span>`}
    </article>`;
  }

  // ------------------------------------------------------------ settings kit
  function settingRow({ title, sub = '', end = '', ic = '', cls = '', attrs = '' }) {
    return `<div class="set-row ${cls}" ${attrs}>
      ${ic ? `<span class="set-ico">${icon(ic)}</span>` : ''}
      <div class="set-body"><div class="set-title">${title}</div>${sub ? `<div class="set-sub">${sub}</div>` : ''}</div>
      ${end ? `<div class="set-end">${end}</div>` : ''}
    </div>`;
  }
  function switchRow({ title, sub = '', on, attrs = '', ic = '' }) {
    return settingRow({
      title, sub, ic, cls: 'switch-row', attrs: `${attrs} data-switch`,
      end: `<span class="switch ${on ? 'on' : ''}" role="switch" aria-checked="${!!on}"></span>`,
    });
  }

  function skeletonRows(n = 6) {
    return `<div class="pcard" aria-hidden="true"><div class="skel" style="padding:0">
      ${Array.from({ length: n }, () => `<div class="sk-row" style="min-height:64px;border-bottom:1px solid var(--line-2);padding:0 14px">
        <span class="sk sk-av" style="width:32px;height:32px;border-radius:9px"></span>
        <span class="sk-lines"><span class="sk sk-l1"></span><span class="sk sk-l2 short"></span></span>
        <span class="sk sk-meta" style="margin-top:0"></span>
      </div>`).join('')}</div></div>`;
  }

  function empty({ icon: ic, title, text, action = '' }) {
    return `<div class="empty"><div class="em-art">${icon(ic)}</div><h3>${title}</h3>${text ? `<p>${esc(text)}</p>` : ''}${action}</div>`;
  }

  return {
    esc, icon, ibtn, accountById, shortId, accountTitle, accountHandle, firstName, day, capitalize,
    initials, colorIndexFor, avatar, btn, copyBtn, statusPill, tag, pill, stateDot, platform,
    pageHead, page, searchbar, opsTabs, fchips, section, banner, kv, prop, num, metric, healthRow,
    userCard, deviceRow, openReportsPill, reportCard, auditRow, AUDIT_KIND, inviteCard,
    settingRow, switchRow, skeletonRows, empty,
  };
})();
