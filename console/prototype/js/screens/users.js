/* Users & Devices: the list, the wide split and an account's page. */
(() => {
  const { esc, icon } = UI;

  const find = (id) => UI.accountById(id);
  const devicesOf = (a) => DATA.devices[a.id] || [];

  function matches(a, q, filter) {
    if (filter === 'active' && a.status !== 'active') return false;
    if (filter === 'suspended' && a.status !== 'suspended') return false;
    const s = q.trim().toLowerCase();
    if (!s) return true;
    return `${a.helixName || ''} ${a.displayName || ''} ${a.phone} ${a.last4 || ''}`.toLowerCase().includes(s);
  }

  function identityCard(a) {
    const det = DATA.accountDetails[a.id] || {};
    return `<div class="pcard">
      <div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">User identity & state</div><div class="pcard-sub">Everything the server knows about this account.</div></div>${UI.openReportsPill(a)}</div>
      <div class="prop-list">
        ${UI.prop('Account ID', `${esc(a.id)} ${UI.copyBtn(a.id, 'Copy account ID')}`)}
        ${UI.prop('Phone', esc(a.phone))}
        ${UI.prop('Helix name', esc(UI.accountHandle(a)))}
        ${UI.prop('State', UI.statusPill(a.status))}
        ${UI.prop('Last seen', a.lastSeenOn ? esc(UI.day(a.lastSeenOn)) : 'Never', { mono: false })}
        ${UI.prop('Joined', esc(UI.day(a.createdAt)), { mono: false })}
        ${UI.prop('Password', det.hasPassword ? 'Set' : 'Not set', { mono: false })}
        ${UI.prop('Open reports', a.openReports ? `${a.openReports}${UI.btn('View', 'ghost', { sm: true, attrs: 'data-go="ops_reports"', cls: 'prop-action' })}` : 'None', { mono: false })}
      </div>
    </div>`;
  }

  function devicesCard(a) {
    const list = devicesOf(a);
    const active = list.filter((d) => d.active);
    const rows = list.length
      ? list.map(UI.deviceRow).join('')
      : `<div class="mini-empty">${icon('device-mobile-slash')} <span>No devices are registered. The person can sign in with a new one.</span></div>`;
    return `<div class="pcard">
      <div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Devices</div><div class="pcard-sub">${active.length} active · ${list.length - active.length} revoked</div></div></div>
      <div class="device-list">${rows}</div>
      <div class="pcard-foot">${icon('info')} Revoking ends a device’s access at its next request. Messages already on it are not deleted.</div>
    </div>`;
  }

  function actionsCard(a) {
    return `<div class="pcard">
      <div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Administrative actions</div><div class="pcard-sub">Recovery and identity help for this person.</div></div></div>
      <div class="action-list">
        ${UI.settingRow({
          ic: 'key', title: 'Recovery code',
          sub: 'Create a one-time code that lets this person back into their account.',
          end: UI.btn('Create code', 'secondary', { sm: true, attrs: 'data-recovery' }),
        })}
        ${UI.settingRow({
          ic: 'identification-card', title: 'Copy user ID',
          sub: `<span class="mono">${esc(a.id)}</span>`,
          end: UI.copyBtn(a.id, 'Copy user ID'),
        })}
      </div>
    </div>`;
  }

  function dangerCard(a) {
    const suspended = a.status === 'suspended';
    return `<div class="pcard danger-zone">
      <div class="pcard-head"><div class="pcard-titles"><div class="pcard-title danger">Danger zone</div><div class="pcard-sub">These change whether this person can use Helix. Each one is written to the audit trail.</div></div></div>
      ${suspended
        ? UI.settingRow({
          ic: 'play-circle', title: 'Resume this account',
          sub: 'The person can sign in, send and receive again. Their devices are still registered.',
          end: UI.btn('Resume', 'secondary', { sm: true, attrs: 'data-resume' }),
          cls: 'danger-row',
        })
        : UI.settingRow({
          ic: 'pause-circle', title: 'Suspend this account',
          sub: 'The person cannot sign in, send or receive. Devices keep their keys.',
          end: UI.btn('Suspend', 'danger', { sm: true, attrs: 'data-suspend' }),
          cls: 'danger-row',
        })}
      ${UI.settingRow({
        ic: 'prohibit', title: 'Ban this account',
        sub: 'Ends every session at once and refuses sign-in until an admin lifts it.',
        end: UI.btn('Ban', 'danger', { sm: true, attrs: 'data-ban' }),
        cls: 'danger-row',
      })}
      ${UI.settingRow({
        ic: 'trash', title: 'Delete this account',
        sub: 'Removes the account and its devices. Messages already delivered are not recalled.',
        end: UI.btn('Delete', 'danger', { sm: true, attrs: 'data-delete' }),
        cls: 'danger-row',
      })}
    </div>`;
  }

  function hero(a) {
    return `<div class="acct-hero">
      ${UI.avatar(a, 52)}
      <div class="ah-body">
        <div class="ah-name">${esc(UI.accountTitle(a))} ${UI.statusPill(a.status)}</div>
        <div class="ah-sub">${esc(UI.accountHandle(a))} · ${esc(a.phone)}</div>
        <div class="ah-meta">Joined ${esc(UI.day(a.createdAt))} · <span class="mono">${esc(a.id)}</span></div>
      </div>
    </div>`;
  }

  function detailBody(a, { withHero = false } = {}) {
    return `<div class="detail-stack">
      ${withHero ? hero(a) : ''}
      ${identityCard(a)}
      ${devicesCard(a)}
      ${actionsCard(a)}
      ${dangerCard(a)}
    </div>`;
  }

  function banDialog(a, done) {
    App.dialog({
      title: `Ban ${UI.accountTitle(a)}?`,
      text: 'A ban ends every session at once and refuses sign-in until an admin lifts it. The account keeps its name and messages.',
      body: `${Kit.field({ id: 'banReason', label: 'Reason', multiline: true, rows: 2, hint: 'What happened? This is written to the audit trail.' })}${Kit.field({ id: 'banWord', label: 'Type BAN to confirm', hint: 'BAN' })}`,
      actions: [{ label: 'Cancel' }, {
        label: 'Ban account', kind: 'danger-solid',
        run: (panel) => {
          const reason = panel.querySelector('#banReason');
          const word = panel.querySelector('#banWord');
          if (!reason || reason.value.trim().length < 3) { reason?.focus(); return false; }
          if (!word || word.value.trim().toUpperCase() !== 'BAN') { word?.focus(); return false; }
          a.status = 'suspended';
          App.snack(`${UI.accountTitle(a)} banned`, null, { tone: '' });
          done();
        },
      }],
      onMount: (panel) => {
        const word = panel.querySelector('#banWord');
        const act = panel.querySelector('.dl-actions .btn:last-child');
        if (word && act) {
          act.disabled = true;
          word.addEventListener('input', () => { act.disabled = word.value.trim().toUpperCase() !== 'BAN'; });
        }
        panel.querySelector('#banReason')?.focus();
      },
    });
  }

  function wireDetail(root, a, done, { onGone } = {}) {
    root.querySelectorAll('[data-revoke]').forEach((b) => b.addEventListener('click', () => {
      const d = devicesOf(a).find((x) => x.id === b.dataset.revoke);
      if (!d) return;
      Kit.confirm(
        `Revoke ${d.name}?`,
        'The device can no longer send or receive. Messages already on it are not deleted, and the person’s other devices keep working.',
        'Revoke device',
        () => {
          d.active = false; d.revokedAt = '2026-10-22';
          a.activeDevices = devicesOf(a).filter((x) => x.active).length;
          App.snack(`${d.name} revoked`);
          done();
        },
      );
    }));
    root.querySelector('[data-recovery]')?.addEventListener('click', () => {
      Kit.confirm(
        `Create a recovery code for ${UI.accountTitle(a)}?`,
        'The code lets this person back into their account once. It is shown to you only now, and expires in 24 hours.',
        'Create code',
        () => Kit.codeOnce({
          code: 'RC-4M8P-2Q7K',
          title: 'Recovery code created',
          text: 'Give this code to the account holder through a channel you trust. It works once and is shown only now.',
          run: () => App.snack('Recovery code created'),
        }),
        'primary',
      );
    });
    root.querySelector('[data-suspend]')?.addEventListener('click', () => {
      Kit.reason({
        title: `Suspend ${UI.accountTitle(a)}?`,
        text: 'The person cannot sign in, send or receive while suspended. Their devices keep their keys, and you can resume the account at any time.',
        label: 'Suspend account',
        run: (reason) => {
          a.status = 'suspended';
          App.snack(`${UI.accountTitle(a)} suspended · ${reason}`);
          done();
        },
      });
    });
    root.querySelector('[data-resume]')?.addEventListener('click', () => {
      Kit.confirm(
        `Resume ${UI.accountTitle(a)}?`,
        'The person can sign in, send and receive again. Their registered devices are unchanged.',
        'Resume account',
        () => {
          a.status = 'active';
          App.snack(`${UI.accountTitle(a)} resumed`);
          done();
        },
        'primary',
      );
    });
    root.querySelector('[data-ban]')?.addEventListener('click', () => banDialog(a, done));
    root.querySelector('[data-delete]')?.addEventListener('click', () => {
      Kit.typed({
        title: `Delete ${UI.accountTitle(a)}?`,
        text: 'This removes the account and its devices from this server. Messages already delivered are not recalled, and the account cannot be restored.',
        word: 'DELETE',
        label: 'Delete account',
        run: () => {
          DATA.accounts.splice(DATA.accounts.indexOf(a), 1);
          delete DATA.devices[a.id];
          delete DATA.accountDetails[a.id];
          App.snack(`${UI.accountTitle(a)} deleted`);
          onGone ? onGone() : done();
        },
      });
    });
  }

  function listHtml(accounts, wide, sel, filter) {
    if (!accounts.length) {
      return `<div class="list-empty">${icon('users-three')}<div><strong>No one matches.</strong><span>Try a Helix name, a phone number or the last four digits.</span></div></div>`;
    }
    return accounts.map((a) => UI.userCard(a, { selected: wide && a.id === sel })).join('');
  }

  function counts() {
    return {
      all: DATA.accounts.length,
      active: DATA.accounts.filter((a) => a.status === 'active').length,
      suspended: DATA.accounts.filter((a) => a.status === 'suspended').length,
    };
  }

  function listScreen(params, entry) {
    const state = params.state || '';
    const wide = App.isWide();
    const c = counts();
    const headerActions = UI.btn('Refresh', 'secondary', { icon: 'arrows-clockwise', sm: true, attrs: 'data-refresh' });

    if (state === 'loading') {
      return UI.page({
        eyebrow: 'Users', title: 'Users & Devices',
        sub: 'Search people by Helix name or the last four digits of their phone number.',
        actions: UI.btn('Refresh', 'secondary', { icon: 'arrows-clockwise', sm: true, disabled: true }),
        body: `<div class="toolbar">${UI.searchbar('userSearch', 'Search by Helix name or last 4 digits')}${UI.fchips([['all', 'All users'], ['active', 'Active'], ['suspended', 'Suspended']], 'all')}</div>${Kit.skeletonRows(6)}<div class="page-loading" style="padding-top:16px"><span>Loading accounts…</span></div>`,
      });
    }
    if (state === 'error') {
      return UI.page({
        eyebrow: 'Users', title: 'Users & Devices',
        sub: 'Search people by Helix name or the last four digits of their phone number.',
        actions: headerActions,
        body: Kit.loadFailed('Accounts could not be loaded.', 'The server answered, but the account list did not come back. Nothing has changed for anyone.'),
      });
    }
    if (state === 'empty') {
      return UI.page({
        eyebrow: 'Users', title: 'Users & Devices',
        sub: 'No accounts yet.',
        actions: headerActions,
        body: `<div class="pcard">${Kit.empty({ icon: 'users-three', title: 'No one has signed up yet.', text: 'Accounts appear here as soon as people create one on this server.' })}</div>`,
      });
    }

    const filter = entry.state.filter || params.filter || 'all';
    entry.state.filter = filter;
    const query = entry.state.query || '';
    const visible = DATA.accounts.filter((a) => matches(a, query, filter));
    let sel = entry.state.sel || null;
    if (wide && !visible.some((a) => a.id === sel)) sel = visible[0]?.id || null;
    entry.state.sel = sel;
    const selected = sel ? find(sel) : null;

    const toolbar = `<div class="toolbar">
      ${UI.searchbar('userSearch', 'Search by Helix name or last 4 digits', query)}
      <span class="spacer"></span>
      ${UI.fchips([['all', 'All users', c.all], ['active', 'Active', c.active], ['suspended', 'Suspended', c.suspended]], filter)}
    </div>`;

    const body = wide
      ? `<div class="users-split">
          <div class="user-list-col">
            ${toolbar}
            <div class="user-list" id="userList">${listHtml(visible, true, sel, filter)}</div>
            <div class="list-foot"><span id="listCount">${visible.length} account${visible.length === 1 ? '' : 's'}</span><span>Select a person to see their devices.</span></div>
          </div>
          <div class="user-pane" id="userPane">${selected ? detailBody(selected, { withHero: true }) : `<div class="pane-empty">${icon('user-circle')}Choose someone from the list.</div>`}</div>
        </div>`
      : `${toolbar}<div class="user-list" id="userList">${listHtml(visible, false, null, filter)}</div><div class="list-foot"><span id="listCount">${visible.length} account${visible.length === 1 ? '' : 's'}</span><span>Updated just now</span></div>`;

    return UI.page({
      eyebrow: 'Users', title: 'Users & Devices',
      sub: `${c.all} accounts · ${c.active} active · ${c.suspended} suspended.`,
      actions: headerActions,
      body,
    });
  }

  function drawList(entry, el) {
    const list = el.querySelector('#userList');
    if (!list) return;
    const wide = App.isWide();
    const query = entry.state.query || '';
    const filter = entry.state.filter || 'all';
    const visible = DATA.accounts.filter((a) => matches(a, query, filter));
    if (wide && !visible.some((a) => a.id === entry.state.sel)) entry.state.sel = visible[0]?.id || null;
    list.innerHTML = listHtml(visible, wide, entry.state.sel, filter);
    const count = el.querySelector('#listCount');
    if (count) count.textContent = `${visible.length} account${visible.length === 1 ? '' : 's'}`;
    if (wide) {
      const pane = el.querySelector('#userPane');
      const a = find(entry.state.sel);
      if (pane) {
        pane.innerHTML = a ? detailBody(a, { withHero: true }) : `<div class="pane-empty">${icon('user-circle')}Choose someone from the list.</div>`;
        if (a) wireDetail(pane, a, () => entry.rerender());
      }
    }
  }

  function wireList(el, params, entry) {
    const input = el.querySelector('#userSearch');
    if (input) {
      input.value = entry.state.query || '';
      input.addEventListener('input', () => { entry.state.query = input.value; drawList(entry, el); });
    }
    el.querySelectorAll('[data-filter]').forEach((b) => b.addEventListener('click', () => {
      entry.state.filter = b.dataset.filter;
      entry.state.sel = null;
      entry.rerender();
    }));
    const list = el.querySelector('#userList');
    list?.addEventListener('click', (e) => {
      const card = e.target.closest('[data-user]');
      if (!card) return;
      const a = find(card.dataset.user);
      if (!a) return;
      if (App.isWide()) { entry.state.sel = a.id; entry.rerender(); }
      else App.push('account', { id: a.id });
    });
    list?.addEventListener('keydown', (e) => {
      const card = e.target.closest('[data-user]');
      if (!card || (e.key !== 'Enter' && e.key !== ' ')) return;
      e.preventDefault(); card.click();
    });
    const pane = el.querySelector('#userPane');
    const selected = entry.state.sel ? find(entry.state.sel) : null;
    if (pane && selected) wireDetail(pane, selected, () => entry.rerender());
    el.querySelector('[data-refresh]')?.addEventListener('click', () => {
      if (entry.state.busy) return;
      entry.state.busy = true;
      entry.params = { ...entry.params, state: 'loading' };
      entry.rerender();
      setTimeout(() => {
        entry.state.busy = false;
        entry.params = { ...entry.params, state: '' };
        entry.rerender();
        App.snack('Accounts refreshed');
      }, 650);
    });
  }

  App.register({
    id: 'users', title: 'Users & Devices', group: 'Users', nav: 'users', order: 20,
    interactions: [
      ['tap', 'A person in the list', 'Opens their account beside the list in a wide window, or as a page on a phone.'],
      ['type', 'The search field', 'Filters by Helix name, display name, phone number or the last four digits.'],
      ['tap', 'All users / Active / Suspended', 'Narrows the list; each chip shows how many it would show.'],
      ['tap', 'Refresh', 'Asks the server again and shows the list’s loading state while it waits.'],
      ['auto', 'Account cards', 'Show state, phone, Helix name, device count, join date and any open reports.'],
      ['auto', 'The wide split', 'Keeps the list while an account is open; the phone pushes the account page with a back arrow.'],
    ],
    entries: [
      { label: 'Users & Devices' },
      { label: 'Users · loading', params: { state: 'loading' } },
      { label: 'Users · empty', params: { state: 'empty' } },
      { label: 'Users · error', params: { state: 'error' } },
      { label: 'Users · suspended', params: { filter: 'suspended' } },
    ],
    render: listScreen,
    mount: wireList,
  });

  const accountInteractions = [
    ['tap', 'Revoke beside a device', 'Asks first, then ends that device’s access; the other devices keep working.'],
    ['tap', 'Create code (recovery)', 'Asks first, then shows a one-time recovery code in a dialog. It is never shown again.'],
    ['tap', 'Suspend / Resume', 'Suspending asks for a reason and blocks sign-in, sending and receiving; resuming lifts it.'],
    ['tap', 'Ban', 'Asks for a reason and the typed word BAN, then ends every session and refuses sign-in.'],
    ['tap', 'Delete', 'Asks for the typed word DELETE, then removes the account and its devices.'],
    ['tap', 'Copy account ID or Copy user ID', 'Copies the ID and says so in a toast.'],
    ['tap', 'View beside open reports', 'Opens User Reports & Moderation.'],
    ['tap', 'Back', 'Returns to Users & Devices.'],
  ];

  App.register({
    id: 'account', title: 'Account', group: 'Users', nav: 'users', order: 21,
    base: { screen: 'users' },
    interactions: accountInteractions,
    entries: [
      { label: 'Account · active', params: { id: 'acc_7N2K9Q' }, base: { screen: 'users' } },
      { label: 'Account · suspended', params: { id: 'acc_3M8Q1D' }, base: { screen: 'users' } },
      { label: 'Account · no devices', params: { id: 'acc_4K8N2M' }, base: { screen: 'users' } },
    ],
    render(params, entry) {
      const a = find(params.id) || DATA.accounts[0];
      if (!a) {
        return UI.page({
          eyebrow: 'Users', title: 'Account', back: true,
          body: `<div class="pcard">${Kit.empty({ icon: 'user', title: 'This account is gone.', text: 'It may have been deleted in another session.' })}</div>`,
        });
      }
      return UI.page({
        eyebrow: 'Users', title: esc(UI.accountTitle(a)),
        sub: `${esc(UI.accountHandle(a))} · ${esc(a.phone)}`,
        back: true,
        actions: UI.statusPill(a.status),
        body: detailBody(a),
      });
    },
    mount(el, params, entry) {
      const a = find(params.id) || DATA.accounts[0];
      if (!a) return;
      wireDetail(el, a, () => entry.rerender(), { onGone: () => App.pop() });
    },
  });
})();
