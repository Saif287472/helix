// Start the console once every screen has registered.
App.boot();

// The screenshot tool polls window.__consoleReady before taking a shot, so a
// picture is never taken before the fonts have swapped in or the page has
// painted. It only sets these two properties; it draws nothing.
(function markReady() {
  const INFO = { fonts: 'pending', frames: 'pending', scroll: 'none' };
  window.__consoleReady = false;
  window.__consoleReadyInfo = INFO;

  const wait = (ms) => new Promise((done) => setTimeout(done, ms));
  const frames = (n) => new Promise((done) => {
    const next = (left) => (left ? requestAnimationFrame(() => next(left - 1)) : done());
    next(n);
  });
  const within = (promise, ms) => Promise.race([promise.then(() => true, () => true), wait(ms).then(() => false)]);

  (document.fonts && document.fonts.ready ? within(document.fonts.ready, 4000) : Promise.resolve(true))
    .then((loaded) => {
      INFO.fonts = loaded ? 'loaded' : 'timeout';
      return within(frames(2), 500).then((painted) => { INFO.frames = painted ? 'painted' : 'not-painted'; });
    })
    .then(() => {
      const want = Number(new URLSearchParams(location.search).get('scroll')) || 0;
      if (!want) return;
      INFO.scroll = 'pending';
      const pages = document.querySelectorAll('#stack .page');
      const open = pages[pages.length - 1];
      const target = open && open.querySelector('.scroll');
      if (!target) { INFO.scroll = 'unreached'; return; }
      target.scrollTop = want;
      const poll = (until) => {
        if (target.scrollTop > 0) INFO.scroll = 'applied';
        else if (Date.now() < until) return wait(50).then(() => poll(until));
        else INFO.scroll = 'unreached';
      };
      return poll(Date.now() + 2000);
    })
    .then(() => { window.__consoleReady = true; });
})();
