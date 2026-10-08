class_name UiRegistry
extends RefCounted
## Реестр расширений интерфейса. Живёт в движке (без зависимостей от сцен),
## чтобы моды могли регистрировать элементы UI из своих скриптов.
## Интерфейс читает эти реестры при отрисовке.
##
## Режим карты: {id, name, icon?, order?, color: Callable(game, prov_id) -> Color|String|null,
##   legend?: Callable(game) -> Array[{color, label}], tooltip?: Callable(game, prov_id) -> String}
## Панель мода (кнопка внизу): {id, name, icon, order?, render: Callable(game, ui) -> Control}
## Раздел окна персонажа/провинции: {id, title, order?, render: Callable(game, id, ui) -> Control}
## Виджет верхней панели: {id, order?, render: Callable(game) -> {icon?, text, tooltip?} | null}
## Оповещение: {id, order?, check: Callable(game) -> {icon, text, kind?, action?} | Array | null}
##   action: {tab?, character?, title?, province?}

var map_modes := Registry.new("режим карты")
var panels := Registry.new("панель")
var character_sections := Registry.new("раздел персонажа")
var province_sections := Registry.new("раздел провинции")
var top_bar := Registry.new("виджет")
var alerts := Registry.new("оповещение")
## Иконки тем событий: theme → {icon, color}.
var event_themes := Registry.new("тема события")
