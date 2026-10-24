/* Ops · Reports: the moderation queue. */
(() => {
  const { esc } = UI;

  const openCount = () => DATA.reports.filter((r) => r.status === 'open').length;

  function list(params, entry) {
    const state = params.state || '';
    const filter = entry.state.filter || params.filter || 'open';
    entry.state.filter = filter;
    const open = DATA.reports.filter((r) => r.status === 'open').length;
    const resolved = DATA.reports.filter((r) => r.status === 'resolved').length;
    const dismissed = DATA.reports.filter((r) => r.status === 'dismissed').length;
    const tabs = UI.opsTabs('reports', open);
    const actions = UI.btn('Refresh', 'secondary', { icon: 'arrows-clockwise', sm: true, attrs: 'data-refresh' });

    if (state === 'loading') {
      return UI.page({
        eyebrow: 'Ops & Logs', title: 'User Reports & Moderation',
        sub: 'Reports opened by people who were messaged.',
        actions: UI.btn('Refresh', 'secondary', { icon: 'arrows-clockwise', sm: true, disabled: true }),
        body: `${UI.opsTabs('reports', open)}<div class="toolbar">${UI.fchips([['open', 'Open', open], ['resolved', 'Resolved', resolved], ['dismissed', 'Dismissed', dismissed], ['all', 'All', DATA.reports.length]], 'open')}</div>${Kit.skeletonRows(3)}<div class="page-loading" style="padding-top:16px"><span>Loading reports…</span></div>`,
      });
    }
    if (state === 'error') {
      return UI.page({
        eyebrow: 'Ops & Logs', title: 'User Reports & Moderation',
        sub: 'Reports opened by people who were messaged.', actions,
        body: `${tabs}${Kit.loadFailed('Reports could not be loaded.', 'The server answered, but the moderation queue did not come back. Nothing has changed for the people waiting.')}`,
      });
    }

    if (state === 'empty') {
      return UI.page({
        eyebrow: 'Ops & Logs', title: 'User Reports & Moderation',
        sub: 'No reports have been opened.', actions,
        body: `${tabs}<div class="pcard">${Kit.empty({ icon: 'shield-check', title: 'No reports right now.', text: 'When someone reports a person, it appears here with what they wrote.' })}</div>`,
      });
    }

    const shown = DATA.reports.filter((r) => filter === 'all' || r.status === filter);
    const cards = shown.length
      ? shown.map(UI.reportCard).join('')
      : `<div class="list-empty">${UI.icon('flag')}<div><strong>Nothing in this state.</strong><span>Try another filter above.</span></div></div>`;

    return UI.page({
      eyebrow: 'Ops & Logs', title: 'User Reports & Moderation',
      sub: `${open} open · ${resolved} resolved · ${dismissed} dismissed. A decision is recorded in the audit trail.`,
      actions,
      body: `${tabs}
        <div class="toolbar">${UI.fchips([['open', 'Open', open], ['resolved', 'Resolved', resolved], ['dismissed', 'Dismissed', dismissed], ['all', 'All', DATA.reports.length]], filter)}<span class="spacer"></span><span class="tool-note">Newest first</span></div>
        <div class="report-list">${cards}</div>
        <div class="list-foot"><span>${shown.length} report${shown.length === 1 ? '' : 's'} shown</span><span>Updated just now</span></div>`,
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
        App.snack('Reports refreshed');
      }, 650);
    });
    el.addEventListener('click', (e) => {
      const resolve = e.target.closest('[data-resolve]');
      if (resolve) {
        const r = DATA.reports.find((x) => x.id === resolve.dataset.resolve);
        if (r) { r.status = 'resolved'; App.snack(`${r.id} resolved · audit trail updated`); entry.rerender(); }
        return;
      }
      const dismiss = e.target.closest('[data-dismiss]');
      if (dismiss) {
        const r = DATA.reports.find((x) => x.id === dismiss.dataset.dismiss);
        if (r) { r.status = 'dismissed'; App.snack(`${r.id} dismissed · audit trail updated`); entry.rerender(); }
        return;
      }
      const account = e.target.closest('[data-open-account]');
      if (account) App.push('account', { id: account.dataset.openAccount });
    });
  }

  App.register({
    id: 'ops_reports', title: 'User Reports & Moderation', group: 'Ops & Logs', nav: 'ops', order: 30,
    interactions: [
      ['tap', 'Open / Resolved / Dismissed / All', 'Narrows the queue; each chip shows how many reports are in that state.'],
      ['tap', 'Resolve', 'Closes the report as resolved and writes the decision to the audit trail.'],
      ['tap', 'Dismiss', 'Closes the report as not a platform matter and writes that to the audit trail.'],
      ['tap', 'Open account (or the account ID)', 'Opens the reported account; on a wide window it opens its page from the list.'],
      ['tap', 'Refresh', 'Asks the server again and shows the loading state while it waits.'],
      ['auto', 'Reports tab badge', 'Shows how many reports are open, on every Ops screen.'],
    ],
    entries: [
      { label: 'Reports' },
      { label: 'Reports · resolved', params: { filter: 'resolved' } },
      { label: 'Reports · loading', params: { state: 'loading' } },
      { label: 'Reports · empty', params: { state: 'empty' } },
      { label: 'Reports · error', params: { state: 'error' } },
    ],
    render: list,
    mount: wire,
  });
})();
