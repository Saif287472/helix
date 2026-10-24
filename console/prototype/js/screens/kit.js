/* Reference: the console components in one place, for the Flutter port. */
(() => {
  const { esc } = UI;
  const sample = DATA.accounts[0];
  const report = DATA.reports[0];

  App.register({
    id: 'kit', title: 'Component kit', group: 'Reference', nav: null, order: 60,
    interactions: [
      ['tap', 'The switch row', 'Toggles in place; the kit has no server behind it.'],
      ['tap', 'The password eye', 'Shows or hides the sample password.'],
    ],
    entries: [{ label: 'Component kit' }],
    render() {
      return UI.page({
        eyebrow: 'Reference', title: 'Component kit',
        sub: 'The console’s own widgets, drawn once so the Flutter port has one reference. These are the Orbit components the admin reuses.',
        body: `<div class="kit-grid">
          <div class="pcard"><div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Buttons</div><div class="pcard-sub">Primary, secondary, ghost, danger; 34 px and 28 px.</div></div></div>
            <div class="pcard-body kit-row">${UI.btn('Refresh', 'secondary', { icon: 'arrows-clockwise' })}${UI.btn('Create invite', 'primary', { icon: 'plus' })}${UI.btn('Open account', 'ghost')}${UI.btn('Suspend', 'danger')}${UI.btn('Small', 'secondary', { sm: true })}</div>
          </div>
          <div class="pcard"><div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Pills</div><div class="pcard-sub">Tone means state, never decoration.</div></div></div>
            <div class="pcard-body kit-row">${UI.statusPill('active')}${UI.statusPill('suspended')}${UI.statusPill('open')}${UI.statusPill('resolved')}${UI.pill('Production', 'info')}${UI.pill('Not set up', 'mute')}</div>
          </div>
          <div class="pcard"><div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Metric tile</div><div class="pcard-sub">One number, one plain explanation.</div></div></div>
            <div class="pcard-body">${UI.metric({ label: 'Active device connections', value: UI.num(312), sub: 'Devices holding a live socket', icon: 'plugs-connected' })}</div>
          </div>
          <div class="pcard"><div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Account card</div><div class="pcard-sub">The list row; the split pane adds the hero.</div></div></div>
            <div class="pcard-body" style="padding:0">${UI.userCard(sample)}</div>
          </div>
          <div class="pcard"><div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Report card</div><div class="pcard-sub">Category, account, what was written, and the decision buttons.</div></div></div>
            <div style="padding:10px">${UI.reportCard(report)}</div>
          </div>
          <div class="pcard"><div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Audit row</div><div class="pcard-sub">The action, its kind, its target and the exact time.</div></div></div>
            <div class="audit-list">${UI.auditRow(DATA.audit[2])}</div>
          </div>
          <div class="pcard"><div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Invite card</div><div class="pcard-sub">The code is never in the list; only the ID and its state.</div></div></div>
            <div style="padding:10px">${UI.inviteCard(DATA.invites[0])}</div>
          </div>
          <div class="pcard"><div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Settings row and switch</div><div class="pcard-sub">The whole row is the target.</div></div></div>
            ${UI.switchRow({ title: 'Worldwide mode', sub: 'Off · people can only reach accounts on this server.', on: false, ic: 'globe-hemisphere-west' })}
          </div>
          <div class="pcard"><div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Fields</div><div class="pcard-sub">One line and multiline; a password field has an eye.</div></div></div>
            <div class="pcard-body">${Kit.field({ label: 'Server name', value: 'Helix Global' })}${Kit.field({ label: 'Admin password', type: 'password', eye: true, value: 'prototype' })}</div>
          </div>
          <div class="pcard"><div class="pcard-head"><div class="pcard-titles"><div class="pcard-title">Empty and failed</div><div class="pcard-sub">Both say what happened and what to do.</div></div></div>
            <div class="pcard-body kit-states">${Kit.empty({ icon: 'users-three', title: 'No one matches.', text: 'Try a Helix name or the last four digits.' })}<div class="load-failed compact"><span class="lf-ico">${UI.icon('cloud-slash')}</span><div class="lf-text"><div class="lf-title">This could not be loaded.</div><div class="lf-sub">Check the server, then try again.</div></div></div></div>
          </div>
        </div><div class="list-foot"><span>Reference only — no data on this page changes.</span><span>${esc(DATA.server.name)} · v${esc(DATA.server.version)}</span></div>`,
      });
    },
  });
})();
