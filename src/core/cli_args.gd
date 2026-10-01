# Implements §9.9 CLI argument parsing.
class_name CliArgs
extends RefCounted

var autostart: bool = false
var mode: StringName = &"mini_post"
var bots: int = 5
var duration: int = 7
var rng_seed: int = 0
var has_seed: bool = false
var selftest: bool = false
var test_filter: String = ""
var run_script: String = ""
var drive: String = ""
var soak: int = 0
var gen_sfx: bool = false
var bench: bool = false
var bench_s: int = 30
var windowed: bool = false
var log_level: String = "info"

static func parse() -> CliArgs:
	var args := CliArgs.new()
	var raw_args := OS.get_cmdline_user_args()
	if raw_args.is_empty():
		var all_args := OS.get_cmdline_args()
		var found_sep := false
		for a in all_args:
			if found_sep:
				raw_args.append(a)
			elif a == "--":
				found_sep = true
	
	for a in raw_args:
		if a == "--autostart":
			args.autostart = true
		elif a == "--selftest":
			args.selftest = true
		elif a == "--gen-sfx":
			args.gen_sfx = true
		elif a == "--bench":
			args.bench = true
		elif a.begins_with("--bench="):
			args.bench = true
			args.bench_s = maxi(1, a.substr(8).to_int())
		elif a == "--windowed":
			args.windowed = true
		elif a.begins_with("--mode="):
			args.mode = StringName(a.substr(7))
		elif a.begins_with("--bots="):
			args.bots = a.substr(7).to_int()
		elif a.begins_with("--duration="):
			args.duration = a.substr(11).to_int()
		elif a.begins_with("--seed="):
			args.rng_seed = a.substr(7).to_int()
			args.has_seed = true
		elif a.begins_with("--soak="):
			args.soak = a.substr(7).to_int()
		elif a.begins_with("--log-level="):
			args.log_level = a.substr(12)
		elif a.begins_with("--only="):
			args.test_filter = a.substr(7)
		elif a.begins_with("--run-script="):
			args.run_script = a.substr(13)
		elif a.begins_with("--drive="):
			args.drive = a.substr(8)
			
	return args
