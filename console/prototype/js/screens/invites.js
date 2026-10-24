/* Invites: codes for servers that register by invite, never shown after creation. */
(() => {
  const { esc, icon } = UI;
  const CODE = 'HX-7F2K-QP9D';

  function list(params, entry) {
    const state = params.state || '';
    const open = DATA.invites.filter((v) => v.status === 'open').length;
    const actions = UI.btn('Create invite', 'primary', { icon: 'plus', sm: true, attrs: 'data-create' });
    const header = UI.pageHead({
      eyebrow: 'Users', title: 'Invites',
      sub: `${open} open · ${DATA.invites.length} in total. Each code creates one account and expires after seven days.`,
      actions,
    });

    if (state === 'loading') {
      return `${header}<div class="scroll" data-keep-scroll="page"><div class="pg-body">${Kit.skeletonRows(5)}<div class="page-loading" style="padding-top:16px"><span>Loading invites…</span></div></div></div>`;
    }
    if (state === 'error') {
      return `${header}<div class="scroll" data-keep-scroll="page"><div class="pg-body">${Kit.loadFailed('Invites could not be loaded.', 'The server answered, but the invite list did not come back. Codes that already exist still work.')}</div></div>`;
    }
    if (state === 'empty') {
      return `${header}<div class="scroll" data-keep-scroll="page"><div class="pg-body"><div class="pcard">${Kit.empty({
        icon: 'ticket', title: 'No invites yet.',
        text: 'Create one when someone needs an account on this server. You can cancel an invite until it is used.',
        action: `<div style="margin-top:4px">${UI.btn('Create invite', 'primary', { icon: 'plus', attrs: 'data-create' })}</div>`,
      })}</div></div></div>`;
    }

    return `${header}<div class="scroll" data-keep-scroll="page"><div class="pg-body">
      <div class="sec-label">Issued invites<span class="spacer"></span><span class="sl-note">${DATA.invites.length} total</span></div>
      <div class="invite-list">${DATA.invites.map(UI.inviteCard).join('')}</div>
      <div class="list-foot"><span>Codes are shown once, at creation.</span><span>Cancelled and expired invites stay listed.</span></div>
    </div></div>`;
  }

  function create(entry) {
    Kit.createInvite((code) => {
      DATA.invites.unshift({
        id: 'inv_5C9E1KRT', status: 'open', issuer: 'admin', fresh: true,
        createdAt: '2026-10-22 11:42', expiresAt: '2026-10-29 11:42', redeemedBy: null,
      });
      entry.rerender();
      Kit.codeOnce({
        code,
        run: () => App.snack('Invite created · expires in 7 days'),
      });
    });
  }

  function wire(el, params, entry) {
    el.querySelectorAll('[data-create]').forEach((b) => b.addEventListener('click', () => create(entry)));
    el.querySelectorAll('[data-cancel-invite]').forEach((b) => b.addEventListener('click', () => {
      const v = DATA.invites.find((x) => x.id === b.dataset.cancelInvite);
      if (!v) return;
      Kit.confirm(
        `Cancel invite ${UI.shortId(v.id)}?`,
        'The code stops working at once. Anyone who already used it keeps their account.',
        'Cancel invite',
        () => { v.status = 'cancelled'; v.fresh = false; App.snack(`Invite ${UI.shortId(v.id)} cancelled`); entry.rerender(); },
      );
    }));
  }

  App.register({
    id: 'invites', title: 'Invites', group: 'Users', nav: 'invites', order: 25,
    interactions: [
      ['tap', 'Create invite', 'Asks for nothing else, creates the invite and shows its code once in a dialog.'],
      ['tap', 'Copy in the code dialog', 'Copies the code and says so; the code cannot be seen again after the dialog closes.'],
      ['tap', 'Cancel beside an open invite', 'Asks first, then stops the code working and marks the invite cancelled.'],
      ['auto', 'Invite cards', 'Show the short invite ID, state, creation, expiry, issuer and who used it — never the code.'],
      ['auto', 'The place itself', 'Only exists on servers that register by invite; Helix Global registers by phone, so the bar hides it.'],
    ],
    entries: [
      { label: 'Invites' },
      { label: 'Invites · new code', params: { code: true } },
      { label: 'Invites · empty', params: { state: 'empty' } },
      { label: 'Invites · loading', params: { state: 'loading' } },
      { label: 'Invites · error', params: { state: 'error' } },
    ],
    render: list,
    mount: wire,
    afterOpen(el, params, entry) {
      if (params.code) {
        setTimeout(() => {
          Kit.codeOnce({
            code: CODE,
            run: () => App.snack('Invite created · expires in 7 days'),
          });
        }, 220);
      }
    },
  });
})();
