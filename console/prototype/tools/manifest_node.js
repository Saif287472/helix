// Prints the prototype's manifest (App.manifest()) as JSON, without a browser.
//
// It runs the same scripts index.html loads, in order, in a Node sandbox with
// a permissive stand-in for the browser. Screens only register at load time,
// so nothing needs to draw. tools/manifest.py runs this:
//   node tools/manifest_node.js > manifest.json
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.dirname(__dirname);
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const scripts = [...html.matchAll(/<script src="(js\/[^"]+)"><\/script>/g)].map((m) => m[1]).filter((s) => !s.endsWith('boot.js'));

// A browser stand-in that accepts any property, call or construction.
const stub = () => new Proxy(function () {}, {
  get: (t, k) => (k === Symbol.toPrimitive ? () => '' : k === 'length' ? 0 : stub()),
  apply: () => stub(),
  construct: () => stub(),
});
const sandbox = {
  console, setTimeout: () => 0, clearTimeout() {}, setInterval: () => 0, clearInterval() {},
  requestAnimationFrame: () => 0, document: stub(), location: stub(), history: stub(), navigator: stub(),
  localStorage: { getItem: () => null, setItem() {} }, matchMedia: () => ({ matches: false }),
  CSS: { escape: (s) => String(s) }, PointerEvent: function () {}, CustomEvent: function () {}, Event: function () {},
};
sandbox.window = sandbox;
vm.createContext(sandbox);
for (const s of scripts) vm.runInContext(fs.readFileSync(path.join(root, s), 'utf8'), sandbox, { filename: s });
process.stdout.write(JSON.stringify(vm.runInContext('App.manifest()', sandbox)));
