class_name TestCase
extends RefCounted
## Base class for headless tests. Files named res://tests/test_*.gd extend this; every method whose
## name starts with "test_" runs once. Methods may be coroutines (await is allowed).
## Run all:   godot --headless --path game res://tests/run_tests.tscn
## Filter:    godot --headless --path game res://tests/run_tests.tscn -- --filter=world

var failures: PackedStringArray = PackedStringArray()
var current_test := ""
## SceneTree for tests that need nodes or frames (set by the runner).
var tree: SceneTree


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current_test, msg])


func assert_true(cond: bool, msg: String = "expected true") -> bool:
	if not cond:
		fail(msg)
	return cond


func assert_false(cond: bool, msg: String = "expected false") -> bool:
	return assert_true(not cond, msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> bool:
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("%s expected %s, got %s" % [msg, str(expected), str(actual)])
		return false
	return true


func assert_ne(actual: Variant, other: Variant, msg: String = "") -> bool:
	if typeof(actual) == typeof(other) and actual == other:
		fail("%s expected values to differ, both %s" % [msg, str(actual)])
		return false
	return true


func assert_between(value: float, lo: float, hi: float, msg: String = "") -> bool:
	if value < lo or value > hi or is_nan(value):
		fail("%s expected %s in [%s, %s]" % [msg, str(value), str(lo), str(hi)])
		return false
	return true


## Optional per-file hooks.
func before_all() -> void:
	pass


func after_all() -> void:
	pass
