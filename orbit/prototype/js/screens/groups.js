/*
  Groups: new group, member picker, group info, group settings, invite links,
  join requests, banned people, add members, join a group with a link.
  Flutter: features/groups/presentation. Copy from SCREENS.md.
*/
(() => {
  const { esc, icon, ibtn, avatar, row } = UI;
  const { section, field, intro, notice, wire, confirm, inputDialog } = Kit;
  const FAMILY = { id: 'group:family', title: 'Family', description: 'Eid plans, dinners and everything in between.', members: [
    { id: 'me', role: 'admin' }, { id: 'ammu', role: 'owner' }, { id: 'abbu', role: 'admin' }, { id: 'rumana', role: 'member' }, { id: 'karim', role: 'member', unconfirmed: true },
  ] };
  const nameOf = (id) => (id === 'me' ? 'You' : Data.displayName(Data.people[id]));
  const avOf = (id) => (id === 'me' ? { name: Data.me.name, color: 0 } : Data.av(Data.people[id]));
  const groupAv = { name: 'Family', seed: 'family', group: true };
  const roleLabel = { owner: 'Owner', admin: 'Admin', member: '' };

  // ------------------------------------------------------------ member picker
  function picker(st, exclude = []) {
    const q = (st.q || '').trim().toLowerCase();
    const ppl = ['nadia', 'arif', 'sadia', 'tanvir', 'ammu', 'abbu', 'rumana', 'karim', 'rafiq'].filter((id) => !exclude.includes(id)).map((id) => Data.people[id])
      .filter((p) => !q || Data.displayName(p).toLowerCase().includes(q) || (p.names.number || '').replace(/\D/g, '').includes(q.replace(/\D/g, '') || 'x'));
    const lookup = /^[+~\d]/.test(q) && q.length > 2 ? `<button class="chat-row" data-lookup>${`<span class="av" style="--size:44px;background:var(--accent-soft);color:var(--accent)">${icon(st.looking ? 'spinner-gap' : 'user-plus', 'bold')}</span>`}<span class="cr-body"><span class="cr-name"><span class="nm">Find “${esc(st.q.trim())}” on Orbit</span></span></span></button>` : '';
    return `${st.sel.size ? `<div class="mchips">${[...st.sel].map((id) => `<span class="mchip">${avatar(Data.av(Data.people[id]), 28)}${esc(Data.displayName(Data.people[id]).split(' ')[0])}${ibtn('x', 'Remove from selection', `data-unpick="${id}"`)}</span>`).join('')}</div>` : ''}
      <div class="search" style="margin-top:6px">${icon('magnifying-glass')}<input id="mpq" placeholder="Search name, number or ~name" value="${esc(st.q || '')}" aria-label="Search name, number or ~name" autocomplete="off"></div>
      ${lookup}
      ${ppl.length ? ppl.map((p) => `<button class="chat-row" data-pick="${p.id}" style="height:64px">${avatar(Data.av(p), 44)}<span class="cr-body"><span class="cr-name"><span class="nm">${esc(Data.displayName(p))}</span></span><span class="cr-preview mono" style="font-size:12px">${esc(Data.secondary(p) || '')}</span></span><span class="pick ${st.sel.has(p.id) ? 'on' : ''}">${icon('check', 'bold')}</span></button>`).join('')
        : lookup ? '' : st.q ? `<p class="sec-foot">No results</p>` : UI.empty({ icon: 'user-circle-dashed', title: 'Nobody here yet', text: 'Type a phone number or a ~name to find someone on Orbit.' })}`;
  }
  function wirePicker(el, entry, onChange) {
    const st = entry.state;
    el.querySelectorAll('[data-pick]').forEach((b) => b.addEventListener('click', () => { const id = b.dataset.pick; st.sel.has(id) ? st.sel.delete(id) : st.sel.add(id); onChange(); }));
    el.querySelectorAll('[data-unpick]').forEach((b) => b.addEventListener('click', () => { st.sel.delete(b.dataset.unpick); onChange(); }));
    const q = el.querySelector('#mpq');
    if (q) q.addEventListener('input', () => { st.q = q.value; const pos = q.selectionStart; onChange(); const n = entry.el.querySelector('#mpq'); n.focus(); n.setSelectionRange(pos, pos); });
    el.querySelector('[data-lookup]')?.addEventListener('click', () => { st.looking = true; onChange(); setTimeout(() => { st.looking = false; if (entry.el.isConnected) onChange(); App.snack('Nobody on Orbit matches that. Check the number or name.'); }, 900); });
  }

  // --------------------------------------------------------------- new group
  App.register({
    id: 'group-new', title: 'New group', group: 'Groups', order: 50,
    interactions: [
      ['tap', 'Picture circle', 'Adds a picture; when one is set, a sheet offers another or removing it.'],
      ['type', 'Group name', 'Names the group; creating without a name shows the error.'],
      ['tap', 'Person', 'Picks or unpicks them; picked people show as chips above.'],
      ['tap', '× on a chip', 'Unpicks that person.'],
      ['type', 'Member search', 'Filters people; a number or ~name shows a “Find on Orbit” row.'],
      ['tap', 'Find on Orbit row', 'Looks them up; says when nobody matches.'],
      ['tap', 'Create with N', 'Creates the group; explains anyone who could not be added; then opens the group chat.'],
    ],
    entries: [
      { key: 'group-new', label: 'New group', params: {} },
      { key: 'group-new-picked', label: 'New group · people picked', params: { name: 'Weekend trip', sel: ['nadia', 'arif', 'sadia'] } },
      { key: 'group-new-error', label: 'New group · name missing', params: { sel: ['nadia'], error: true } },
    ].map((e) => ({ ...e, base: { screen: 'home', params: { tab: 'chats' } } })),
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, sel: new Set(params.sel || []), name: params.name || '', error: params.error, q: '' });
      const n = st.sel.size;
      return `${UI.appbar({ title: 'New group' })}<div class="scroll" data-keep-scroll="ng" style="padding-bottom:110px">
        <div style="display:flex;gap:14px;align-items:flex-start;padding:16px var(--gutter) 0">
          <button class="av" data-pic style="--size:64px;border:1.5px dashed var(--accent-line);background:var(--accent-soft);color:var(--accent)" title="Add a group picture" aria-label="Add a group picture">${icon(st.pic ? 'check' : 'camera-plus')}</button>
          <div style="flex:1">${field({ id: 'gname', label: 'Group name', value: st.name, error: st.error ? 'Enter a group name of 1 to 100 characters.' : '', max: 100 })}</div></div>
        <div class="list-label"><span class="eyebrow">Members</span></div>
        ${picker(st)}</div>
        <button class="xfab" data-create ${st.busy ? 'disabled' : ''}>${st.busy ? '<i class="ph ph-spinner-gap spin"></i>' : icon('check', 'bold')}${n ? `Create with ${n}` : 'Create group'}</button>`;
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      wirePicker(el, entry, () => entry.rerender());
      el.querySelector('#gname').addEventListener('input', (e) => { st.name = e.target.value; });
      el.querySelector('[data-pic]').addEventListener('click', () => (st.pic ? App.sheet({ title: 'Group picture', items: [{ icon: 'image', label: 'Choose another picture' }, { icon: 'trash', label: 'Remove picture', danger: true, run: () => { st.pic = false; entry.rerender(); } }] }) : (st.pic = true, entry.rerender())));
      el.querySelector('[data-create]').addEventListener('click', () => {
        if (!st.name.trim()) { st.error = true; entry.rerender(); return; }
        st.busy = true; entry.rerender();
        setTimeout(() => {
          st.busy = false;
          const go = () => App.replace('chat', { id: 'group:family' });
          if (st.sel.has('arif')) App.dialog({ title: 'Some people were not added', text: 'Arif Hossain could not be added. The group was created; send them an invite link from the group’s page.', actions: [{ label: 'OK', kind: 'primary', run: go }] });
          else go();
        }, 800);
      });
    },
  });

  // -------------------------------------------------------------- group info
  App.register({
    id: 'group-info', title: 'Group info', group: 'Groups', order: 50,
    interactions: [
      ['auto', 'Members, when the group lets everyone edit and add', 'They see the picture, Edit group info and Add members too.'],
      ['tap', 'Group picture (admin)', 'Sheet: choose or remove the picture.'],
      ['tap', 'Edit (admin)', 'Sheet with the name and description, and Save.'],
      ['tap', 'Disappearing messages', 'Sheet: Off, 24 hours, 7 days, 90 days.'],
      ['tap', 'Member', 'Sheet: Make or remove admin, Make owner (owner only, asks), Remove (asks), Remove and ban (asks).'],
      ['tap', 'Add members / Invite with a link / Join requests / Banned people / Group settings', 'Opens that page.'],
      ['tap', 'Confirm / Remove on an unconfirmed member', 'Confirms them, or asks before removing them.'],
      ['tap', 'Leave group', 'Asks first, then returns to Chats and says you left.'],
      ['tap', 'Delete group (owner)', 'Asks first, then returns to Chats.'],
    ],
    entries: [
      { key: 'group-info', label: 'Group info (you are an admin)', params: { role: 'admin' } },
      { key: 'group-info-owner', label: 'Group info (owner view)', params: { role: 'owner' } },
      { key: 'group-info-member', label: 'Group info (plain member)', params: { role: 'member' } },
      { key: 'group-info-member-open', label: 'Group info (member; the group lets everyone edit and add)', params: { role: 'member', everyone: true } },
      { key: 'group-info-pending-link', label: 'Group info · unconfirmed member who joined by link', params: { role: 'admin', pendingReason: 'link' } },
      { key: 'group-info-gone', label: 'Group info · not in the group', params: { gone: true } },
    ].map((e) => ({ ...e, base: [{ screen: 'home', params: { tab: 'chats' } }, { screen: 'chat', params: { id: 'group:family' } }] })),
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, disappearing: '7 days', confirmed: false });
      if (params.gone) return Kit.page({ title: 'Group info', body: UI.empty({ icon: 'users-three', title: 'You are not in this group', text: 'You left it, were removed, or it was deleted. Its messages stay in your chats.', action: '<button class="btn secondary" data-back>Go back</button>' }) });
      const role = params.role || 'admin';
      const admin = role !== 'member';
      // With Everyone in the group settings, members may edit the group and add people too (Review 1).
      const open = admin || !!params.everyone;
      const members = FAMILY.members.map((m) => (m.id === 'me' ? { ...m, role } : m.id === 'ammu' && role === 'owner' ? { ...m, role: 'admin' } : m));
      const canAct = (m) => m.id !== 'me' && (role === 'owner' || (role === 'admin' && m.role === 'member'));
      const memberRow = (m) => {
        const sub = [m.unconfirmed && !st.confirmed ? '<span style="color:var(--warning)">Not confirmed</span>' : '', roleLabel[m.role], m.id === 'me' ? '' : esc(Data.secondary(Data.people[m.id]) || '')].filter(Boolean).join(' · ');
        return `<div class="row">${avatar(avOf(m.id), 40)}<span class="rw-body"><span class="rw-title" style="display:block">${esc(nameOf(m.id))}</span><span class="rw-sub" style="display:block">${sub}</span></span>${canAct(m) ? ibtn('dots-three-vertical', `Actions for ${nameOf(m.id)}`, `data-member="${m.id}"`) : ''}</div>`;
      };
      const pending = st.confirmed ? '' : `<div class="pending-card" style="margin:14px var(--gutter) 0">${icon('shield-warning', 'fill')}<div><div class="pc-title">Confirm Karim Uncle?</div><div class="pc-text">${params.pendingReason === 'link' ? 'Karim Uncle joined this group through its invite link, and nothing else vouches for them.' : 'Karim Uncle was added by the server roster, but no admin of this group announced it.'} Until you confirm, what you send in this group stays unreadable to them.</div>${admin ? '' : '<div class="pc-text" style="margin-top:6px;color:var(--ink-3)">Only an admin can remove someone. If you do not know them, you can leave the group.</div>'}<div class="pc-actions"><button class="btn primary" data-confirm>Confirm</button>${admin ? '<button class="btn secondary" data-remove-pending>Remove</button>' : ''}</div></div></div>`;
      const body = `
        <div class="hero"><button class="av" style="--size:112px;border:0;padding:0;background:var(--av-0-bg);color:var(--av-0-ink)" ${open ? 'data-gpic title="Group picture"' : ''}>${icon('users-three', 'fill')}</button>
          <div class="h-name">${esc(FAMILY.title)}</div><div class="h-sub">${members.length} members</div><div class="h-about">${esc(FAMILY.description)}</div>
          ${open ? `<button class="btn secondary" style="margin-top:12px;height:40px" data-edit>${icon('pencil-simple')}Edit group info</button>` : ''}</div>
        ${pending}
        ${section('Group', [
          row({ icon: 'timer', color: 5, title: 'Disappearing messages', value: st.disappearing, end: admin ? 'chevron' : '', attrs: admin ? 'data-disappear' : '', tag: admin ? 'button' : 'div' }),
          ...(admin ? [
            row({ icon: 'sliders-horizontal', color: 0, title: 'Group settings', sub: 'Who can edit, add people and send', end: 'chevron', attrs: 'data-go="group-settings"' }),
            row({ icon: 'link-simple', color: 1, title: 'Invite with a link', end: 'chevron', attrs: 'data-go="group-invite"' }),
            row({ icon: 'user-circle-plus', color: 3, title: 'Join requests', sub: '2 people are waiting', end: 'chevron', attrs: 'data-go="group-requests"' }),
            row({ icon: 'prohibit', color: 7, title: 'Banned people', end: 'chevron', attrs: 'data-go="group-banned"' }),
          ] : []),
        ])}
        <div class="group-title eyebrow">${members.length} members</div>
        <div class="card">${open ? `<button class="row accent" data-go="group-add"><span class="rw-ico" style="background:var(--accent);color:var(--on-accent)">${icon('user-plus', 'bold')}</span><span class="rw-body"><span class="rw-title">Add members</span></span></button>` : ''}${members.map(memberRow).join('')}</div>
        ${section('', [row({ icon: 'sign-out', title: 'Leave group', danger: true, attrs: 'data-leave' }), ...(role === 'owner' ? [row({ icon: 'trash', title: 'Delete group', danger: true, attrs: 'data-delete' })] : [])])}`;
      return Kit.page({ title: 'Group info', body });
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      const role = params.role || 'admin';
      el.querySelector('[data-confirm]')?.addEventListener('click', () => { st.confirmed = true; entry.rerender(); App.snack('Karim Uncle confirmed.'); });
      el.querySelector('[data-remove-pending]')?.addEventListener('click', () => confirm('Remove Karim Uncle?', 'Karim Uncle will be taken out of the group. The group key changes, so they cannot read anything new.', 'Remove', () => App.snack('Removed 1 person.')));
      el.querySelector('[data-gpic]')?.addEventListener('click', () => App.sheet({ title: 'Group picture', items: [{ icon: 'image', label: 'Choose a picture' }, { icon: 'trash', label: 'Remove picture', danger: true }] }));
      el.querySelector('[data-edit]')?.addEventListener('click', () => {
        const h = App.sheet({ title: 'Edit group info', body: `<div class="pad">${field({ id: 'eg1', label: 'Group name', value: FAMILY.title, max: 100 })}${field({ id: 'eg2', label: 'Description', value: FAMILY.description, max: 500, multiline: true, rows: 3 })}<div class="btn-row" style="padding:4px 0 0"><button class="btn secondary" data-x>Cancel</button><button class="btn primary" data-ok>Save</button></div></div>` });
        h.panel.querySelector('[data-x]').addEventListener('click', () => h.close());
        h.panel.querySelector('[data-ok]').addEventListener('click', () => { FAMILY.title = h.panel.querySelector('#eg1').value || FAMILY.title; FAMILY.description = h.panel.querySelector('#eg2').value; h.close(); entry.rerender(); });
      });
      el.querySelector('[data-disappear]')?.addEventListener('click', () => App.sheet({ title: 'Disappearing messages', text: 'New messages in this group disappear after this long, for everyone.', items: ['Off', '24 hours', '7 days', '90 days'].map((o) => ({ icon: 'timer', label: o, on: st.disappearing === o, run: () => { st.disappearing = o; entry.rerender(); } })) }));
      el.querySelectorAll('[data-member]').forEach((b) => b.addEventListener('click', () => {
        const id = b.dataset.member; const n = nameOf(id); const m = FAMILY.members.find((x) => x.id === id);
        const isAdmin = m.role === 'admin' || (id === 'ammu' && role === 'owner');
        const items = [
          { icon: 'shield-star', label: isAdmin ? 'Remove admin' : 'Make admin', run: () => App.snack(isAdmin ? `${n} is no longer an admin.` : `${n} is now an admin.`) },
          ...(role === 'owner' ? [{ icon: 'crown-simple', label: 'Make owner', run: () => App.dialog({ title: `Make ${n} the owner?`, text: 'They will own the group. You become an admin and cannot undo this yourself.', actions: [{ label: 'Cancel' }, { label: 'Make owner', kind: 'primary' }] }) }] : []),
          { icon: 'user-minus', label: 'Remove from group', danger: true, run: () => confirm(`Remove ${n}?`, `${n} will be taken out of the group. The group key changes, so they cannot read anything new.`, 'Remove', () => App.snack('Removed 1 person.')) },
          { icon: 'prohibit', label: 'Remove and ban', danger: true, run: () => confirm(`Remove and ban ${n}?`, `${n} will be removed and cannot join again through a link until you unban them.`, 'Ban', () => App.snack(`${n} was removed and banned.`)) },
        ];
        App.sheet({ title: n, items });
      }));
      el.querySelector('[data-leave]')?.addEventListener('click', () => confirm(`Leave “${FAMILY.title}”?`, 'You will stop getting its messages. Its history stays in your chats. You can only come back if someone adds you or sends a link.', 'Leave', () => { App.popTo('home'); App.snack('You left this group.'); }));
      el.querySelector('[data-delete]')?.addEventListener('click', () => confirm(`Delete “${FAMILY.title}”?`, 'The group is deleted for everyone and nobody can send to it any more. This cannot be undone.', 'Delete group', () => { App.popTo('home'); App.snack('This group was deleted.'); }));
    },
  });

  const infoBase = [{ screen: 'home', params: { tab: 'chats' } }, { screen: 'chat', params: { id: 'group:family' } }, { screen: 'group-info', params: { role: 'admin' } }];

  // ---------------------------------------------------------- group settings
  App.register({
    id: 'group-settings', title: 'Group settings', group: 'Groups', order: 50,
    interactions: [
      ['tap', 'Edit group info / Add members / Send messages', 'Sheet: Only admins or Everyone.'],
    ],
    entries: [
      { key: 'group-settings', label: 'Group settings', params: {} },
      { key: 'group-settings-member', label: 'Group settings · not an admin', params: { member: true } },
    ].map((e) => ({ ...e, base: infoBase })),
    render(params) {
      const rows = [['Edit group info', 'Who can edit group info', 'Only admins'], ['Add members', 'Who can add members', 'Everyone'], ['Send messages', 'Who can send messages', 'Everyone']]
        .map(([t, s, c]) => (params.member ? row({ title: t, value: c, tag: 'div' }) : row({ title: t, value: c, end: 'chevron', attrs: `data-choose="${esc([s, 'Everyone', 'Only admins'].join('|'))}"` })));
      return Kit.page({ title: 'Group settings', body: `${params.member ? notice('info', 'Only admins can change these settings.') : ''}${section('Members can', rows, 'Admins can always do all of these.')}` });
    },
    mount(el, params, entry) { wire(el, entry); },
  });

  // ------------------------------------------------------------ invite links
  App.register({
    id: 'group-invite', title: 'Invite with a link', group: 'Groups', order: 50,
    interactions: [
      ['auto', 'New links', 'Join straight away unless “Admins approve new members” is on (off by default).'],
      ['tap', 'Approve new members', 'Switch: new links need an admin’s approval.'],
      ['tap', 'Create a link', 'A new link appears at the top.'],
      ['tap', 'Share / Copy', 'Shares the invite text or copies the link.'],
      ['tap', 'Revoke', 'Asks first; the link stops working.'],
    ],
    entries: [
      { key: 'group-invite', label: 'Invite links', params: { links: 2 } },
      { key: 'group-invite-empty', label: 'Invite links · none yet', params: { links: 0 } },
    ].map((e) => ({ ...e, base: infoBase })),
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, approve: !!params.approve, links: params.links === 2 ? [{ approve: true, url: 'https://helix.agiletechbd.com/open#HLX-GRP-8KQ2-ZP4M-W7DX-3RTA' }, { approve: false, url: 'https://helix.agiletechbd.com/open#HLX-GRP-2VNC-HY6Q-5BJE-K9LS' }] : [] });
      const cards = st.links.length ? st.links.map((l, i) => `<div class="linkc"><div class="lk-head">${icon(l.approve ? 'shield-check' : 'lightning', 'fill')}${l.approve ? 'Admins approve new members' : 'Joins straight away'}</div><div class="lk-url">${esc(l.url)}</div>
        <div class="lk-actions"><button class="btn primary" data-share>${icon('share-network')}Share</button><button class="btn secondary" data-copy>${icon('copy')}Copy</button><button class="btn ghost" style="color:var(--danger)" data-revoke="${i}">Revoke</button></div></div>`).join('')
        : '<p class="sec-foot" style="text-align:center;margin-top:18px">Links you make appear here so you can share or revoke them.</p>';
      return Kit.page({ title: 'Invite with a link', body: `${intro('', 'Anyone with a link can ask to join this group. Share it only with people you want in.')}
        ${section('', [row({ title: 'Admins approve new members', sub: st.approve ? 'People who use the link wait for an admin to let them in.' : 'People who use the link join straight away.', end: 'switch', on: st.approve, attrs: 'data-switch data-approve' })])}
        <div class="btn-row"><button class="btn primary block" data-create>${st.busy ? '<i class="ph ph-spinner-gap spin"></i>' : icon('link-simple-horizontal')}Create link</button></div>${cards}` });
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      el.querySelector('[data-approve]').addEventListener('toggle', (e) => { st.approve = e.detail; entry.rerender(); });
      el.querySelector('[data-create]').addEventListener('click', () => { st.busy = true; entry.rerender(); setTimeout(() => { st.busy = false; st.links.unshift({ approve: st.approve, url: 'https://helix.agiletechbd.com/open#HLX-GRP-6TRM-QX2L-9HDW-AE5C' }); entry.rerender(); }, 700); });
      el.querySelectorAll('[data-share]').forEach((b) => b.addEventListener('click', () => App.snack('Opens the share sheet: Join the group “Family” on Orbit: …')));
      el.querySelectorAll('[data-copy]').forEach((b) => b.addEventListener('click', () => App.snack('Link copied.')));
      el.querySelectorAll('[data-revoke]').forEach((b) => b.addEventListener('click', () => confirm('Revoke this link?', 'It stops working at once. People who already joined stay in the group.', 'Revoke', () => { st.links.splice(+b.dataset.revoke, 1); entry.rerender(); })));
    },
  });

  // ------------------------------------------------- join requests and bans
  App.register({
    id: 'group-requests', title: 'Join requests', group: 'Groups', order: 50,
    interactions: [
      ['tap', 'Approve / Reject', 'Lets the person in, or turns them away.'],
    ],
    entries: [
      { key: 'group-requests', label: 'Join requests', params: {} },
      { key: 'group-requests-empty', label: 'Join requests · nobody waiting', params: { empty: true } },
    ].map((e) => ({ ...e, base: infoBase })),
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, list: params.empty ? [] : [['sadia', 'today at 09:02'], ['tanvir', 'yesterday at 21:40']] });
      if (!st.list.length) return Kit.page({ title: 'Join requests', body: UI.empty({ icon: 'user-circle-plus', title: 'No one is waiting', text: 'When someone uses an approval link, they show up here for you to let in.' }) });
      return Kit.page({ title: 'Join requests', body: `<div style="height:12px"></div><div class="card">${st.list.map(([id, when]) => { const n = Data.displayName(Data.people[id]); return `<div class="row">${avatar(Data.av(Data.people[id]), 40)}<span class="rw-body"><span class="rw-title" style="display:block">${esc(n)}</span><span class="rw-sub" style="display:block">Asked ${when}</span></span>${ibtn('x', `Reject ${n}`, `data-reject="${id}"`, 'danger')}${ibtn('check', `Approve ${n}`, `data-approve="${id}"`, 'accent', 'bold')}</div>`; }).join('')}</div>` });
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      const done = (id, msg) => { st.list = st.list.filter(([x]) => x !== id); entry.rerender(); App.snack(msg); };
      el.querySelectorAll('[data-approve]').forEach((b) => b.addEventListener('click', () => done(b.dataset.approve, `${Data.displayName(Data.people[b.dataset.approve])} joined the group.`)));
      el.querySelectorAll('[data-reject]').forEach((b) => b.addEventListener('click', () => done(b.dataset.reject, `${Data.displayName(Data.people[b.dataset.reject])} was turned away.`)));
    },
  });

  App.register({
    id: 'group-banned', title: 'Banned people', group: 'Groups', order: 50,
    interactions: [
      ['tap', 'Unban', 'Lets the person join again with a link.'],
    ],
    entries: [
      { key: 'group-banned', label: 'Banned people', params: {} },
      { key: 'group-banned-empty', label: 'Banned people · none', params: { empty: true } },
    ].map((e) => ({ ...e, base: infoBase })),
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, list: params.empty ? [] : ['shuvo'] });
      const note = 'Banned people cannot join through a link. Bans made on other devices are not listed here.';
      if (!st.list.length) return Kit.page({ title: 'Banned people', body: UI.empty({ icon: 'prohibit', title: 'No one is banned', text: 'People you remove and ban from this phone are listed here. Bans made on another device are not shown.' }) });
      return Kit.page({ title: 'Banned people', body: `${intro('', note)}<div style="height:10px"></div><div class="card">${st.list.map((id) => `<div class="row">${avatar(Data.av(Data.people[id]), 40)}<span class="rw-body"><span class="rw-title" style="display:block">${esc(Data.displayName(Data.people[id]))}</span><span class="rw-sub" style="display:block">Banned 2 October</span></span><button class="btn ghost" data-unban="${id}">Unban</button></div>`).join('')}</div>` });
    },
    mount(el, params, entry) {
      wire(el, entry);
      el.querySelectorAll('[data-unban]').forEach((b) => b.addEventListener('click', () => { entry.state.list = []; entry.rerender(); App.snack('Shuvo can join again.'); }));
    },
  });

  // ------------------------------------------------------------- add members
  App.register({
    id: 'group-add', title: 'Add members', group: 'Groups', order: 50,
    interactions: [
      ['tap', 'Person', 'Picks or unpicks them.'],
      ['type', 'Search', 'Filters people; a number or ~name can be looked up.'],
      ['tap', 'Add', 'Adds them; explains when nobody could be added; returns with “Added N people”.'],
    ],
    entries: [{ key: 'group-add', label: 'Add members', params: {}, base: infoBase }],
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, sel: new Set(), q: '' });
      return `${UI.appbar({ title: 'Add members' })}<div class="scroll" data-keep-scroll="am" style="padding-bottom:110px">${picker(st, ['ammu', 'abbu', 'rumana', 'karim'])}</div>
        ${st.sel.size ? `<button class="xfab" data-add>${st.busy ? '<i class="ph ph-spinner-gap spin"></i>' : icon('user-plus', 'bold')}Add ${st.sel.size}</button>` : ''}`;
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry); wirePicker(el, entry, () => entry.rerender());
      el.querySelector('[data-add]')?.addEventListener('click', () => {
        st.busy = true; entry.rerender();
        setTimeout(() => {
          if (st.sel.has('arif') && st.sel.size === 1) { st.busy = false; entry.rerender(); App.dialog({ title: 'No one was added', text: 'Arif Hossain could not be added. Send them an invite link instead.', actions: [{ label: 'OK', kind: 'primary' }] }); return; }
          const n = st.sel.size; App.pop(); App.snack(n === 1 ? 'Added 1 person.' : `Added ${n} people.`);
        }, 800);
      });
    },
  });

  // -------------------------------------------------------- join with a link
  App.register({
    id: 'group-join', title: 'Join a group', group: 'Groups', order: 50,
    interactions: [
      ['type', 'Link', 'The group link to join.'],
      ['tap', 'Paste', 'Pastes the link.'],
      ['tap', 'Continue', 'Checks it (“not an Orbit group link” when wrong), loads, then shows the group preview.'],
      ['tap', 'Join', 'Joins, or waits for an admin when the link needs approval.'],
      ['tap', 'Open', 'Opens the group chat.'],
      ['tap', 'Try again', 'Back to the link field after a failure.'],
    ],
    entries: [
      { key: 'group-join', label: 'Join a group · paste link', params: { phase: 'input' } },
      { key: 'group-join-preview', label: 'Join a group · preview', params: { phase: 'preview' } },
      { key: 'group-join-approval', label: 'Join a group · approval link', params: { phase: 'preview', approval: true } },
      { key: 'group-join-member', label: 'Join a group · already a member', params: { phase: 'preview', member: true } },
      { key: 'group-join-noname', label: 'Join a group · the link did not open the name', params: { phase: 'preview', noName: true } },
      { key: 'group-join-done', label: 'Join a group · joined', params: { phase: 'joined' } },
      { key: 'group-join-pending', label: 'Join a group · request sent', params: { phase: 'pending' } },
      { key: 'group-join-failed', label: 'Join a group · link expired', params: { phase: 'failed' } },
    ].map((e) => ({ ...e, base: { screen: 'home', params: { tab: 'chats' } } })),
    render(params, entry) {
      const st = entry.state; if (!st.init) Object.assign(st, { init: true, phase: params.phase, link: params.phase === 'input' ? '' : 'https://helix.agiletechbd.com/open#HLX-GRP-8KQ2-ZP4M-W7DX-3RTA' });
      const gav = { name: 'Book Club', seed: 'bookclub', group: true };
      let body;
      switch (st.phase) {
        case 'input':
          body = `${intro('', 'Paste the group link you were sent. It starts with https:// or helix:// and ends with HLX-GRP-…')}<div class="pad" style="margin-top:14px">${field({ id: 'jlink', label: 'Group link', value: st.link, hint: 'https://…/open#HLX-GRP-…', mono: true, paste: true })}<button class="btn primary block" data-continue>Continue</button></div>`; break;
        case 'loading':
          body = `<div class="center-page"><i class="ph ph-spinner-gap spin" style="font-size:34px;color:var(--accent)"></i><p>Opening the link…</p></div>`; break;
        case 'preview':
          body = params.noName
            ? `<div class="hero" style="padding-top:34px">${avatar({ name: '?', color: 7 }, 112)}<div class="h-name">A group on Orbit</div><div class="h-about">This link did not open the group’s name. It may be cut off; you can still ask to join.</div></div>`
            : `<div class="hero" style="padding-top:34px">${avatar(gav, 112)}<div class="h-name">Book Club</div><div class="h-sub">14 members</div><div class="h-about">One book a month, coffee every Saturday.</div></div>`;
          body += `
${params.member ? notice('info', 'You are already in this group.') : params.approval ? notice('info', 'An admin has to approve you before you are in.') : ''}
            <div class="btn-row" style="flex-direction:column">${params.member ? '<button class="btn primary block" data-open>Open group</button>' : `<button class="btn primary block" data-join>${params.approval ? 'Ask to join' : 'Join group'}</button>`}<button class="btn secondary block" data-back>Cancel</button></div>`; break;
        case 'joining':
          body = `<div class="center-page"><i class="ph ph-spinner-gap spin" style="font-size:34px;color:var(--accent)"></i><p>Joining…</p></div>`; break;
        case 'joined':
          body = `<div class="center-page"><div class="cp-icon" style="background:var(--success-soft);color:var(--success)">${icon('check-circle', 'fill')}</div><h2>You joined “Book Club”</h2><p>You are in the group now.</p><button class="btn primary" style="margin-top:12px" data-open>Open group</button></div>`; break;
        case 'pending':
          body = `<div class="center-page"><div class="cp-icon" style="background:var(--accent-soft);color:var(--accent)">${icon('hourglass-medium', 'fill')}</div><h2>Request sent</h2><p>An admin of “Book Club” has to approve you. You will see the group when they do.</p><button class="btn primary" style="margin-top:12px" data-back>Done</button></div>`; break;
        default:
          body = `<div class="center-page"><div class="cp-icon" style="background:var(--danger-soft);color:var(--danger)">${icon('link-break', 'fill')}</div><h2>Something went wrong</h2><p>This invite link has expired. Ask for a new one.</p><button class="btn secondary" style="margin-top:12px" data-retry>Retry</button></div>`;
      }
      return Kit.page({ title: 'Join a group', body });
    },
    mount(el, params, entry) {
      const st = entry.state; wire(el, entry);
      const to = (p, ms, then) => { st.phase = p; entry.rerender(); if (then) setTimeout(() => { if (entry.el.isConnected) { st.phase = then; entry.rerender(); } }, ms); };
      el.querySelector('[data-paste]')?.addEventListener('click', (e) => { e.preventDefault(); st.link = 'https://helix.agiletechbd.com/open#HLX-GRP-8KQ2-ZP4M-W7DX-3RTA'; entry.rerender(); });
      el.querySelector('[data-continue]')?.addEventListener('click', () => {
        st.link = el.querySelector('#jlink').value.trim();
        if (!/HLX-GRP-/i.test(st.link)) { App.snack('That is not an Orbit group link. Check that you copied all of it.'); return; }
        to('loading', 900, 'preview');
      });
      el.querySelector('[data-join]')?.addEventListener('click', () => to('joining', 900, params.approval ? 'pending' : 'joined'));
      el.querySelectorAll('[data-open]').forEach((b) => b.addEventListener('click', () => App.replace('chat', { id: 'group:family' })));
      el.querySelector('[data-retry]')?.addEventListener('click', () => to('input'));
    },
  });

  window.HelixFamily = FAMILY;
})();
