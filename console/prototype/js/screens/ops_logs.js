/* Ops · Logs: the live server console. */
(() => {
  const { esc, icon } = UI;

  const lineText = (l) => `${l.at} ${l.level.toUpperCase()} ${l.event} ${l.msg}`;

  function lines(list) {
    return list.map((l) => `<div class="log-line lvl-${esc(l.level)}">
      <span class="lg-time">${esc(l.at)}</span>
      <span class="lg-level">${esc(l.level)}</span>
      <span class="lg-event">${esc(l.event)}</span>
      <span class="lg-msg">${esc(l.msg)}</span>
    </div>`).join('');
  }

  function list(params, entry) {
    const state = params.state || '';
    const paused = entry.state.paused != null ? entry.state.paused : (params.paused || false);
    const q = entry.state.query != null ? entry.state.query : (params.q || '');
    entry.state.query = q;
    const open = DATA.reports.filter((r) => r.status === 'open').length;
    const tabs = UI.opsTabs('logs', open);
    const shown = DATA.logs.filter((l) => !q || `${l.level} ${l.event} ${l.msg}`.toLowerCase().includes(q.toLowerCase()));
    const streamPill = paused ? UI.statusPill('paused') : UI.statusPill('live');

    const header = UI.btn('Refresh', 'secondary', { icon: 'arrows-clockwise', sm: true, attrs: 'data-refresh' });

    if (state === 'loading') {
      return UI.page({
        eyebrow: 'Ops & Logs', title: 'Live Server Console',
        sub: 'Structured lines from the server process, newest at the bottom.',
        actions: header,
        body: `${tabs}<div class="pcard"><div class="log-bar">${UI.statusPill('live')}<span class="spacer"></span>${UI.searchbar('logFilter', 'Filter lines')}</div><div class="log-scroll" style="padding:14px">${Array.from({ length: 10 }, (_, i) => `<div class="sk" style="height:11px;width:${55 + (i * 37) % 40}%;margin:9px 0"></div>`).join('')}</div></div><div class="page-loading" style="padding-top:10px"><span>Loading log lines…</span></div>`,
      });
    }
    if (state === 'error') {
      return UI.page({
        eyebrow: 'Ops & Logs', title: 'Live Server Console',
        sub: 'Structured lines from the server process, newest at the bottom.', actions: header,
        body: `${tabs}${Kit.loadFailed('The log stream could not be reached.', 'The server is answering admin requests but the log tail did not open. The lines are still being written; try again.')}`,
      });
    }
    if (state === 'empty') {
      return UI.page({
        eyebrow: 'Ops & Logs', title: 'Live Server Console',
        sub: 'No lines yet.', actions: header,
        body: `${tabs}<div class="pcard">${Kit.empty({ icon: 'terminal-window', title: 'The console is quiet.', text: 'Lines appear here as the server writes them. Start a request or wait for the next background job.' })}</div>`,
      });
    }

    return UI.page({
      eyebrow: 'Ops & Logs', title: 'Live Server Console',
      sub: 'Structured lines from the server process, newest at the bottom. Secrets, keys and full phone numbers never reach this stream.',
      actions: header,
      body: `${tabs}
        <div class="pcard log-panel">
          <div class="log-bar">
            ${streamPill}
            <span class="spacer"></span>
            <button class="btn secondary sm" data-reload>${icon('arrows-clockwise')}Reload</button>
            <button class="btn secondary sm" data-pause>${icon(paused ? 'play' : 'pause')}${paused ? 'Resume' : 'Pause'}</button>
            <button class="btn secondary sm" data-copy-logs>${icon('copy')}Copy</button>
          </div>
          <div class="log-filter">${UI.searchbar('logFilter', 'Filter by level, event or text', q)}<span class="log-count">${shown.length} of ${DATA.logs.length} lines</span></div>
          <div class="log-scroll" id="logScroll" tabindex="0" aria-label="Server log lines">
            ${shown.length ? lines(shown) : `<div class="list-empty">${icon('funnel')}<div><strong>No lines match.</strong><span>Clear the filter to see the whole tail.</span></div></div>`}
          </div>
          <div class="pcard-foot">${icon('info')} ${paused ? 'The stream is paused; Reload fetches the latest lines.' : 'While live, the console asks for new lines every few seconds and follows the bottom.'}</div>
        </div>`,
    });
  }

  function wire(el, params, entry) {
    const scroller = el.querySelector('#logScroll');
    if (scroller && !entry.state.paused) scroller.scrollTop = scroller.scrollHeight;
    const input = el.querySelector('#logFilter');
    if (input) {
      input.value = entry.state.query || '';
      input.addEventListener('input', () => {
        entry.state.query = input.value;
        entry.rerender();
        const again = document.querySelector('#stack .page:last-child #logFilter');
        if (again) { again.focus(); again.setSelectionRange(again.value.length, again.value.length); }
      });
    }
    el.querySelector('[data-pause]')?.addEventListener('click', () => {
      entry.state.paused = !entry.state.paused;
      App.snack(entry.state.paused ? 'Stream paused' : 'Stream resumed');
      entry.rerender();
    });
    el.querySelector('[data-reload]')?.addEventListener('click', () => {
      if (entry.state.busy) return;
      entry.state.busy = true;
      entry.params = { ...entry.params, state: 'loading' };
      entry.rerender();
      setTimeout(() => {
        entry.state.busy = false;
        entry.params = { ...entry.params, state: '' };
        entry.rerender();
        App.snack('Log lines refreshed');
      }, 650);
    });
    el.querySelector('[data-copy-logs]')?.addEventListener('click', () => {
      const visible = DATA.logs.filter((l) => !entry.state.query || `${l.level} ${l.event} ${l.msg}`.toLowerCase().includes(entry.state.query.toLowerCase()));
      Kit.copy(visible.map(lineText).join('\n'), `Copied ${visible.length} log lines`);
    });
  }

  App.register({
    id: 'ops_logs', title: 'Live Server Console', group: 'Ops & Logs', nav: 'ops', order: 32,
    interactions: [
      ['tap', 'Pause / Resume', 'Stops following new lines without leaving the page; the pill changes to Stream paused.'],
      ['tap', 'Reload', 'Fetches the tail again and shows the loading state while it waits.'],
      ['tap', 'Copy', 'Copies the visible lines as text, one per line, and says how many.'],
      ['type', 'Filter by level, event or text', 'Narrows the lines in place; the count shows how many of the tail match.'],
      ['auto', 'The live tail', 'Follows the newest line while streaming; pause to read without the list moving.'],
      ['auto', 'The polling note', 'Says plainly that the console asks for new lines every few seconds rather than holding a socket.'],
    ],
    entries: [
      { label: 'Logs' },
      { label: 'Logs · paused', params: { paused: true } },
      { label: 'Logs · warnings', params: { q: 'warn' } },
      { label: 'Logs · loading', params: { state: 'loading' } },
      { label: 'Logs · empty', params: { state: 'empty' } },
      { label: 'Logs · error', params: { state: 'error' } },
    ],
    render: list,
    mount: wire,
  });
})();
