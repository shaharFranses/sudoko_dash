#!/usr/bin/env python3
"""Sudoku Dash QA checker: solution counting (cap 2) + technique-based grader.
Input: JSONL, one puzzle per line: {"size":9,"tier":3,"seed":123,"givens":[[0,..],..],"solution":[[..]]}
(For 9x9 packs: convert data/packs/9x9_t{1-4}.json entries to this JSONL; "seed" may be the pack index.)
(0 = empty). Produce it from the Godot generator, e.g. a headless dump script:
  godot --headless -s res://qa/dump_puzzles.gd -- --n 100 > puzzles.jsonl
Usage: python3 sudoku_check.py puzzles.jsonl [--strict-tier]
Exit 0 only if every puzzle has exactly 1 solution, matches its solution, and grades to its tier.
Grader tiers (spec §1): 1 naked single, 2 hidden single, 3 naked/hidden pairs or pointing,
3 naked/hidden pair + pointing pair/triple, 4 naked/hidden triples,
box-line reduction or X-Wing (spec v3 §1, unchanged from v2 in substance).
--step BOARD.json: {"grid":[[..]], "givens":[[..]]?, "solution":[[..]]?, "game_step":{..}?}
  grid = current board (givens + player digits). Solution is computed from givens if omitted.
  - wrong player digits -> prints WRONG_DIGITS; game_step must be {"flag":[[r,c],..]} (flag and stop).
  - else prints the reference next step (placement or eliminations) and, if game_step is given
    ({"cell":[r,c],"value":v} or {"eliminations":[[r,c,v],..]}, 0-based), validates it:
    correct digit placed, or only non-solution candidates removed. Exit 0 = valid. (AC7/AC14) Returns 5 ("beyond") if those techniques stall.
"""
import json, sys
from itertools import combinations
BOX = {4: (2, 2), 6: (2, 3), 9: (3, 3)}

def units(n):
    br, bc = BOX[n]
    rows = [[(r, c) for c in range(n)] for r in range(n)]
    cols = [[(r, c) for r in range(n)] for c in range(n)]
    boxes = [[(r, c) for r in range(R, R + br) for c in range(C, C + bc)]
             for R in range(0, n, br) for C in range(0, n, bc)]
    return rows, cols, boxes

def peers(n):
    rows, cols, boxes = units(n); p = {}
    for u in rows + cols + boxes:
        for cell in u: p.setdefault(cell, set()).update(u)
    for k in p: p[k].discard(k)
    return p

def count_solutions(grid, cap=2):
    n = len(grid); g = [row[:] for row in grid]; P = peers(n); found = [0]
    def cands(r, c): return set(range(1, n + 1)) - {g[a][b] for a, b in P[(r, c)]}
    def rec():
        best = None
        for r in range(n):
            for c in range(n):
                if g[r][c] == 0:
                    cs = cands(r, c)
                    if best is None or len(cs) < len(best[2]): best = (r, c, cs)
        if best is None: found[0] += 1; return found[0] >= cap
        r, c, cs = best
        for v in cs:
            g[r][c] = v
            if rec(): return True
        g[r][c] = 0; return False
    rec(); return found[0]

def solve_one(grid):
    n = len(grid); g = [row[:] for row in grid]; P = peers(n)
    def rec():
        for r in range(n):
            for c in range(n):
                if g[r][c] == 0:
                    for v in set(range(1, n + 1)) - {g[a][b] for a, b in P[(r, c)]}:
                        g[r][c] = v
                        if rec(): return True
                    g[r][c] = 0; return False
        return True
    return g if rec() else None

def validate_step(grid, sol, st):
    """st = {"cell":[r,c],"value":v} (placement) or {"eliminations":[[r,c,v],..]} (0-based).
    Valid per v3 decision N3: places the correct digit into an empty cell, or removes only
    candidates that are not in the solution (and removes at least one)."""
    if "value" in st:
        r, c = st["cell"]; return grid[r][c] == 0 and sol[r][c] == st["value"]
    el = st.get("eliminations") or []
    return bool(el) and all(grid[r][c] == 0 and sol[r][c] != v for r, c, v in el)

def grade(grid, first=False):
    """first=True: stop at the first placement; return (tier_needed, (r, c, v))."""
    n = len(grid); rows, cols, boxes = units(n); allu = rows + cols + boxes; P = peers(n)
    g = [row[:] for row in grid]
    C = {(r, c): (set(range(1, n + 1)) - {g[a][b] for a, b in P[(r, c)]}) if g[r][c] == 0 else set()
         for r in range(n) for c in range(n)}
    placed = []
    def place(cell, v):
        placed.append((cell[0], cell[1], v))
        g[cell[0]][cell[1]] = v; C[cell] = set()
        for q in P[cell]: C[q].discard(v)
    def naked_single():
        for k, s in C.items():
            if len(s) == 1: place(k, next(iter(s))); return True
    def hidden_single():
        for u in allu:
            for v in range(1, n + 1):
                spots = [k for k in u if v in C[k]]
                if len(spots) == 1: place(spots[0], v); return True
    def subsets(size):
        ch = False
        for u in allu:
            empt = [k for k in u if C[k]]
            for combo in combinations(empt, size):  # naked subsets
                un = set().union(*(C[k] for k in combo))
                if len(un) == size:
                    for k in empt:
                        if k not in combo and C[k] & un: C[k] -= un; ch = True
            for vs in combinations(range(1, n + 1), size):  # hidden subsets
                spots = {k for k in empt if C[k] & set(vs)}
                if len(spots) == size and all(any(v in C[k] for k in spots) for v in vs):
                    for k in spots:
                        if C[k] - set(vs): C[k] &= set(vs); ch = True
        return ch
    def pointing():
        ch = False
        for b in boxes:
            for v in range(1, n + 1):
                spots = [k for k in b if v in C[k]]
                if not spots: continue
                for line in rows + cols:
                    if all(k in line for k in spots):
                        for k in line:
                            if k not in b and v in C[k]: C[k].discard(v); ch = True
        return ch
    def boxline():
        ch = False
        for line in rows + cols:  # box/line reduction (tier 4 in spec v2)
            for v in range(1, n + 1):
                spots = [k for k in line if v in C[k]]
                for b in boxes:
                    if spots and all(k in b for k in spots):
                        for k in b:
                            if k not in line and v in C[k]: C[k].discard(v); ch = True
        return ch
    def xwing():
        ch = False
        for v in range(1, n + 1):
            for A, B in ((rows, 1), (cols, 0)):
                pos = [(i, {k[B] for k in u if v in C[k]}) for i, u in enumerate(A)]
                pos = [p for p in pos if len(p[1]) == 2]
                for (i, s), (j, t) in combinations(pos, 2):
                    if s == t:
                        for k, cs in C.items():
                            other = k[1 - B]
                            if k[B] in s and other not in (i, j) and v in cs: cs.discard(v); ch = True
        return ch
    tier = 0
    steps = [(1, naked_single), (2, hidden_single), (3, lambda: subsets(2) or pointing()),
             (4, lambda: boxline() or subsets(3) or xwing())]
    while any(g[r][c] == 0 for r in range(n) for c in range(n)):
        for t, fn in steps:
            snap = {k: set(v) for k, v in C.items()} if first else None
            if fn(): tier = max(tier, t); break
        else: return 5, (None if first else g)
        if first:
            if placed: return tier, ("place", placed[0])
            el = [(k[0], k[1], v) for k in snap for v in snap[k] - C[k]]
            if el: return tier, ("elim", el)
    return tier, (None if first else g)

def main():
    if sys.argv[1] == "--step":
        b = json.load(open(sys.argv[2])); grid = b["grid"]; n = len(grid)
        givens = b.get("givens") or grid
        sol = b.get("solution") or solve_one(givens)
        wrong = [(r, c) for r in range(n) for c in range(n) if grid[r][c] and grid[r][c] != sol[r][c]]
        if wrong:
            # v3 decision N2: Teach must flag the wrong digit(s) and stop.
            print("WRONG_DIGITS " + " ".join(f"r{r+1}c{c+1}" for r, c in wrong)
                  + " expected_teach=FLAG_AND_STOP")
            gs = b.get("game_step")
            if gs is None: sys.exit(0)
            ok = gs.get("flag") is not None and sorted(map(tuple, [gs["flag"]] if isinstance(gs["flag"][0], int) else gs["flag"])) == sorted(wrong)
            print(f"GAME_STEP flagged_correctly={ok}"); sys.exit(0 if ok else 1)
        t, mv = grade(grid, first=True)
        if mv is None: print(f"NO_STEP tier={t}")
        elif mv[0] == "place":
            r, c, v = mv[1]; print(f"REF_STEP place r{r+1}c{c+1}={v} tier_needed={t} valid={validate_step(grid, sol, {'cell':[r,c],'value':v})}")
        else:
            print(f"REF_STEP eliminate {len(mv[1])} candidate(s) tier_needed={t} valid={validate_step(grid, sol, {'eliminations':mv[1]})}")
        gs = b.get("game_step")
        if gs is not None:
            ok = validate_step(grid, sol, gs)
            print(f"GAME_STEP technique={gs.get('technique')} valid={ok}"); sys.exit(0 if ok else 1)
        sys.exit(0 if mv is not None else 1)
    path = sys.argv[1]; fails = 0; total = 0; by = {}
    for line in open(path):
        if not line.strip(): continue
        p = json.loads(line); total += 1
        cnt = count_solutions(p["givens"]); t, solved = grade(p["givens"])
        ok = cnt == 1 and t == p["tier"] and (not p.get("solution") or solved == p["solution"] or t == 5)
        key = (p["size"], p["tier"]); by.setdefault(key, [0, 0]); by[key][0] += 1; by[key][1] += ok
        if not ok:
            fails += 1
            print(f"FAIL size={p['size']} seed={p.get('seed')} req_tier={p['tier']} solutions={cnt} graded={t}")
    for (s, t), (n_, ok) in sorted(by.items()): print(f"size {s} tier {t}: {ok}/{n_} pass")
    print(f"TOTAL {total - fails}/{total} {'PASS' if fails == 0 else 'FAIL'}")
    sys.exit(1 if fails else 0)

if __name__ == "__main__":
    main()
