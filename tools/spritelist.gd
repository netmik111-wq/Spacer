extends SceneTree
## (v74) Writes dist_files/sprites/README.txt: what the «sprites» folder next to the game takes
## (see src/client/sprites.gd), every sheet and every thing's picture by name. Run after adding things:
##   godot --headless --path . --script res://tools/spritelist.gd

const Items := preload("res://src/shared/items.gd")
const Sprites := preload("res://src/client/sprites.gd")


func _initialize() -> void:
	var lines := PackedStringArray([
		"Свои картинки для Spacer (с версии 0.67)",
		"",
		"Любую картинку игры можно заменить своей. Положите в эту папку PNG-файл",
		"с нужным именем, и игра покажет его вместо своей. Чтобы вернуть картинку игры,",
		"уберите файл. Файлы читаются при запуске игры.",
		"",
		"Листы (размер должен совпадать с листом игры: игра режет из них кадры).",
		"Листы игры лежат рядом, в папке original: копируйте оттуда и рисуйте поверх.",
		"  body.png         (с 0.80) тело человека: 128x96, кадры 32x48 без рамки, по 4 в ряд:",
		"                   лицом (вниз), правым боком, спиной (вверх), левым боком. Верхний ряд —",
		"                   женщина, нижний — мужчина. Наискосок игра показывает бок. Тёмно-синюю",
		"                   одежду игра перекрашивает в цвет должности (и пиратов), так что рисуйте её",
		"                   тёмно-синей. Шагов пока нет: человек скользит стоя.",
		"  suit_man.png,    (с 0.81) человек в скафандре, мужчина и женщина: 96x192 каждый, кадры 32x48",
		"  suit_woman.png   без рамки, 3 в ряд, 4 ряда: спиной (один кадр); лицом: стекло, забрало",
		"                   наполовину, забрало опущено; левым боком и правым боком: забрало опущено,",
		"                   наполовину, стекло. Забрало опущено, пока человек дышит из баллона.",
		"                   Тёмно-синее игра тоже перекрашивает в цвет должности.",
		"  chars.png        боты-охранники, роботы и тяжёлые абордажники: 24 кадра по 34x50",
		"                   в ряд (32x48 и рамка 1 пиксель), по 3 кадра на сторону: вниз, вверх,",
		"                   влево, вправо, вниз-влево, вниз-вправо, вверх-влево, вверх-вправо;",
		"                   ряд на цвет и одежду (людей в нём игра больше не берёт; тяжёлых",
		"                   абордажников с 0.82 тоже: они в скафандре стального цвета)",
		"  tiles.png        стены, пол, двери, машины (32x32, 8 в ряд). С 0.83 нарисован из вашего",
		"                   набора тайлов; в конце листа — новые куски: двери четырёх видов с лампами",
		"                   и стадиями открытия, ставни окон, широкие пульты по частям, машины",
		"                   спиной. Лист 0.82 (старые картинки) лежит в папке old: игра его не берёт.",
		"  breach.png       пробоина в корпусе",
		"  hud_monitor.png  монитор здоровья в углу экрана",
		"  hud_alerts.png   лампы предупреждений",
		"  shuttle.png      (с 0.79) челнок флотилии сверху, носом вверх: 128x96 (4 на 3 клетки)",
		"  cursor_sight.png (с 0.82) прицел мыши с оружием в руке: до 128x128, выстрел идёт в середину",
		"",
		"Вещи: квадратная картинка любого размера (лучше 17x17, 34x34 или 68x68).",
		"Она видна в слотах, в шкафу, на полу и в руках у людей. Имена:",
	])
	var seen := {}
	var rows: Array = []
	for item: int in Items.INFO.keys():
		var key := Sprites.item_key(item)
		var name := Items.name_of(Items.kind_of(item))
		if seen.has(key) or name == "":
			continue
		seen[key] = true
		rows.append([Items.kind_of(item), key, name])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	for r: Array in rows:
		lines.append("  %-16s %s" % [str(r[1]) + ".png", r[2]])
	var f := FileAccess.open("res://dist_files/sprites/README.txt", FileAccess.WRITE)
	f.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
	f.store_string("\r\n".join(lines) + "\r\n")
	f.close()
	print("sprites README: %d things" % rows.size())
	quit(0)
