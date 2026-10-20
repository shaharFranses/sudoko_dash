#!/bin/sh
# Expected exits: a b e w = 0 (valid), c f x = 1 (invalid); puzzles_sample = 1 (empty 4x4 is non-unique).
cd "$(dirname "$0")"; fail=0
for f in a:0 b:0 c:1 e:0 f:1 w:0 x:1; do n=${f%:*}; want=${f#*:}
  python3 sudoku_check.py --step fixtures/$n.json >/dev/null; got=$?
  [ "$got" = "$want" ] && echo "ok $n" || { echo "BAD $n got=$got want=$want"; fail=1; }; done
python3 sudoku_check.py fixtures/puzzles_sample.jsonl >/dev/null; [ $? = 1 ] && echo "ok jsonl" || fail=1
exit $fail
