// Start the prototype once every screen has registered.
App.boot();

// --------------------------------------------------------------- readiness
// The compare tool (orbit/flutter/tools/compare/shoot_html.py) drives headless
// Chrome over the DevTools protocol and polls window.__orbitReady, because
// Chrome can take a picture of this page before every script has run - the
// blank and unstyled screenshots Phase 1b hit. So the page has to say when it
// is genuinely ready, which means: the fonts have been swapped in, the first
// frame has been painted (best effort in a headless browser, see below), and a
// ?scroll= request has been applied (App.boot scrolls a beat later, so without
// that wait a shot at scroll=760 would be taken at 0, and the two halves of a
// comparison would not line up).
//
// This is additive: it sets two properties on window and reads the DOM. It
// adds no node, no class and no style, so it cannot change what a screen
// draws. It is also only ever observed by a screenshot tool; nothing in the
// prototype reads it.
(function markReady() {
  const INFO = { fonts: 'pending', frames: 'pending', scroll: 'none' };
  window.__orbitReady = false;
  window.__orbitReadyInfo = INFO;

  const wait = (ms) => new Promise((done) => setTimeout(done, ms));
  const frames = (n) => new Promise((done) => {
    const next = (left) => (left ? requestAnimationFrame(() => next(left - 1)) : done());
    next(n);
  });
  // A font CDN that never answers must not wedge a batch of 236 shots.
  const within = (promise, ms) => Promise.race([promise.then(() => true, () => true), wait(ms).then(() => false)]);

  (document.fonts && document.fonts.ready ? within(document.fonts.ready, 4000) : Promise.resolve(true))
    .then((loaded) => {
      INFO.fonts = loaded ? 'loaded' : 'timeout';
      // Headless Chrome does not run animation frames until something asks for
      // one, and the screenshot does, so waiting for a frame is best effort:
      // an unbounded wait here would hang the tool instead of the page.
      return within(frames(2), 500).then((painted) => { INFO.frames = painted ? 'painted' : 'not-painted'; });
    })
    .then(() => {
      const want = Number(new URLSearchParams(location.search).get('scroll')) || 0;
      if (!want) return;
      INFO.scroll = 'pending';
      // The scrollable elements App.boot scrolls: .scroll and .timeline.
      const scrolled = () => [...document.querySelectorAll('.scroll, .timeline')].some((el) => {
        const room = el.scrollHeight - el.clientHeight;
        return room > 0 && el.scrollTop >= Math.min(want, room);
      });
      // App.boot scrolls 120 ms after start, which can be before the theme's
      // fonts arrive; the page was shorter then, so the scroll stopped short
      // (seen with Papyrus). Ask again on the open page now that it is laid
      // out in its own fonts. Set it exactly even when it went past: the
      // browser's scroll anchoring moves a scrolled page down when the fonts
      // make the content above taller (seen with kit-shell, 20px).
      const pages = document.querySelectorAll('#stack .page');
      const open = pages[pages.length - 1];
      const target = open && open.querySelector('.scroll, .timeline');
      if (target) target.scrollTop = want;
      const poll = (until) => {
        if (scrolled()) INFO.scroll = 'applied';
        else if (Date.now() < until) return wait(50).then(() => poll(until));
        else INFO.scroll = 'unreached';
      };
      return poll(Date.now() + 2000);
    })
    .then(() => { window.__orbitReady = true; });
})();
