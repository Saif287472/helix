/*
  Overview, in direction A. One line of status in the strip, four facts in the
  signal strip, then four panels: what the node answered, what it can reach,
  what the last operator did, and what is waiting.

  Everything on this page comes from two calls the console already makes:
  GET /v1/ops/metrics and GET /v1/admin/config. Counts are this node's
  lifetime and start again at a restart, so nothing here is a trend.
*/
(() => {
  const { esc, icon } = UI;

  /* A node that has just started answers with zeros. The board has to say that
     plainly instead of showing empty bars and a division by nothing. */
  const ZERO = (startedAt) => ({
    requests: 0, serverErrors: 0, clientErrors: 0, serverErrorShare: 0,
    websocketsOpen: 0, websocketConnections: 0, mailboxBacklog: 0, deadJobs: 0,
    crashReports: 0, jobsFinished: { ok: 0, retry: 0, dead: 0 }, startedAt,
  });

  const share = (m, n) => (m.requests ? ((n / m.requests) * 100).toFixed(1) : '0.0');

  function signals(m) {
    const cell = (k, v, sub, tone = '') => `<div class="cr-signal"><div class="k">${k}</div>
      <div class="v"><b class="${tone}">${v}</b><span>${sub}</span></div></div>`;
    return `<div class="cr-signals">
      ${cell('Devices online', UI.num(m.websocketsOpen), 'live sockets')}
      ${cell('Undelivered', UI.num(m.mailboxBacklog), 'in mailboxes')}
      ${cell('Failed jobs', UI.num(m.deadJobs), 'out of retries', m.deadJobs ? 'warn' : '')}
      ${cell('Crash reports', UI.num(m.crashReports), 'last 24 h')}
    </div>`;
  }

  function requestsPanel(m) {
    const okShare = m.requests ? (100 - m.serverErrorShare * 100 - (m.clientErrors / m.requests) * 100).toFixed(1) : '0.0';
    const jobs = m.jobsFinished;
    const jobTotal = jobs.ok + jobs.retry + jobs.dead;
    return `<section class="cr-panel">
      <header><h2>Requests</h2><span class="aside">this node · since ${esc(m.startedAt.slice(11))}</span></header>
      <div class="cr-lead"><b>${UI.num(m.requests)}</b><span>answered</span></div>
      ${m.requests ? `<div class="cr-bar" role="img" aria-label="${okShare} percent succeeded, ${share(m, m.clientErrors)} percent client errors, ${share(m, m.serverErrors)} percent server errors">
        <i class="ok" style="width:${okShare}%"></i><i class="client" style="width:${share(m, m.clientErrors)}%"></i><i class="server" style="width:${share(m, m.serverErrors)}%"></i>
      </div>
      <div class="cr-legend">
        <span><i style="background:var(--success)"></i>2xx <b>${okShare}%</b></span>
        <span><i style="background:var(--warning)"></i>4xx <b>${share(m, m.clientErrors)}%</b></span>
        <span><i style="background:var(--danger)"></i>5xx <b>${share(m, m.serverErrors)}%</b></span>
        <span class="muted">${UI.num(m.serverErrors)} server errors · ${UI.num(m.websocketConnections)} connections open now</span>
      </div>
      <div class="cr-jobs">
        <div class="cr-jobshead"><span>Background jobs</span><span>${UI.num(jobTotal)} finished</span></div>
        <div class="cr-bar"><i class="ok" style="width:${(jobs.ok / jobTotal * 100).toFixed(2)}%"></i><i class="client" style="width:1%"></i><i class="server" style="width:1%"></i></div>
        <div class="cr-legend"><span><i style="background:var(--success)"></i>${UI.num(jobs.ok)} ok</span><span><i style="background:var(--warning)"></i>${jobs.retry} retried</span><span><i style="background:var(--danger)"></i>${jobs.dead} dead</span></div>
      </div>` : `<div class="cr-quiet">${icon('hourglass-medium')}<span>Nothing has been answered since the node started. The bars appear with the first request.</span></div>`}
      <div class="cr-note">One axis: the share by outcome. Counts start again when the node restarts.</div>
    </section>`;
  }

  function healthPanel(degraded) {
    const g = DATA.integrations;
    const row = (name, sub, ok, word) => `<div class="cr-row"><div style="min-width:0"><div class="name">${name}</div><div class="sub">${sub}</div></div>
      <span class="word"><span class="dot ${ok ? 'ok' : 'bad'}"></span>${word}</span></div>`;
    const setup = (label, it, sub) => row(label, sub, it.configured, it.configured ? 'Set up' : 'Not set up');
    return `<section class="cr-panel">
      <header><h2>Service health</h2><span class="aside">what this node can reach</span></header>
      <div class="cr-list">
        ${row('Database', 'PostgreSQL 17 · primary', !degraded, degraded ? 'Failing' : 'Operational')}
        ${row('Object storage', 'local · attachments and backups', DATA.health.storage, DATA.health.storage ? 'Operational' : 'Failing')}
        ${setup('FCM push', g.push, `provider ${g.push.provider}`)}
        ${setup('SMS gateway', g.sms, `provider ${g.sms.provider}`)}
        ${row('TURN relay', `${g.turn.count} addresses · calls behind routers`, g.turn.configured, g.turn.configured ? 'Set up' : 'Not set up')}
      </div>
      <div class="cr-note">A set-up line only says the key is present. It cannot say the provider accepts it.</div>
    </section>`;
  }

  function auditPanel(quiet) {
    const det = (a) => [a.target ? UI.shortId(a.target) : '',
      ...Object.entries(a.details || {}).map(([k, v]) => `${k}: ${v}`)].filter(Boolean).join(' · ');
    const rows = quiet ? '' : DATA.audit.slice(0, 4).map((a) => `<div class="cr-row">
      <time class="t" datetime="${esc(a.at)}" title="${esc(a.at)}">${Kit.rel(a.at, true)}</time>
      <span class="act">${esc(a.action)}</span>
      <span class="det">${esc(det(a))}</span>
      <span class="who">you</span></div>`).join('');
    return `<section class="cr-panel">
      <header><h2>Recent admin actions</h2><a class="aside" href="#ops_audit">Audit trail →</a></header>
      <div class="cr-list">${rows || `<div class="cr-quiet">${icon('scroll')}<span>No admin action has been taken on this node yet.</span></div>`}</div>
    </section>`;
  }

  function waitingPanel(m, maintenance, quiet) {
    const open = quiet ? 0 : DATA.reports.filter((r) => r.status === 'open').length;
    const c = DATA.config;
    const need = (n, what, sub, href, act) => `<div class="cr-need"><b>${n}</b><div class="what">${what}<span>${sub}</span></div>
      ${href ? `<a href="${href}">${act} →</a>` : '<span class="none">Nothing</span>'}</div>`;
    return `<section class="cr-panel">
      <header><h2>Waiting for you</h2></header>
      ${need(open, 'Open reports', 'newest first in Ops', open ? '#ops_reports' : '', 'Review')}
      ${need(m.deadJobs, 'Failed background jobs', 'out of retries', m.deadJobs ? '#ops_config' : '', 'Purge')}
      <div class="cr-facts">
        <div><b>${esc(c.nodeId)}</b> · v${esc(c.version)} · ${c.registration === 'phone' ? 'phone sign-up' : 'invite sign-up'}</div>
        <div>Federation ${c.federation ? 'on' : 'off'} · Maintenance ${maintenance ? 'on' : 'off'}</div>
        <div>Session ends ${esc(c.signedInUntil)}</div>
      </div>
    </section>`;
  }

  function loading() {
    const sig = '<div class="cr-signal"><div class="k"><span class="sk" style="width:78px;height:9px"></span></div>' +
      '<div class="v"><span class="sk" style="width:46px;height:22px"></span></div></div>';
    const panel = (title) => `<section class="cr-panel">
      <header><h2>${title}</h2><span class="aside"><span class="sk" style="width:88px;height:9px"></span></span></header>
      <div class="sk-table">${Kit.skeletonTable(5, 3)}</div></section>`;
    return `<div class="cr-signals">${sig.repeat(4)}</div>
      <div class="cr-grid">
        ${panel('Requests')}${panel('Service health')}${panel('Recent admin actions')}${panel('Waiting for you')}
      </div>`;
  }

  function render(params, entry) {
    if (entry && entry.state.busy) return `<div class="canvas">${loading()}</div>`;
    const s = params.state || 'ok';
    if (s === 'offline') {
      return `<div class="canvas"><div>${Kit.offline({ at: '11:41:58' })}<p class="canvas-why">The strip keeps the last node you could reach. Nothing on this page is current.</p></div></div>`;
    }
    if (s === 'denied') {
      return `<div class="canvas"><div>${Kit.noPermission()}<p class="canvas-why">An action you started before the session ended may already have happened. Check the audit trail after signing in again.</p></div></div>`;
    }
    if (s === 'loading') return `<div class="canvas">${loading()}</div>`;
    const degraded = s === 'degraded';
    const quiet = s === 'quiet';
    const maintenance = DATA.config.maintenance || s === 'maintenance';
    const m = quiet ? ZERO(DATA.metrics.startedAt) : DATA.metrics;
    const flag = degraded
      ? `<div class="cr-flag">${icon('database')}<span>The readiness check failed on its last run. New work can fail until the database answers again.</span></div>`
      : maintenance
        ? `<div class="cr-flag">${icon('traffic-cone')}<span>Maintenance is on. New sign-ins are refused; people already signed in keep working normally.</span></div>`
        : '';
    return `<div class="canvas">
      ${flag}
      ${signals(m)}
      <div class="cr-grid">
        ${requestsPanel(m)}
        ${healthPanel(degraded)}
        ${auditPanel(quiet)}
        ${waitingPanel(m, maintenance, quiet)}
      </div>
    </div>
    <footer class="canvas-foot">
      <span class="kbd-hint"><span><span class="key">r</span>Check again</span><span><span class="key">?</span>Shortcuts</span></span>
      <span class="right">Counts are this node only · 22 Oct 2026, 11:42</span>
    </footer>`;
  }

  App.register({
    id: 'overview', title: 'Overview', strip: 'Overview', group: 'Overview', nav: 'overview', order: 10,
    ready: 'ok',
    interactions: [
      ['tap', 'Refresh in the status strip', 'Asks GET /v1/ops/metrics and GET /v1/admin/config again; the page shows its skeleton while it waits and the strip stamps the new time.'],
      ['tap', 'Audit trail →', 'Opens Ops → Audit at the same list.'],
      ['tap', 'Review → / Purge →', 'Opens the open reports, or the configuration panel where a purge is confirmed.'],
      ['hover', 'A relative time', 'The exact timestamp, from the datetime attribute.'],
      ['auto', 'Signal strip', 'Four counts, each with what it means; failed jobs turn amber when they are not zero.'],
      ['auto', 'Maintenance mode', 'When it is on, the status strip carries the warning before anything else on the page.'],
      ['auto', 'A failing readiness check', 'The database line turns red and the strip stops saying Ready.'],
      ['auto', 'A node with nothing on it', 'Every count reads 0, the bars are replaced by one line saying the node has answered nothing yet, and the audit panel says no action has been taken.'],
      ['key', 'r / ?', 'r checks again, the same as Refresh; ? opens the keyboard sheet. This page has no rows to move through, so it does not advertise j and k.'],
    ],
    entries: [
      { label: 'Overview' },
      { key: 'overview-loading', label: 'Overview · loading', params: { state: 'loading' } },
      { key: 'overview-degraded', label: 'Overview · not ready', params: { state: 'degraded' } },
      { key: 'overview-offline', label: 'Overview · node unreachable', params: { state: 'offline' } },
      { key: 'overview-denied', label: 'Overview · session ended', params: { state: 'denied' } },
      { key: 'overview-maintenance', label: 'Overview · maintenance on', params: { state: 'maintenance' } },
      { key: 'overview-quiet', label: 'Overview · a node with nothing on it', params: { state: 'quiet' } },
      { key: 'overview-long', label: 'Overview · long data', params: { state: 'ok', text: '2x' } },
    ],
    render(params, entry) {
      const html = render(params, entry);
      if (params.text === '2x') return `<div class="text-2x">${html}</div>`;
      return html;
    },
    mount(el, params, entry) {
      el.querySelector('[data-retry]')?.addEventListener('click', () => {
        entry.state.busy = true;
        entry.rerender();
        setTimeout(() => { entry.state.busy = false; entry.rerender(); }, 500);
      });
    },
  });
})();
