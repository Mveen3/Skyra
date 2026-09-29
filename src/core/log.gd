# Implements §9.1 and §9.9 Logging system.
extends Node

enum Level { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }

var current_level: int = Level.INFO
var _log_file_path: String = "user://logs/skyra.log"
var _max_log_size: int = 1048576 # 1 MB

func _ready() -> void:
	_init_log_dir()

func _init_log_dir() -> void:
	var dir_path := _log_file_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

func set_level_from_string(lvl: String) -> void:
	match lvl.to_lower():
		"debug": current_level = Level.DEBUG
		"info": current_level = Level.INFO
		"warn", "warning": current_level = Level.WARN
		"error": current_level = Level.ERROR
		_: current_level = Level.INFO

func debug(msg: String) -> void:
	_log(Level.DEBUG, msg)

func info(msg: String) -> void:
	_log(Level.INFO, msg)

func warn(msg: String) -> void:
	_log(Level.WARN, msg)

func error(msg: String) -> void:
	_log(Level.ERROR, msg)

func _log(lvl: int, msg: String) -> void:
	if lvl < current_level:
		return
	
	var prefix: String
	match lvl:
		Level.DEBUG: prefix = "[DEBUG]"
		Level.INFO: prefix = "[INFO]"
		Level.WARN: prefix = "[WARN]"
		Level.ERROR: prefix = "[ERROR]"
		_: prefix = "[LOG]"
	
	var line: String = "%s %s" % [prefix, msg]
	if lvl == Level.ERROR:
		printerr(line)
	else:
		print(line)
	
	_write_to_file(line)

func _write_to_file(line: String) -> void:
	var real_path := ProjectSettings.globalize_path(_log_file_path)
	if FileAccess.file_exists(real_path):
		var fa := FileAccess.open(real_path, FileAccess.READ)
		if fa:
			var sz := fa.get_length()
			fa.close()
			if sz > _max_log_size:
				var backup_path := real_path + ".old"
				DirAccess.remove_absolute(backup_path)
				DirAccess.rename_absolute(real_path, backup_path)
	
	var fa := FileAccess.open(real_path, FileAccess.READ_WRITE)
	if not fa:
		fa = FileAccess.open(real_path, FileAccess.WRITE)
	if fa:
		fa.seek_end()
		fa.store_line(line)
		fa.close()
