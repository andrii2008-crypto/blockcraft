extends RefCounted
# Простейший журнал: пишет шаги в файл, чтобы после вылета можно было увидеть, где всё оборвалось.

const PATH := "user://run.log"


static func start() -> String:
	var prev := ""
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			prev = f.get_as_text()
			f.close()
	var w := FileAccess.open(PATH, FileAccess.WRITE)
	if w != null:
		w.store_line("--- new run ---")
		w.close()
	return prev


static func put(msg: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%d %s" % [Time.get_ticks_msec(), msg])
	f.close()
