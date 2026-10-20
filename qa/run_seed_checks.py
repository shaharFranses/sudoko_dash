#!/usr/bin/env python3
"""Run1 helper: convert export_puzzles.gd format=json output to sudoku_check JSONL (tier = REQUESTED tier),
check that the game's own grade equals the requested tier, and feed the game's first_step (step(givens))
to sudoku_check.py --step. Usage: run_seed_checks.py <dir with s{size}_t{tier}.json>"""
import json, glob, os, subprocess, sys, re
d = sys.argv[1]; here = os.path.dirname(os.path.abspath(__file__)); summ = []
for f in sorted(glob.glob(f"{d}/s*_t*.json")):
    size, req = map(int, re.findall(r"s(\d+)_t(\d+)", f)[0]); L = json.load(open(f)); n = size
    g = lambda a: [a[i*n:(i+1)*n] for i in range(n)]
    base = f[:-5]
    with open(base + ".jsonl", "w") as o:
        for p in L: o.write(json.dumps({"size": n, "tier": req, "seed": p["seed"], "givens": g(p["givens"]), "solution": g(p["solution"])}) + "\n")
    r = subprocess.run([sys.executable, f"{here}/sudoku_check.py", base + ".jsonl"], capture_output=True, text=True)
    open(base + ".check.txt", "w").write(r.stdout)
    game_bad = [p["seed"] for p in L if p["tier"] != req or p["solution_count"] != 1]
    step_bad = []; os.makedirs(base + "_steps", exist_ok=True)
    for p in L:
        fs = p["first_step"]
        if fs["technique"] in ("naked_single", "hidden_single"):
            c = fs["cells"][0]; gs = {"technique": fs["technique"], "cell": [c // n, c % n], "value": fs["value"]}
        else:
            gs = {"technique": fs["technique"], "eliminations": [[e[0] // n, e[0] % n, e[1]] if isinstance(e, list) else [e["cell"] // n, e["cell"] % n, e["value"]] for e in fs["eliminations"]]}
        bf = f"{base}_steps/{p['seed']}.json"; json.dump({"grid": g(p["givens"]), "solution": g(p["solution"]), "game_step": gs}, open(bf, "w"))
        s = subprocess.run([sys.executable, f"{here}/sudoku_check.py", "--step", bf], capture_output=True, text=True)
        if s.returncode: step_bad.append((p["seed"], s.stdout.strip()))
    line = f"size {size} tier {req}: n={len(L)} checker[{r.stdout.strip().splitlines()[-1]}] game_grade_or_count_mismatch={len(game_bad)} teach_step_invalid={len(step_bad)}"
    summ.append(line); print(line)
    for b in step_bad[:5]: print("   step FAIL seed", b)
    if game_bad: print("   game mismatch seeds", game_bad[:10])
open(f"{d}/SUMMARY.txt", "w").write("\n".join(summ) + "\n")
