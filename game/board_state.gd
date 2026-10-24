## State of one grid attempt: entries, notes, mistakes, unlimited undo. Pure logic (no Nodes).
extends RefCounted

const Shape = preload("res://sudoku/shape.gd")

var size: int
var shape
var givens: Array
var solution: Array
var cells: Array       # current digits (givens + player entries, wrong ones included)
var notes: Array       # bitmask per cell
var history: Array = []  # snapshots {cells, notes} for exact undo
var mistakes: int = 0
var max_mistakes: int = 3   # 0 = unlimited (4x4)
var second_chance_used: bool = false
var used_continue: bool = false
var any_mistake: bool = false
var reveals: int = 0
var failed: bool = false    # second mistake limit after Continue -> only Retry
var taught: Array = []      # Teach steps already given on this attempt: {technique, cells, value, eliminations, explanation}

func setup(p_size: int, p_givens: Array, p_solution: Array) -> void:
	size = p_size
	shape = Shape.of(size)
	givens = p_givens.duplicate()
	solution = p_solution.duplicate()
	max_mistakes = 0 if size == 4 else 3
	retry()

func retry() -> void:
	cells = givens.duplicate()
	notes = []
	notes.resize(cells.size())
	notes.fill(0)
	history = []
	mistakes = 0
	second_chance_used = false
	used_continue = false
	any_mistake = false
	reveals = 0
	failed = false
	taught = []

func is_given(i: int) -> bool:
	return givens[i] != 0

func snapshot() -> Dictionary:
	return {"cells": cells.duplicate(), "notes": notes.duplicate()}

func _push() -> void:
	history.append(snapshot())

func can_undo() -> bool:
	return history.size() > 0

func undo() -> bool:
	if history.is_empty(): return false
	var s: Dictionary = history.pop_back()
	cells = s.cells
	notes = s.notes
	return true

## Returns {"changed":bool, "mistake":bool, "limit_reached":bool}
func place(i: int, d: int) -> Dictionary:
	var r = {"changed": false, "mistake": false, "limit_reached": false}
	if is_given(i) or cells[i] == d or failed: return r
	_push()
	cells[i] = d
	notes[i] = 0
	r.changed = true
	if d != solution[i]:
		mistakes += 1
		any_mistake = true
		r.mistake = true
		if max_mistakes > 0 and mistakes >= max_mistakes:
			r.limit_reached = true
			if used_continue: failed = true
	else:
		var bit = 1 << (d - 1)
		for p in shape.peers[i]: notes[p] &= ~bit
	return r

func toggle_note(i: int, d: int) -> bool:
	if is_given(i) or cells[i] != 0 or failed: return false
	_push()
	notes[i] ^= 1 << (d - 1)
	return true

func erase(i: int) -> bool:
	if is_given(i) or (cells[i] == 0 and notes[i] == 0): return false
	_push()
	cells[i] = 0
	notes[i] = 0
	return true

func reveal(i: int) -> bool:
	if is_given(i) or cells[i] == solution[i]: return false
	_push()
	cells[i] = solution[i]
	notes[i] = 0
	var bit = 1 << (solution[i] - 1)
	for p in shape.peers[i]: notes[p] &= ~bit
	reveals += 1
	return true

func wrong_cells() -> Array:
	var out = []
	for i in cells.size():
		if cells[i] != 0 and cells[i] != solution[i]: out.append(i)
	return out

## Record a taught step (only the fields the hint engine / re-show need).
func add_taught(s: Dictionary) -> void:
	var el = []
	for e in s.get("eliminations", []): el.append([int(e[0]), int(e[1])])
	taught.append({"technique": str(s.technique), "cells": _ints(s.cells), "value": int(s.get("value", 0)),
		"eliminations": el, "explanation": str(s.get("explanation", ""))})

## The most recent taught step the player hasn't acted on yet ({} if none): a placement whose cell
## doesn't hold the taught digit, or an elimination step with an affected cell still unsolved.
func active_hint() -> Dictionary:
	for k in range(taught.size() - 1, -1, -1):
		var t: Dictionary = taught[k]
		if t.technique == "naked_single" or t.technique == "hidden_single":
			if cells[t.cells[0]] != t.value: return t
		else:
			for e in t.eliminations:
				if cells[e[0]] != solution[e[0]]: return t
	return {}

## Board for Teach: givens + correct player digits.
func correct_board() -> Array:
	var b = cells.duplicate()
	for i in b.size():
		if b[i] != solution[i]: b[i] = 0
	return b

func is_complete() -> bool:
	return cells == solution

## Second-chance Continue: reset mistakes, strip wrong digits from board and undo history.
func apply_continue() -> void:
	mistakes = 0
	second_chance_used = true
	used_continue = true
	for i in cells.size():
		if cells[i] != 0 and cells[i] != solution[i]: cells[i] = 0
	for s in history:
		for i in s.cells.size():
			if s.cells[i] != 0 and s.cells[i] != solution[i]: s.cells[i] = 0

func to_dict() -> Dictionary:
	return {"size": size, "givens": givens, "solution": solution, "cells": cells, "notes": notes,
		"history": history, "mistakes": mistakes, "second_chance_used": second_chance_used,
		"used_continue": used_continue, "any_mistake": any_mistake, "reveals": reveals, "failed": failed, "taught": taught}

func from_dict(d: Dictionary) -> void:
	size = int(d.size)
	shape = Shape.of(size)
	givens = _ints(d.givens); solution = _ints(d.solution); cells = _ints(d.cells); notes = _ints(d.notes)
	history = []
	for s in d.history: history.append({"cells": _ints(s.cells), "notes": _ints(s.notes)})
	max_mistakes = 0 if size == 4 else 3
	mistakes = int(d.mistakes); second_chance_used = bool(d.second_chance_used)
	used_continue = bool(d.used_continue); any_mistake = bool(d.any_mistake)
	reveals = int(d.reveals); failed = bool(d.failed)
	taught = []
	for t in d.get("taught", []):
		if t is Dictionary and t.has("technique") and t.has("cells"): add_taught(t)

static func _ints(a: Array) -> Array:
	var o = []
	for v in a: o.append(int(v))
	return o
