/* Ops · Audit: every administrative action, newest first. */
(() => {
  const kindOf = UI.AUDIT_KIND;
  const count = (k) => DATA.audit.filter((e) => kindOf(e.action) === k).length;

  function list(params, entry) {
    const state = params.state || '';
    const filter = entry.state.filter || params.filter || 'all';
    entry.state.filter = filter;
    const tabs = UI.opsTabs('audit', DATA.reports.filter((r) => r.status === 'open').length);
    const actions = UI.btn('Refresh', 'secondary', { icon: 'arrows-clockwise', sm: true, attrs: 'data-refresh' });
    const chips = UI.fchips([
      ['all', 'All events', DATA.audit.length],
      ['access', 'Access'], ['moderation', 'Moderation'], ['system', 'System'],
    ], filter);

    if (state === 'loading') {
      return UI.page({
        eyebrow: 'Ops & Logs', title: 'Administrative Audit Trail',
        sub: 'Every administrative action on this server, newest first.',
        actions: UI.btn('Refresh', 'secondary', { icon: 'arrows-clockwise', sm: true, disabled: true }),
        body: `${tabs}${Kit.skeletonRows(6)}<div class="page-loading" style="padding-top:16px"><span>Loading the audit trail…</span></div>`,
      });
    }
    if (state === 'error') {
      return UI.page({
        eyebrow: 'Ops & Logs', title: 'Administrative Audit Trail',
        sub: 'Every administrative action on this server, newest first.', actions,
        body: `${tabs}${Kit.loadFailed('The audit trail could not be loaded.', 'The server answered, but the entries did not come back. No action is lost — this is only the read.')}`,
      });
    }
    if (state === 'empty') {
      return UI.page({
        eyebrow: 'Ops & Logs', title: 'Administrative Audit Trail',
        sub: 'No administrative actions yet.', actions,
        body: `${tabs}<div class="pcard">${Kit.empty({ icon: 'scroll', title: 'Nothing has been recorded yet.', text: 'Sign-ins, moderation and configuration changes appear here as they happen.' })}</div>`,
      });
    }

    const shown = DATA.audit.filter((e) => filter === 'all' || kindOf(e.action) === filter);
    const rows = shown.length
      ? shown.map(UI.auditRow).join('')
      : `<div class="list-empty">${UI.icon('scroll')}<div><strong>No events of this kind.</strong><span>Try another filter above.</span></div></div>`;

    return UI.page({
      eyebrow: 'Ops & Logs', title: 'Administrative Audit Trail',
      sub: 'Every administrative action on this server, newest first. Targets are shown by their short ID.',
      actions,
      body: `${tabs}
        <div class="toolbar">${chips}<span class="spacer"></span><span class="tool-note">${DATA.audit.length} entries</span></div>
        <div class="pcard audit-list">${rows}</div>
        <div class="list-foot"><span>${shown.length} entr${shown.length === 1 ? 'y' : 'ies'} shown</span><span>Newest first</span></div>`,
    });
  }

  function wire(el, params, entry) {
    el.querySelectorAll('[data-filter]').forEach((b) => b.addEventListener('click', () => {
      entry.state.filter = b.dataset.filter;
      entry.rerender();
    }));
    el.querySelector('[data-refresh]')?.addEventListener('click', () => {
      if (entry.state.busy) return;
      entry.state.busy = true;
      entry.params = { ...entry.params, state: 'loading' };
      entry.rerender();
      setTimeout(() => {
        entry.state.busy = false;
        entry.params = { ...entry.params, state: '' };
        entry.rerender();
        App.snack('Audit trail refreshed');
      }, 650);
    });
  }

  App.register({
    id: 'ops_audit', title: 'Administrative Audit Trail', group: 'Ops & Logs', nav: 'ops', order: 31,
    interactions: [
      ['tap', 'All events / Access / Moderation / System', 'Filters by what the action touched; All events shows the full count.'],
      ['tap', 'Refresh', 'Asks the server again; the list keeps its filter while it loads.'],
      ['auto', 'Audit rows', 'Show the action code, a kind pill, the target’s short ID, its details and the exact time.'],
      ['auto', 'Order', 'Newest first, as the server returns it; entries are append-only.'],
    ],
    entries: [
      { label: 'Audit trail' },
      { label: 'Audit · access', params: { filter: 'access' } },
      { label: 'Audit · loading', params: { state: 'loading' } },
      { label: 'Audit · empty', params: { state: 'empty' } },
      { label: 'Audit · error', params: { state: 'error' } },
    ],
    render: list,
    mount: wire,
  });
})();
