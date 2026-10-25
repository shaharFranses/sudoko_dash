import json,sys
sys.path.insert(0,'qa'); import sudoku_check as S
d=json.load(open(sys.argv[1])); bad=[]; inval=[]; nt=0; ntt=0
for b in d:
    n=int(len(b['grid'])**.5); sq=lambda a:[list(map(int,a[i*n:(i+1)*n])) for i in range(n)]
    g=sq(b['grid']); sol=sq(b['solution']); st=b['step']; T={c for c in b['target'] if b['grid'][c]==0}
    P=S.peers(n); rows,cols,boxes=S.units(n)
    cand={(r,c):set(range(1,n+1))-{g[a][e] for a,e in P[(r,c)]} for r in range(n) for c in range(n) if g[r][c]==0}
    # independent: does a T-touching single exist?
    tsingle=any(divmod(t,n) in cand and len(cand[divmod(t,n)])==1 for t in T)
    for u in rows+cols+boxes:
        for v in range(1,n+1):
            pl=[x for x in u if x in cand and v in cand[x]]
            if len(pl)==1 and pl[0][0]*n+pl[0][1] in T: tsingle=True
    cells=[int(c) for c in st.get('cells',[])]; el=st.get('eliminations',[])
    touches=(not el and st.get('value',0) and any(c in T for c in cells)) or any(int(e[0]) in T for e in el)
    # validity
    if not el and st.get('value',0):
        ok=all(sol[c//n][c%n]==int(st['value']) for c in cells)
    else:
        ok=all(sol[int(e[0])//n][int(e[0])%n]!=int(e[1]) for e in el)
    if not ok: inval.append((b['level'],st))
    if bool(touches)!=bool(st.get('touches_target')): bad.append(('flag mismatch',b['level']))
    if not touches and tsingle: bad.append(('T single existed but step off-T',b['level'],st['technique']))
    nt+=1; ntt+=bool(touches)
print(f"boards={nt} step_touches_T={ntt} invalid_steps={len(inval)} violations={len(bad)}")
for x in bad[:10]: print(x)
print(sys.argv[1], 'RESULT', 'PASS' if not bad and not inval else 'FAIL')
