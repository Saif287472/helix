/*
  Appearance (You > Appearance): pick a theme. Each card is a live mini chat
  drawn in its own theme (data-theme on the card scopes the tokens), so what
  you see is what you get. The choice stays until you change it.
*/
(() => {
  const { esc, icon } = UI;
  const base = [{ screen: 'home', params: { tab: 'chats' } }, { screen: 'settings-page', params: {} }];

  function card(t, current) {
    const on = t.id === current;
    return `<button class="theme-card ${on ? 'on' : ''}" data-theme="${t.id}" data-pick="${t.id}" aria-pressed="${on}" aria-label="${esc(t.name)} theme${on ? ', selected' : ''}">
      <span class="tc-screen">
        <span class="tc-head"><span class="wordmark tc-word">Orbit</span>${on ? `<span class="tc-check">${icon('check', 'bold')}</span>` : ''}</span>
        <span class="tc-bub in">Got a minute?</span>
        <span class="tc-bub out">Sure, what’s up?</span>
        <span class="tc-bar"><span class="tc-pill">Chats</span><span class="tc-fab"></span></span>
      </span>
      <span class="tc-meta"><span class="tc-name">${esc(t.name)}</span><span class="tc-vibe">${esc(t.vibe)}</span></span>
    </button>`;
  }

  App.register({
    id: 'appearance', title: 'Appearance', group: 'You (settings and profile)', order: 58,
    entries: [{ key: 'appearance', label: 'Appearance · pick a theme', params: {}, base }],
    render() {
      const all = window.OrbitThemes || [];
      const cur = App.getTheme();
      const light = all.filter((t) => !t.dark); const dark = all.filter((t) => t.dark);
      return `<header class="appbar flat you-bar">${UI.ibtn('arrow-left', 'Back', 'data-back')}<div class="ab-title"><h1>Appearance</h1></div></header>
        <div class="scroll" data-keep-scroll="appearance" style="padding-bottom:36px">
          <div class="hero-card"><div class="hc-top"><span class="hc-ico">${icon('palette', 'fill')}</span><div class="hc-text"><div class="hc-title">${esc(cur.name)}</div><div class="hc-sub">${esc(cur.vibe)} · ${cur.dark ? 'dark' : 'light'}</div></div></div>
            <div class="hc-pills">${cur.swatches.map((c) => `<span class="swatch" style="background:${c}"></span>`).join('')}<span class="hc-pill" style="margin-left:auto">${icon('lock-simple')}Stays until you change it</span></div></div>
          <div class="group-title eyebrow">Light</div><div class="theme-grid">${light.map((t) => card(t, cur.id)).join('')}</div>
          <div class="group-title eyebrow">Dark</div><div class="theme-grid">${dark.map((t) => card(t, cur.id)).join('')}</div>
          <p class="sec-foot" style="text-align:center;margin-top:18px">Each theme changes colours, type, shapes and patterns. More themes are on the way.</p>
        </div>`;
    },
    mount(el, params, entry) {
      Kit.wire(el, entry);
      el.querySelectorAll('[data-pick]').forEach((b) => b.addEventListener('click', () => {
        if (b.dataset.pick === App.getTheme().id) return;
        App.setTheme(b.dataset.pick);
        App.snack(`${App.getTheme().name} theme on`);
      }));
    },
  });
})();
