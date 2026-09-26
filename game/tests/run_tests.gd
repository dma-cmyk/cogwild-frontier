extends Node
## Headless test runner: loads res://tests/test_*.gd, runs every test_* method, prints a summary
## and quits with exit code 0 (all passed) or 1. User args after "--": --filter=<substring>.

func _ready() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr(9)
	var files := Array(DirAccess.get_files_at("res://tests"))
	files.sort()
	var total := 0
	var failed := 0
	var all_failures := PackedStringArray()
	var t0 := Time.get_ticks_msec()
	for f: String in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")) or f == "test_case.gd":
			continue
		if filter != "" and not f.contains(filter):
			continue
		var script: GDScript = load("res://tests/" + f)
		if script == null:
			all_failures.append("%s: failed to load" % f)
			failed += 1
			continue
		var case: TestCase = script.new()
		case.tree = get_tree()
		await case.before_all()
		for m: Dictionary in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			case.current_test = "%s::%s" % [f.get_basename(), name]
			var before := case.failures.size()
			var start := Time.get_ticks_msec()
			await case.call(name)
			var ok := case.failures.size() == before
			if not ok:
				failed += 1
			print("%s %s (%d ms)" % ["PASS" if ok else "FAIL", case.current_test, Time.get_ticks_msec() - start])
		await case.after_all()
		all_failures.append_array(case.failures)
	for msg in all_failures:
		printerr("  FAILURE ", msg)
	print("TESTS: %d run, %d failed, %.1f s" % [total, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit(1 if failed > 0 or total == 0 else 0)
