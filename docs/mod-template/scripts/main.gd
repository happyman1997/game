extends RefCounted
## Необязательный скрипт мода на GDScript. Удалите его и поле "scripts"
## в mod.json, если мод состоит только из данных.
##
## Движок вызывает init(api) один раз после загрузки контента всех модов.


func init(api: ModApi) -> void:
	# Новое значение для скриптов: сколько у персонажа соколов.
	api.value("falcons", {
		"scopes": ["character"],
		"doc": "Число соколов у персонажа",
		"get": func(ctx, scope, _arg):
			var c: Variant = ctx.game.ch(scope.id)
			return Data.num(c.vars.get("falcons")) if c != null else 0.0,
	})
	# Хук: сокольничие радуются удачной охоте.
	api.on("decision.taken", func(p: Dictionary):
		if p.decision != "train_falcon":
			return
		var c: Variant = p.game.ch(p.character)
		if c != null:
			c.vars["falcons"] = Data.num(c.vars.get("falcons")) + 1)
	api.log("my_mod загружен")
