import io, re

p = 'css/console.css'
s = io.open(p, encoding='utf-8').read()

# 1. the old header + dock block (replaced by css/shell.css)
start = s.index('/* ---- Orbit-style header')
end = s.index('/* ================= Page furniture ================= */')
s = s[:start] + s[end:]

# 2. its phone counterparts inside the container query
for frag in [
    '  .topbar { min-height: 58px; padding: 9px 16px 5px; gap: 8px; }\n',
    '  .wordmark { font-size: 22px; }\n',
    '  .server-chip { height: 30px; padding: 0 10px; gap: 7px; }\n',
    '  .tb-server { font-size: 11.5px; }\n',
    '  .topnav { display: none; }\n',
]:
    assert frag in s, frag
    s = s.replace(frag, '')

tab_start = s.index('  .tabbar {\n    display: flex; position: absolute;')
tab_end = s.index('  .pg-head { padding: 14px 16px 10px; }')
s = s[:tab_start] + s[tab_end:]

# 3. .app is now a row: rail + column (shell.css owns the direction)
s = s.replace('  display: flex; flex-direction: column; min-width: 0; min-height: 0;\n  background: var(--bg); overflow: hidden;',
              '  display: flex; flex-direction: row; min-width: 0; min-height: 0;\n  background: var(--bg); overflow: hidden;')
s = s.replace('.app .stack { position: relative; inset: auto; flex: 1 1 auto; min-height: 0; overflow: hidden; }\n', '')
s = s.replace('.app.auth .topbar, .app.auth .tabbar { display: none !important; }',
              '.app.auth .rail, .app.auth .tabbar, .app.auth .mstrip { display: none !important; }\n.app.auth .stack { flex: 1; }')

io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('console.css rewritten:', len(s.splitlines()), 'lines')
