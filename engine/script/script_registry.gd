class_name ScriptRegistry
extends RefCounted
## Реестры скриптового языка. Встроенные триггеры/эффекты регистрируются
## так же, как и моддерские — мод может добавить новый или переопределить
## существующий.
##
## Определения — словари с Callable:
##   триггер:  {scopes?, doc?, eval: (ctx, scope, arg) -> bool, describe?: (ctx, scope, arg) -> String}
##   эффект:   {scopes?, doc?, apply: (ctx, scope, arg) -> void, describe?: (ctx, scope, arg) -> String|Array|null}
##   значение: {scopes?, doc?, get: (ctx, scope, arg_scope) -> float}
##   ссылка:   {from?, to?, doc?, resolve: (ctx, scope) -> Dictionary|null}
##   список:   {from?, to?, doc?, list: (ctx, scope) -> Array}

var triggers := Registry.new("триггер")
var effects := Registry.new("эффект")
var values := Registry.new("значение")
var links := Registry.new("ссылка на скоуп")
var lists := Registry.new("список")
var constants := Registry.new("константа")
