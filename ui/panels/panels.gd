class_name Panels
extends RefCounted
## Содержимое левого окна по ссылке {kind, id}: заголовок и тело.


static func build(app: App, ref: Dictionary) -> Dictionary:
	var g := app.game
	var title := ""
	var body: Control = null
	match ref.kind:
		"character":
			title = app.t("ui.tab.character")
			body = CharacterPanel.build(app, ref.id)
		"province":
			title = app.t("ui.province")
			body = ProvincePanel.build(app, ref.id)
		"title":
			title = app.t("ui.title")
			body = ProvincePanel.build_title(app, ref.id)
		"army":
			title = app.t("ui.army")
			body = MilitaryPanel.build_army(app, ref.id)
		"tab":
			title = app.hud.tab_name(ref.id) if app.hud != null else ""
			if g.player == null and ref.id != "pick":
				body = K.label(app.t("ui.pick_character_hint"), "MutedLabel")
			else:
				match ref.id:
					"pick":
						title = app.t("ui.pick_title")
						body = TabPanels.pick(app)
					"lifestyle": body = LifestylePanel.build(app)
					"realm": body = TabPanels.realm(app)
					"military": body = MilitaryPanel.build(app)
					"wars": body = WarsPanel.build(app)
					"intrigue": body = TabPanels.intrigue(app)
					"decisions": body = TabPanels.decisions(app)
					"log": body = TabPanels.log(app)
					_:
						if str(ref.id).begins_with("mod:"):
							var spec: Variant = g.engine.ui.panels.get_item(str(ref.id).substr(4))
							var r: Variant = spec.render.call(g, app) if spec != null else null
							if r is String:
								body = K.rich(r)
							elif r is Control:
								body = r
	if body == null:
		body = K.label("—", "MutedLabel")
	return {"title": title, "body": body}
