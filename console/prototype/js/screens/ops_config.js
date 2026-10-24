/* Ops · Config: the server's identity, safeguards and feature flags. */
(() => {
  const { esc, icon } = UI;

  const openCount = () => DATA.reports.filter((r) => r.status === 'open').length;

  function identity(c) {
    return `<div class="pcard">
      <div class="pcard-head">
        <div class="pcard-titles"><div class="pcard-title">Server node identity</div><div class="pcard-sub">What this server calls itself and where it lives.</div></div>
        ${UI.btn('Rename', 'secondary', { icon: 'pencil-simple', sm: true, attrs: 'data-rename' })}
      </div>
      <div class="node-identity">
        <span class="node-mark">${icon('hexagon')}</span>
        <div class="ni-body">
          <div class="ni-name">${esc(c.serverName)}</div>
          <div class="ni-sub">${esc(c.address)} · <span class="mono">${esc(c.nodeId)}</span></div>
        </div>
        ${UI.pill(`v${c.version}`, 'mute')}
      </div>
    </div>`;
  }

  function properties(c) {
    return `<div class="pcard">
      <div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Configuration properties</div><div class="pcard-sub">Read-only facts the server reports about itself.</div></div></div>
      <div class="prop-list">
        ${UI.prop('Public address', `${esc(c.address)} ${UI.copyBtn(c.address, 'Copy public address')}`)}
        ${UI.prop('Node ID', `${esc(c.nodeId)} ${UI.copyBtn(c.nodeId, 'Copy node ID')}`)}
        ${UI.prop('Version', esc(c.version))}
        ${UI.prop('Sign-up mode', 'Phone number', { mono: false })}
        ${UI.prop('Attachment limit', esc(c.maxAttachment), { mono: false })}
        ${UI.prop('Admin session ends', esc(c.signedInUntil))}
      </div>
    </div>`;
  }

  function worldwide(c) {
    return `<div class="pcard">
      <div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Worldwide mode & peer network</div><div class="pcard-sub">Off keeps this server on its own. On exchanges messages with other Helix servers.</div></div></div>
      ${UI.switchRow({
        title: 'Worldwide mode', on: c.federation,
        sub: c.federation ? `On · peer domain ${esc(c.federationDomain || 'not set')}` : 'Off · people can only reach accounts on this server.',
        attrs: 'data-federation', ic: 'globe-hemisphere-west',
      })}
      ${c.federation ? `<div class="pcard-foot">${icon('info')} Peers are discovered through the federation domain. Turning this off stops new cross-server messages; existing chats stay readable.</div>` : ''}
    </div>`;
  }

  function security(c) {
    return `<div class="pcard">
      <div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Local security & app lock</div><div class="pcard-sub">Things an operator can change on this console.</div></div></div>
      ${UI.switchRow({
        title: 'App lock', on: c.appLock,
        sub: c.appLock ? 'On · this device’s screen lock opens the console.' : 'Off · opening the console asks for the admin password.',
        attrs: 'data-applock', ic: 'lock-key',
      })}
      ${UI.settingRow({
        ic: 'password', title: 'Change the admin password',
        sub: 'Signs out every other admin session.',
        end: UI.btn('Change', 'secondary', { sm: true, attrs: 'data-change-password' }),
      })}
    </div>`;
  }

  function maintenance(c, maintenanceOn) {
    const dead = DATA.metrics.deadJobs;
    return `<div class="pcard">
      <div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Node maintenance & clean-up</div><div class="pcard-sub">Pause the server for work, or clear what has already expired.</div></div></div>
      ${UI.switchRow({
        title: 'Maintenance mode', on: maintenanceOn,
        sub: maintenanceOn ? 'On · new sign-ins are refused. People already signed in can keep using the server.' : 'Off · the server accepts sign-ins and new work.',
        attrs: 'data-maintenance', ic: 'wrench',
      })}
      ${UI.settingRow({
        ic: 'broom', title: 'Purge dead jobs and expired rows',
        sub: dead ? `${dead} failed background job${dead === 1 ? '' : 's'} and expired identity rows can be cleared.` : 'Nothing to clear right now.',
        end: UI.btn('Purge', 'secondary', { sm: true, attrs: 'data-purge', disabled: !dead }),
      })}
    </div>`;
  }

  const FLAGS = [
    ['crash_reporting_upload', 'Crash report uploads', 'Let the app upload crash reports. They contain diagnostics, never message content.', 'bug'],
    ['minimal_analytics', 'Minimal analytics', 'Count the smallest set of usage events. No content, no contacts.', 'chart-line-up'],
    ['group_calls', 'Group calls', 'Turn on group voice and video calls for everyone on this server.', 'phone-call'],
  ];
  function flags() {
    return `<div class="pcard">
      <div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Feature flags</div><div class="pcard-sub">Each flag applies to the whole server as soon as it is switched.</div></div></div>
      ${FLAGS.map(([key, title, sub, ic]) => UI.switchRow({
        title, sub, on: !!DATA.flags[key], attrs: `data-flag="${esc(key)}"`, ic,
      })).join('')}
    </div>`;
  }

  function session() {
    return `<div class="pcard">
      <div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Admin session</div><div class="pcard-sub">This console’s session on the server.</div></div></div>
      ${UI.settingRow({
        ic: 'clock', title: 'Signed in until',
        sub: DATA.config.signedInUntil,
        end: UI.btn('Sign out', 'danger', { sm: true, attrs: 'data-signout' }),
      })}
    </div>`;
  }

  function list(params, entry) {
    const state = params.state || '';
    const tabs = UI.opsTabs('config', openCount());
    if (state === 'loading') {
      return UI.page({
        eyebrow: 'Ops & Logs', title: 'Configuration',
        sub: 'This server’s identity, safeguards and feature flags.',
        body: `${tabs}<div class="settings-stack">${Array.from({ length: 3 }, () => `<div class="pcard"><div class="pcard-head"><div class="pcard-titles"><div class="sk" style="width:150px;height:12px"></div></div></div>${Kit.skeletonRows(4)}</div>`).join('')}</div><div class="page-loading" style="padding-top:10px"><span>Loading configuration…</span></div>`,
      });
    }
    if (state === 'error') {
      return UI.page({
        eyebrow: 'Ops & Logs', title: 'Configuration',
        sub: 'This server’s identity, safeguards and feature flags.',
        body: `${tabs}${Kit.loadFailed('The configuration could not be loaded.', 'The server answered, but its settings did not come back. Nothing has changed; try again in a moment.')}`,
      });
    }
    const c = DATA.config;
    const maintenanceOn = entry.state.maintenance != null
      ? entry.state.maintenance
      : (params.maintenance || c.maintenance);
    return UI.page({
      eyebrow: 'Ops & Logs', title: 'Configuration',
      sub: 'This server’s identity, safeguards and feature flags. Changes save at once and are written to the audit trail.',
      body: `${tabs}
        ${maintenanceOn ? UI.banner({ tone: 'warning', ic: 'wrench', title: 'Maintenance mode is on', text: 'New sign-ins are refused. Turn it off below when the work is done.', actions: UI.btn('Turn off', 'secondary', { sm: true, attrs: 'data-maintenance-off' }) }) : ''}
        <div class="settings-stack">
          ${identity(c)}
          ${properties(c)}
          ${worldwide(c)}
          ${security(c)}
          ${maintenance(c, maintenanceOn)}
          ${flags()}
          ${session()}
        </div>`,
    });
  }

  function wire(el, params, entry) {
    el.querySelector('[data-rename]')?.addEventListener('click', () => {
      Kit.rename(DATA.config.serverName, (name) => {
        DATA.config.serverName = name;
        DATA.server.name = name;
        const tb = document.querySelector('#tbServer');
        if (tb) tb.textContent = name;
        App.snack(`Server renamed to ${name}`);
        entry.rerender();
      });
    });
    el.querySelector('[data-federation]')?.addEventListener('toggle', (e) => {
      DATA.config.federation = e.detail;
      DATA.config.federationDomain = e.detail ? 'helix.agiletechbd.com' : null;
      App.snack(e.detail ? 'Worldwide mode on' : 'Worldwide mode off');
      entry.rerender();
    });
    el.querySelector('[data-applock]')?.addEventListener('toggle', (e) => {
      DATA.config.appLock = e.detail;
      App.snack(e.detail ? 'App lock on · this device’s screen lock now opens the console' : 'App lock off');
      entry.rerender();
    });
    const turnOff = () => {
      DATA.config.maintenance = false;
      entry.state.maintenance = false;
      App.snack('Maintenance mode off');
      entry.rerender();
    };
    el.querySelector('[data-maintenance-off]')?.addEventListener('click', turnOff);
    el.querySelector('[data-maintenance]')?.addEventListener('toggle', (e) => {
      if (!e.detail) { turnOff(); return; }
      entry.rerender();
      Kit.confirm(
        'Turn on maintenance mode?',
        'New sign-ins are refused until it is turned off. People already signed in can keep using the server.',
        'Turn on',
        () => {
          DATA.config.maintenance = true;
          entry.state.maintenance = true;
          App.snack('Maintenance mode on');
          entry.rerender();
        },
        'primary',
      );
    });
    el.querySelector('[data-change-password]')?.addEventListener('click', () => {
      Kit.changePassword(() => App.snack('Admin password changed · other sessions signed out'));
    });
    el.querySelector('[data-purge]')?.addEventListener('click', () => {
      const dead = DATA.metrics.deadJobs;
      Kit.confirm(
        'Purge dead jobs and expired rows?',
        `This removes ${dead} failed background job${dead === 1 ? '' : 's'} and expired identity rows. It cannot be undone, but it only touches data that has already expired.`,
        'Purge now',
        () => {
          DATA.metrics.deadJobs = 0;
          App.snack(`Purged ${dead} dead job${dead === 1 ? '' : 's'} and 14 expired identity rows`);
          entry.rerender();
        },
      );
    });
    el.querySelectorAll('[data-flag]').forEach((row) => {
      row.addEventListener('toggle', (e) => {
        const name = row.dataset.flag;
        DATA.flags[name] = e.detail;
        App.snack(`${FLAGS.find((f) => f[1] === row.querySelector('.set-title')?.textContent)?.[1] || name} ${e.detail ? 'on' : 'off'}`);
        entry.rerender();
      });
    });
  }

  App.register({
    id: 'ops_config', title: 'Configuration', group: 'Ops & Logs', nav: 'ops', order: 33,
    interactions: [
      ['tap', 'Rename', 'Opens a dialog with the server name; saving updates the console bar as well.'],
      ['tap', 'Worldwide mode', 'Switches federation on or off and shows or hides the peer domain.'],
      ['tap', 'App lock', 'Switches the device-lock gate for this console on or off; the choice stays on this device.'],
      ['tap', 'Change', 'Changes the admin password; every other admin session is signed out.'],
      ['tap', 'Maintenance mode', 'Turning it on asks first; while on, a banner says new sign-ins are refused.'],
      ['tap', 'Purge', 'Asks first, then clears dead jobs and expired rows and reports the counts.'],
      ['tap', 'A feature flag', 'Applies to the whole server at once and says so in a toast.'],
      ['tap', 'Sign out', 'Asks first, then closes the console session and returns to sign-in.'],
      ['tap', 'Copy beside the address or node ID', 'Copies it and says so in a toast.'],
      ['auto', 'Saving', 'Every switch saves immediately; there is no Save button to forget.'],
    ],
    entries: [
      { label: 'Configuration' },
      { label: 'Config · maintenance on', params: { maintenance: true } },
      { label: 'Config · loading', params: { state: 'loading' } },
      { label: 'Config · error', params: { state: 'error' } },
    ],
    render: list,
    mount: wire,
  });
})();
