/*
  Calls: the full-screen call (dark, the one "future" surface) and the call
  detail page. Flutter: CallScreen (IncomingCallView / InCallView), CallDetailScreen.
  Statuses, controls and ended reasons follow SCREENS.md (the real app).
*/
(() => {
  const { esc, icon, ibtn, avatar } = UI;
  const person = (id) => Data.people[id] || Data.people.nadia;
  const clock = (s) => `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
  const ENDED = {
    ended: ['Call ended', ''],
    declined: ['Call declined', ''],
    busy: ['Busy: on another call', 'They are in another call right now.'],
    noAnswer: ['No answer', ''],
    elsewhere: ['Answered on another device', ''],
    failed: ['Call failed', 'The call could not connect. Check your connection and try again.'],
  };
  const ROUTES = { earpiece: ['ear', 'Phone'], speaker: ['speaker-high', 'Speaker'], bluetooth: ['bluetooth', 'Bluetooth'], headset: ['headphones', 'Headset'] };

  function tray(st, video, ended) {
    const b = (k, ic, label, tip, on, disabled) => `<button class="cbtn ${on ? 'on' : ''}" data-c="${k}" title="${tip}" aria-label="${tip}" aria-pressed="${!!on}" ${disabled || ended ? 'disabled' : ''}><span class="cb-ico">${icon(ic, on ? 'fill' : '')}</span>${label}</button>`;
    const routeLabel = st.route === 'earpiece' ? 'Speaker' : ROUTES[st.route][1];
    const speaker = b('route', st.route === 'earpiece' ? 'speaker-high' : ROUTES[st.route][0], routeLabel, `Audio output: ${ROUTES[st.route][1]}`, st.route !== 'earpiece');
    const mute = b('mute', st.muted ? 'microphone-slash' : 'microphone', 'Mute', st.muted ? 'Unmute microphone' : 'Mute microphone', st.muted);
    const end = `<button class="cbtn end" data-c="end" title="End call" aria-label="End call" ${ended ? 'disabled' : ''}><span class="cb-ico">${icon('phone-disconnect', 'fill')}</span></button>`;
    const controls = video
      ? [b('flip', 'camera-rotate', 'Flip', 'Flip camera', false, !st.camera), b('camera', st.camera ? 'video-camera' : 'video-camera-slash', 'Video', st.camera ? 'Turn camera off' : 'Turn camera on', st.camera, st.phase !== 'active'), mute, speaker]
      : [speaker, b('video', 'video-camera-slash', 'Video', 'Video is not available on a voice call', false, true), mute];
    return `<div class="c-panel hideable" style="grid-template-columns:repeat(${controls.length},1fr)">${controls.join('')}${end}</div>`;
  }

  function header(video) {
    return `<div class="c-top hideable" style="justify-content:center;flex-direction:column;gap:4px;min-height:48px">
      <span class="c-label">Orbit ${video ? 'video' : 'voice'} call</span><span class="c-e2e">${icon('lock-simple', 'fill')}End-to-end encrypted</span></div>`;
  }

  App.register({
    id: 'call', title: 'Call', group: 'Calls', order: 30, night: true, modal: true,
    entries: [
      { key: 'call-incoming', label: 'Incoming voice call', params: { peer: 'nadia', phase: 'incoming' } },
      { key: 'call-incoming-video', label: 'Incoming video call', params: { peer: 'arif', phase: 'incoming', video: true } },
      { key: 'call-incoming-notice', label: 'Incoming · with a notice', params: { peer: 'nadia', phase: 'incoming', notice: 'Orbit needs the microphone to make calls. Allow it in your phone’s settings, then try again.' } },
      { key: 'call-outgoing', label: 'Calling…', params: { peer: 'nadia', phase: 'outgoing' } },
      { key: 'call-ringing', label: 'Ringing…', params: { peer: 'nadia', phase: 'ringing' } },
      { key: 'call-connecting', label: 'Connecting…', params: { peer: 'nadia', phase: 'connecting' } },
      { key: 'call-active', label: 'Voice call', params: { peer: 'nadia', phase: 'active' } },
      { key: 'call-active-weak', label: 'Voice call · poor connection', params: { peer: 'nadia', phase: 'active', weak: true } },
      { key: 'call-reconnecting', label: 'Voice call · reconnecting', params: { peer: 'nadia', phase: 'reconnecting' } },
      { key: 'call-video', label: 'Video call', params: { peer: 'nadia', phase: 'active', video: true } },
      { key: 'call-video-dialing', label: 'Video call · calling (your camera)', params: { peer: 'nadia', phase: 'outgoing', video: true } },
      { key: 'call-ended', label: 'Call ended', params: { peer: 'nadia', phase: 'ended', reason: 'ended', stay: true } },
      { key: 'call-busy', label: 'Busy: on another call', params: { peer: 'arif', phase: 'ended', reason: 'busy', stay: true } },
      { key: 'call-failed', label: 'Call failed', params: { peer: 'arif', phase: 'ended', reason: 'failed', stay: true } },
    ].map((e) => ({ ...e, base: { screen: 'home', params: { tab: 'calls' } } })),
    render(params, entry) {
      const st = entry.state;
      if (!st.init) { st.init = true; st.phase = params.phase; st.camera = !!params.video; st.route = 'earpiece'; st.muted = false; st.secs = params.phase === 'ended' ? 252 : 12; st.reason = params.reason || 'ended'; st.notice = params.notice || null; }
      const p = person(params.peer);
      const name = Data.displayName(p);
      const sub = esc(p.names.number || (p.names.helixName ? `~${p.names.helixName}` : ''));
      const notice = st.notice ? `<div class="c-noticebar">${icon('warning-circle', 'fill')}<span style="flex:1">${esc(st.notice)}</span>${ibtn('x', 'Dismiss', 'data-dismiss')}</div>` : '';
      const orb = (pulse) => `<div class="c-orb">${pulse ? '<span class="halo"></span><span class="halo h2"></span><span class="halo h3"></span>' : ''}${avatar(Data.av(p), 112)}</div>`;

      if (st.phase === 'incoming') {
        return `<div class="call">${header(params.video)}
          <div class="c-mid">${orb(true)}<h1 class="c-name">${esc(name)}</h1><div class="c-sub">${sub}</div><div class="c-status">${icon(params.video ? 'video-camera' : 'phone', 'fill')} Incoming ${params.video ? 'video' : 'voice'} call</div></div>
          ${notice}
          <div class="c-incoming">
            <button class="cbtn decline" data-c="decline" title="Decline call" aria-label="Decline call"><span class="cb-ico">${icon('phone-disconnect', 'fill')}</span>Decline</button>
            <button class="cbtn accept" data-c="accept" title="${params.video ? 'Answer video call' : 'Answer call'}" aria-label="${params.video ? 'Answer video call' : 'Answer call'}"><span class="cb-ico">${icon(params.video ? 'video-camera' : 'phone', 'fill')}</span>Answer</button>
          </div></div>`;
      }

      const ended = st.phase === 'ended';
      // Video layout once there is a picture: theirs when connected, yours while dialing.
      if (params.video && st.camera && !ended && (st.phase === 'active' || st.phase === 'outgoing' || st.phase === 'ringing')) {
        const dialing = st.phase !== 'active';
        return `<div class="call video connected ${st.controlsOff ? 'controls-off' : ''}"><div class="remote ${dialing ? 'ph-c' : 'ph-e'}" data-remote></div>
          <div class="hideable" style="position:relative;z-index:2;padding:48px 16px 0">${header(true)}</div>
          <div class="c-who hideable"><h1 class="c-name">${esc(name)}</h1><div class="c-status ${dialing ? '' : 'live'}">${dialing ? (st.phase === 'ringing' ? 'Ringing…' : 'Calling…') : `<span data-clock>${clock(st.secs)}</span>`}</div></div>
          ${dialing ? '' : '<div class="self ph-c" title="Show your camera full screen"></div>'}
          ${tray(st, true, false)}</div>`;
      }

      let status;
      if (ended) {
        const [reason, detail] = ENDED[st.reason];
        status = `<div class="c-status" style="color:${st.reason === 'failed' || st.reason === 'busy' ? '#FFD3D5' : 'var(--call-muted)'}">${reason}</div><div class="c-sub" style="margin-top:0">${clock(st.secs)}</div>${detail ? `<p class="c-detail">${detail}</p>` : ''}`;
      } else if (st.phase === 'active') status = `<div class="c-status live"><span data-clock>${clock(st.secs)}</span></div>${params.weak ? `<span class="c-chip">${icon('cell-signal-low', 'fill')}Poor connection</span>` : ''}${st.muted ? '<p class="c-detail">Your microphone is off</p>' : ''}`;
      else if (st.phase === 'reconnecting') status = `<div class="c-status">${icon('spinner-gap')} Reconnecting…</div>`;
      else status = `<div class="c-status">${{ outgoing: 'Calling…', ringing: 'Ringing…', connecting: 'Connecting…' }[st.phase]}</div>`;
      const dialing = ['outgoing', 'ringing', 'connecting'].includes(st.phase);
      return `<div class="call ${st.phase === 'active' ? 'connected' : ''} ${ended ? 'ended' : ''}">${header(params.video)}
        <div class="c-mid">${orb(dialing)}<h1 class="c-name">${esc(name)}</h1><div class="c-sub">${sub}</div>${status}</div>
        ${notice}${tray(st, !!params.video, ended)}</div>`;
    },
    mount(el, params, entry) {
      const st = entry.state; const rerender = () => entry.rerender();
      const finish = (reason) => {
        st.phase = 'ended'; st.reason = reason; clearInterval(st.timer); st.timer = null; rerender();
        if (!params.stay) setTimeout(() => { if (App.top() === entry) App.pop(); }, 2200);
      };
      el.querySelector('[data-dismiss]')?.addEventListener('click', () => { st.notice = null; rerender(); });
      el.querySelectorAll('[data-c]').forEach((b) => b.addEventListener('click', (e) => {
        e.stopPropagation();
        const k = b.dataset.c;
        if (k === 'accept') { st.phase = 'connecting'; rerender(); setTimeout(() => { if (App.top() === entry) { st.phase = 'active'; rerender(); } }, 900); }
        if (k === 'decline') finish('declined');
        if (k === 'end') finish('ended');
        if (k === 'mute') { st.muted = !st.muted; rerender(); }
        if (k === 'camera') { st.camera = !st.camera; rerender(); }
        if (k === 'flip') App.snack('Camera flipped');
        if (k === 'route') {
          const opts = [['earpiece', 'ear', 'Phone'], ['speaker', 'speaker-high', 'Speaker'], ['bluetooth', 'bluetooth', 'Bluetooth'], ['headset', 'headphones', 'Headset']];
          App.sheet({ title: 'Audio output', items: opts.map(([k2, ic, label]) => ({ icon: ic, label, on: st.route === k2, run: () => { st.route = k2; rerender(); } })) });
        }
      }));
      // Video: tap the picture to hide or show the controls; drag the self tile, tap it to swap.
      el.querySelector('[data-remote]')?.addEventListener('click', () => { st.controlsOff = !st.controlsOff; el.querySelector('.call').classList.toggle('controls-off', st.controlsOff); });
      const self = el.querySelector('.self');
      if (self) {
        let ox = 0, oy = 0, moved = false;
        self.addEventListener('pointerdown', (e) => { self.setPointerCapture(e.pointerId); ox = e.clientX - self.offsetLeft; oy = e.clientY - self.offsetTop; moved = false; });
        self.addEventListener('pointermove', (e) => { if (!self.hasPointerCapture(e.pointerId)) return; if (Math.abs(e.clientX - ox - self.offsetLeft) > 3) moved = true; self.style.left = `${e.clientX - ox}px`; self.style.top = `${e.clientY - oy}px`; self.style.right = 'auto'; });
        self.addEventListener('pointerup', () => {
          if (moved) return;
          const r = el.querySelector('.remote'); const a = r.className.match(/ph-\w/)[0]; const bcls = self.className.match(/ph-\w/)[0];
          r.className = r.className.replace(a, bcls); self.className = self.className.replace(bcls, a);
          self.title = self.title === 'Show your camera full screen' ? `Show ${Data.displayName(person(params.peer))} full screen` : 'Show your camera full screen';
        });
      }
      // Live flow: calling -> ringing -> connected; a running timer once connected.
      if ((st.phase === 'outgoing' || st.phase === 'ringing') && !st.auto && !params.stay) {
        st.auto = true;
        setTimeout(() => { if (App.top() === entry && st.phase === 'outgoing') { st.phase = 'ringing'; rerender(); } }, 1400);
        setTimeout(() => { if (App.top() === entry && st.phase === 'ringing') { st.phase = 'active'; rerender(); } }, 3600);
      }
      if (st.phase === 'active' && !st.timer) {
        st.timer = setInterval(() => {
          if (!entry.el.isConnected || st.phase !== 'active') { clearInterval(st.timer); st.timer = null; return; }
          st.secs++; const n = entry.el.querySelector('[data-clock]'); if (n) n.textContent = clock(st.secs);
        }, 1000);
      }
    },
  });

  // ---------------------------------------------------------------- call details
  App.register({
    id: 'call-detail', title: 'Call details', group: 'Calls', order: 30,
    entries: [{ key: 'call-detail', label: 'Call details', params: { id: 'call3' }, base: { screen: 'home', params: { tab: 'calls' } } }],
    render(params) {
      const c = Data.calls.find((x) => x.id === params.id) || Data.calls[0];
      const p = person(c.peer);
      const rows = [
        ['incoming', 'Incoming voice call', 'Yesterday, 21:30', '32:18'],
        ['missed', 'Missed voice call', 'Yesterday, 19:02', ''],
        ['outgoing', 'Outgoing voice call', 'Yesterday, 18:55', '1:04'],
      ];
      const ic = { incoming: ['arrow-down-left', 'var(--success)'], missed: ['arrow-down-left', 'var(--danger)'], outgoing: ['arrow-up-right', 'var(--success)'] };
      const round = (k, i, label) => `<button class="quick-item" data-k="${k}" title="${label}"><span class="q-ico">${icon(i)}</span><span class="q-lbl">${label}</span></button>`;
      return `${UI.appbar({ title: 'Call details', actions: ibtn('trash', 'Delete from call history', 'data-del') })}
        <div class="scroll" style="padding-bottom:30px">
          <div style="display:flex;flex-direction:column;align-items:center;padding:20px 20px 6px;gap:6px;text-align:center">
            ${avatar(Data.av(p), 72)}<div style="font-size:22px;font-weight:640;letter-spacing:-0.02em;margin-top:6px">${esc(Data.displayName(p))}</div>
            <div class="mono" style="font-size:12px;color:var(--ink-3)">${esc(Data.secondary(p) || '')}</div>
          </div>
          <div style="display:flex;justify-content:center;gap:18px;padding:10px 16px 6px">${round('voice', 'phone', 'Voice call')}${round('video', 'video-camera', 'Video call')}${round('contact', 'user-circle', 'Contact')}</div>
          ${UI.card(rows.map(([d, t, when, dur]) => UI.row({ icon: ic[d][0], weight: 'bold', title: d === 'missed' ? `<span style="color:var(--danger)">${t}</span>` : t, sub: when, subMono: true, value: dur, tag: 'div' }).replace('class="rw-ico', `style="--av-ink:${ic[d][1]}" class="rw-ico`)), { title: 'Calls' })}
        </div>`;
    },
    mount(el, params) {
      const c = Data.calls.find((x) => x.id === params.id) || Data.calls[0];
      el.querySelector('[data-back]').addEventListener('click', App.pop);
      el.querySelector('[data-k="voice"]').addEventListener('click', () => App.push('call', { peer: c.peer, phase: 'outgoing' }));
      el.querySelector('[data-k="video"]').addEventListener('click', () => App.push('call', { peer: c.peer, phase: 'outgoing', video: true }));
      el.querySelector('[data-k="contact"]').addEventListener('click', () => App.push('contact', { id: c.peer }));
      el.querySelector('[data-del]').addEventListener('click', () => App.dialog({ title: 'Delete from call history?', text: `All ${c.count || 1} calls with ${c.title} will be removed from your call history.`, actions: [{ label: 'Cancel' }, { label: 'Delete', kind: 'danger', run: () => App.pop() }] }));
    },
  });
})();
