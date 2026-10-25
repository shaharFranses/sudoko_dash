"""QA run7: validate qa/hint_memory.gd dump. Usage: python3 qa/check_hint_memory.py dump.json [--cli]
Per board (no digits placed between hints): every paid step valid (sudoku_check.validate_step, N3),
pairwise distinct, each brings new info (new placement cell, or >=1 never-shown elimination),
first 3 paid hints all different, no-new case -> free re-show of an unacted taught hint,
Digit Hunt: first hint places the hunted digit in T when such a single exists (independent check).
--cli also runs `sudoku_check.py --step` on the first 3 steps of every 9x9 board."""
import json, sys, subprocess, tempfile, os
sys.path.insert(0, 'qa'); import sudoku_check as S
d = json.load(open(sys.argv[1])); cli = '--cli' in sys.argv
fails = []; stats = dict(boards=0, b9=0, paid=0, ended=0, reshow_ok=0, hunt_boards=0, hunt_avail=0, hunt_first_ok=0, cli_runs=0, cli_ok=0)
def gs(st, n):
    if st['technique'] in ('naked_single', 'hidden_single'):
        c = int(st['cells'][0]); return {'cell': [c // n, c % n], 'value': int(st['value']), 'technique': st['technique']}
    return {'eliminations': [[int(e[0]) // n, int(e[0]) % n, int(e[1])] for e in st['eliminations']], 'technique': st['technique']}
for bi, b in enumerate(d):
    n = b['size']; sq = lambda a: [list(map(int, a[i*n:(i+1)*n])) for i in range(n)]
    g = sq(b['grid']); sol = sq(b['solution']); steps = b['steps']; tag = f"L{b['level']:02d}#{bi}"
    stats['boards'] += 1; stats['b9'] += n == 9; stats['paid'] += len(steps)
    if not b['cells_unchanged']: fails.append((tag, 'board changed'))
    seen_keys = set(); placed = set(); elims = set()
    for k, st in enumerate(steps):
        gst = gs(st, n)
        if not S.validate_step(g, sol, gst): fails.append((tag, k, 'invalid', st))
        key = json.dumps(gst, sort_keys=True)
        if key in seen_keys: fails.append((tag, k, 'repeat', st))
        seen_keys.add(key)
        if 'value' in gst:
            c = tuple(gst['cell'])
            if c in placed: fails.append((tag, k, 'placement cell re-taught'))
            placed.add(c)
        else:
            new = {tuple(e) for e in gst['eliminations']} - elims
            if not new: fails.append((tag, k, 'no new elimination'))
            elims |= {tuple(e) for e in gst['eliminations']}
        if cli and n == 9 and k < 3:
            with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as f:
                json.dump({'grid': g, 'solution': sol, 'game_step': {x: y for x, y in gst.items() if x != 'technique'}}, f)
            r = subprocess.run([sys.executable, 'qa/sudoku_check.py', '--step', f.name], capture_output=True, text=True); os.unlink(f.name)
            stats['cli_runs'] += 1; stats['cli_ok'] += r.returncode == 0
            if r.returncode != 0: fails.append((tag, k, 'cli --step invalid', r.stdout.strip()))
    if len(steps) >= 3 and len({json.dumps(gs(s, n), sort_keys=True) for s in steps[:3]}) != 3: fails.append((tag, 'first 3 not distinct'))
    if len(steps) < 3: fails.append((tag, f'fewer than 3 paid hints ({len(steps)})'))
    if not b['ended']: fails.append((tag, 'never reached no-new case in 200'))
    else:
        stats['ended'] += 1; r = b['reshow']
        ok = bool(r)  # main.gd shows active_hint (free); must be an unacted taught step
        if ok:
            ok = json.dumps(gs(r, n), sort_keys=True) in seen_keys
            if r['technique'] in ('naked_single', 'hidden_single'):
                c = int(r['cells'][0]); ok = ok and g[c // n][c % n] != int(r['value'])
        if ok: stats['reshow_ok'] += 1
        else: fails.append((tag, 'no-new case without a valid free re-show', r))
    if b['hunt']:
        stats['hunt_boards'] += 1; D = b['digit']; T = {c for c in b['target'] if b['grid'][c] == 0}
        P = S.peers(n); rows, cols, boxes = S.units(n)
        cand = {(r, c): set(range(1, n+1)) - {g[a][e] for a, e in P[(r, c)]} for r in range(n) for c in range(n) if g[r][c] == 0}
        avail = any(len(cand[divmod(t, n)]) == 1 for t in T)
        for u in rows + cols + boxes:
            pl = [x for x in u if x in cand and D in cand[x]]
            if len(pl) == 1 and pl[0][0]*n + pl[0][1] in T: avail = True
        if avail:
            stats['hunt_avail'] += 1; f0 = gs(steps[0], n) if steps else {}
            ok = 'value' in f0 and f0['value'] == D and f0['cell'][0]*n + f0['cell'][1] in T
            stats['hunt_first_ok'] += ok
            if not ok: fails.append((tag, 'hunt: first hint not a hunted-digit placement', steps[0] if steps else None))
print(json.dumps(stats))
for x in fails[:20]: print('FAIL', x)
print('violations', len(fails)); print('RESULT', 'PASS' if not fails else 'FAIL')
