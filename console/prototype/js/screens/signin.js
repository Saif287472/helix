/* Access: sign-in (address, then password or first-run setup) and app lock. */
(() => {
  const { esc, icon } = UI;

  function shell(inner, extra = '') {
    return `<div class="auth-page"><div class="auth-wrap">
      <div class="auth-card">
        <span class="auth-mark" aria-hidden="true"></span>
        ${inner}
      </div>
      <div class="auth-foot">${extra || `Helix Admin · v${esc(DATA.server.version)}`}</div>
    </div></div>`;
  }

  const fieldError = (state, key) => state[key] || '';

  function addressView(params, entry) {
    const value = entry.state.address != null ? entry.state.address : DATA.server.address;
    return shell(`<h1 class="auth-title">Helix Admin</h1>
      <p class="auth-sub">Sign in to the server you run. The address is where its admin API answers.</p>
      <form class="auth-form" novalidate>
        <label class="fld ${entry.state.addressError ? 'has-error' : ''}">
          <span class="fld-label">Server address</span>
          <span class="fld-box"><input id="serverAddress" type="url" value="${esc(value)}" placeholder="https://helix.example.com" autocomplete="url" /></span>
          <span class="fld-err" ${entry.state.addressError ? '' : 'hidden'}>${icon('warning-circle', 'fill')}<span>${esc(entry.state.addressError || '')}</span></span>
          <span class="fld-help">Helix Global is <span class="mono">${esc(DATA.server.address)}</span>.</span>
        </label>
        <button class="btn primary auth-submit" type="submit" data-continue>Continue</button>
      </form>
      <p class="auth-note">${icon('shield-check')} The password never leaves this device; only a key derived from it is sent.</p>`);
  }

  function passwordView(params, entry) {
    const setup = entry.state.setup || params.mode === 'setup';
    const err = entry.state.error || (params.error ? 'The password is not correct.' : '');
    return shell(`<button class="backbtn auth-back" data-back-to-address>${icon('arrow-left')}Change server</button>
      <div class="auth-server"><span class="state-dot ok"></span><span>${esc(DATA.server.name)}</span><span class="auth-host">${esc(DATA.server.address.replace(/^https?:\/\//, ''))}</span></div>
      <h1 class="auth-title">${setup ? 'Create admin password' : 'Sign in'}</h1>
      <p class="auth-sub">${setup ? 'This server has no admin password yet. Choose one with at least 12 characters.' : 'Enter the admin password for this server.'}</p>
      ${err ? `<div class="banner danger auth-banner">${icon('warning-circle')}<div class="bn-body"><div class="bn-title">${esc(err)}</div><div class="bn-text">The server refused this password. Try again — repeated failures are rate-limited.</div></div></div>` : ''}
      ${setup ? `<p class="auth-warn">${icon('warning')} Whoever reaches a new server first can do this step, so do it now.</p>` : ''}
      <form class="auth-form" novalidate>
        ${Kit.field({ id: 'adminPassword', label: setup ? 'New admin password' : 'Admin password', type: 'password', eye: true, hint: setup ? 'At least 12 characters' : '' })}
        ${setup ? Kit.field({ id: 'adminPasswordAgain', label: 'Repeat the password', type: 'password', eye: true }) : ''}
        <button class="btn primary auth-submit" type="submit">${setup ? 'Set password and sign in' : 'Sign in'}</button>
      </form>
      <p class="auth-note">${icon('lock-key')} Only a key derived from the password is sent. Sessions last until they are signed out.</p>`);
  }

  function statusView(entry) {
    return shell(`<h1 class="auth-title">Helix Admin is locked</h1>
      <p class="auth-sub">Use this device’s screen lock to open the console.</p>
      <div class="auth-lockart">${icon('lock-key')}</div>
      <button class="btn primary auth-submit" data-unlock>${icon('lock-open')}Unlock</button>
      <p class="auth-note">${icon('devices')} App lock is a device setting. It does not change the admin password.</p>`, `${esc(DATA.server.name)} · ${esc(DATA.server.address.replace(/^https?:\/\//, ''))}`);
  }

  function render(params, entry) {
    const mode = entry.state.mode || params.mode || 'address';
    entry.state.mode = mode;
    if (mode === 'lock') return statusView(entry);
    return mode === 'address' ? addressView(params, entry) : passwordView(params, entry);
  }

  function submitAddress(entry, el) {
    const input = el.querySelector('#serverAddress');
    const v = (input?.value || '').trim();
    entry.state.address = v;
    if (!/^https?:\/\/\S+\.\S+/.test(v)) {
      entry.state.addressError = v ? 'Use a full address, like https://helix.example.com.' : 'Enter the server address first.';
      entry.rerender();
      return;
    }
    entry.state.addressError = '';
    entry.state.mode = 'password';
    entry.rerender();
    el.querySelector('#adminPassword')?.focus();
  }

  function submitPassword(entry, el, setup) {
    const password = el.querySelector('#adminPassword')?.value || '';
    const again = el.querySelector('#adminPasswordAgain')?.value || '';
    if (setup) {
      if (password.length < 12) { entry.state.error = ''; App.snack('Use at least 12 characters', null, { tone: 'error' }); return; }
      if (password !== again) { App.snack('The two passwords do not match', null, { tone: 'error' }); return; }
    } else if (!password) {
      App.snack('Enter the admin password', null, { tone: 'error' });
      return;
    }
    App.reset('overview');
    App.snack(setup ? 'Password set · signed in' : 'Signed in');
  }

  function wire(el, params, entry) {
    const mode = entry.state.mode || params.mode || 'address';
    const input = el.querySelector('#serverAddress');
    if (input) input.addEventListener('input', () => { entry.state.address = input.value; });
    el.querySelector('form')?.addEventListener('submit', (e) => {
      e.preventDefault();
      if (mode === 'address') submitAddress(entry, el);
      else submitPassword(entry, el, mode === 'setup');
    });
    el.querySelector('[data-back-to-address]')?.addEventListener('click', () => {
      entry.state.mode = 'address';
      entry.state.error = '';
      entry.rerender();
    });
    el.querySelector('[data-unlock]')?.addEventListener('click', () => {
      App.reset('overview');
      App.snack('Unlocked');
    });
    if (mode !== 'address') setTimeout(() => el.querySelector('#adminPassword')?.focus(), 40);
  }

  App.register({
    id: 'signin', title: 'Sign in', group: 'Access', chrome: false, order: 40,
    interactions: [
      ['type', 'Server address', 'The address is remembered for next time; an empty or malformed address is refused in place.'],
      ['tap', 'Continue', 'Checks the address, then shows first-run setup when the server has no admin password, otherwise sign-in.'],
      ['tap', 'Change server', 'Goes back to the address without losing the saved server.'],
      ['tap', 'Sign in / Set password and sign in', 'First-run setup needs two matching passwords of at least 12 characters; then the dashboard opens.'],
      ['tap', 'Password eye', 'Shows or hides the password.'],
      ['auto', 'Wrong password', 'The error banner says the server refused the password and that repeated failures are rate-limited.'],
      ['auto', 'The notice under the form', 'Says the password never leaves the device and only a derived key is sent.'],
    ],
    entries: [
      { label: 'Sign in · address', params: { mode: 'address' } },
      { label: 'Sign in · password', params: { mode: 'password' } },
      { label: 'Sign in · first-run setup', params: { mode: 'setup' } },
      { label: 'Sign in · wrong password', params: { mode: 'password', error: '1' }, key: 'signin:error' },
    ],
    render,
    mount: wire,
  });

  App.register({
    id: 'lock', title: 'Locked console', group: 'Access', chrome: false, order: 41,
    interactions: [
      ['tap', 'Unlock', 'Asks for this device’s screen lock (biometrics, PIN, pattern or password), then reopens the console.'],
      ['auto', 'App lock', 'Is a device setting; it never changes the admin password or ends the server session.'],
    ],
    entries: [{ label: 'Locked console', params: { mode: 'lock' } }],
    render,
    mount: wire,
  });
})();
