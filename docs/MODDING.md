# Руководство по созданию модов

«Корона и Династия» построена так, что **весь игровой контент — это моды**.
Даже базовая игра (карта Британии и Франции 1066 года, черты, события,
решения) — это обычный мод `mods/core`, который можно изменить, дополнить
или целиком заменить своим.

Есть три уровня моддинга — от простого к сложному:

| Уровень | Что нужно уметь | Что можно сделать |
|---|---|---|
| **Данные** (YAML/JSON) | Редактировать текстовые файлы | Черты, культуры, карта, персонажи, события, решения, взаимодействия, войны, интриги, постройки, законы, режимы карты, баланс |
| **Скриптовый язык** в данных | Логика «если — то» | Условия и последствия событий, решений, взаимодействий; формулы шансов и согласия ИИ |
| **JS-скрипты** | JavaScript | Новые механики (системы симуляции), новые триггеры/эффекты для скриптов, алгоритмы наследования, типы войн, режимы карты, панели и виджеты интерфейса |

Готовые примеры:

- [`mods/tournaments`](../mods/tournaments) — мод **без кода**: новые черты, постройка, решение с цепочкой событий, режим карты и правки чужого контента директивами слияния;
- [`mods/plague`](../mods/plague) — **JS-мод**: собственный тип контента `diseases`, система эпидемий, триггеры и эффекты для скриптов, режим карты, виджет, панель;
- [`mods/elective_monarchy`](../mods/elective_monarchy) — **расширение реестра**: новый алгоритм наследования (выборы вассалами);
- [`docs/mod-template`](mod-template) — заготовка: скопируйте в `mods/` и переименуйте.

---

## 1. Быстрый старт

1. Создайте папку `mods/my_mod/`.
2. Положите в неё `mod.json`:

   ```json
   {
     "id": "my_mod",
     "name": { "ru": "Мой мод", "en": "My mod" },
     "version": "1.0.0",
     "dependencies": ["core"]
   }
   ```

3. Создайте `mods/my_mod/data/traits.yaml`:

   ```yaml
   traits:
     falconer:
       category: lifestyle
       icon: "🦅"
       modifiers: { prowess: 1, monthly_prestige: 0.2 }
   ```

4. И перевод `mods/my_mod/localization/ru/my_mod.yaml`:

   ```yaml
   trait:
     falconer: Сокольничий
   trait_desc:
     falconer: Знаток соколиной охоты.
   ```

5. Запустите `npm run validate` — он проверит синтаксис и ссылки.
6. Запустите игру (`npm run dev`) — мод появится в меню «Моды» и будет включён.

Чтобы попробовать мод **без пересборки**, в меню «Моды» нажмите
«Загрузить папку мода…» и выберите папку (работает до перезагрузки страницы).

---

## 2. Файл `mod.json`

| Поле | Описание |
|---|---|
| `id` | Уникальный идентификатор (латиница). |
| `name`, `description` | Строка или `{ "ru": "...", "en": "..." }`. |
| `version`, `author`, `tags` | Для менеджера модов и сохранений. |
| `dependencies` | Моды, без которых этот не работает. Грузятся раньше. Если зависимости нет — мод отключается с понятной ошибкой. |
| `load_after` | «Мягкий» порядок: если указанные моды включены, грузиться после них. |
| `priority` | При прочих равных меньше — раньше (у `core` = −100). |
| `data` | Папки с данными, по умолчанию `["data"]`. Вложенность любая. |
| `localization` | Папка локализации, по умолчанию `localization`. |
| `scripts` | JS/TS-скрипты, экспортирующие `init(api)`. |
| `default_enabled` | `false` — мод выключен, пока игрок не включит его вручную. |

---

## 3. Файлы данных

Каждый файл в папке `data/` (в любых подпапках, YAML или JSON) — это словарь
**«тип контента → { id → определение }»**. В одном файле можно смешивать типы:

```yaml
traits:
  falconer: { category: lifestyle, icon: "🦅" }

decisions:
  train_falcon:
    icon: "🦅"
    cost: { gold: 30 }
    effect: { add_trait: falconer }
```

Файлы читаются в алфавитном порядке, моды — в порядке загрузки.
Если ключ уже определён ранее (в другом файле или моде), записи **сливаются**.

### Слияние и директивы

| Что написано в моде | Что получится |
|---|---|
| Объект | Рекурсивное слияние: меняются только указанные поля. |
| Массив или значение | Замена. |
| `{ $replace: true, ... }` | Объект заменяется целиком. |
| `{ $delete: true }` | Запись (или поле) удаляется. |
| `{ $append: [...] }` | Элементы добавляются в конец списка. |
| `{ $prepend: [...] }` | Элементы добавляются в начало списка. |
| `{ $remove: [...] }` | Элементы удаляются из списка (по значению или по `id`). |

Примеры:

```yaml
traits:
  brave:
    modifiers: { prowess: 4 }       # остальные модификаторы храброго сохранятся

decisions:
  seek_solitude: { $delete: true }  # убрать решение из основной игры

on_actions:
  on_death:
    effect:
      $append:                      # дописать эффект к чужому on_action
        - add_dynasty_prestige: -5
  on_monthly_pulse:
    random_events:
      events:
        my_mod.0001: 10             # словари сливаются — событие добавится в пул

cultures:
  english:
    male_names: { $append: [Hereward] }
```

`defines` и `map` — особые «одиночные» типы: это не коллекция, а один объект,
который тоже сливается рекурсивно. Чтобы поменять одну константу:

```yaml
defines:
  military:
    battle_prestige: 30
```

Полный список констант — в [`mods/core/data/common/defines.yaml`](../mods/core/data/common/defines.yaml).

---

## 4. Типы контента

| Тип | Где пример | Кратко |
|---|---|---|
| `defines` | `core/data/common/defines.yaml` | Числовые константы экономики, армии, демографии, ИИ. |
| `skills` | `core/data/common/skills.yaml` | Навыки. Новый навык автоматически становится значением в скриптах. |
| `traits` | `core/data/common/traits.yaml` | Черты: `category`, `icon`, `modifiers`, `opposites`, `compatibility`, `genetic`/`birth_chance`/`inherit_chance`, `education`, `ai`, `monthly_death_chance`, `monthly_cure_chance`, `duration_days`, `group`. |
| `cultures` | `core/data/common/cultures.yaml` | `color`, `male_names`, `female_names`, `dynasty_pattern` (`name`/`place`), `succession_law`, `skin`/`hair`, `modifiers`. |
| `faiths` | там же | `religion`, `color`, `icon`, `doctrines` (`polygamy`), `virtues`, `sins`, `modifiers`. |
| `terrain`, `holdings`, `buildings` | `core/data/common/economy.yaml` | Местность (оборона, скорость, высота рельефа), владения (налог, ополчение, крепость), постройки (`holding`, `requires`, `cost`, `days`, `modifiers`, `owner_modifiers`, `trigger`). |
| `map`, `landmasses`, `provinces`, `map_links` | `core/data/map/` | Карта — см. раздел 7. |
| `titles` | `core/data/map/titles.yaml` | Иерархия де-юре: `tier`, `liege`, `color`, `capital`, `coa` (герб), `no_create`. Графства создаются из провинций автоматически. |
| `dynasties`, `characters`, `bookmarks` | `core/data/history/` | Исторические персонажи и стартовые даты. |
| `succession_laws` | `core/data/common/laws_and_modifiers.yaml` | `algorithm` (`partition`, `primogeniture`, `seniority` или свой из JS), `gender`, `change_cost`, `can_change`. |
| `opinion_modifiers`, `modifiers` | там же | Модификаторы мнения (`value`, `decay`, `years`, `stacking`) и временные модификаторы персонажей/провинций. |
| `casus_belli` | `core/data/common/war.yaml` | Поводы к войне: `targets` (поставщик целей), `is_valid`, `cost`, `on_victory`, `on_white_peace`, `on_defeat`, `ai_will_do`, `truce_years`, `war_name`. |
| `interactions` | `core/data/common/interactions.yaml` | Взаимодействия персонажей (см. раздел 6). |
| `schemes` | `core/data/common/schemes.yaml` | Интриги: `progress`, `success_chance`, `discovery_chance`, `on_success`, `on_failure`, `on_discovered`. |
| `decisions` | `core/data/common/decisions.yaml` | `is_shown`, `is_valid`, `cost`, `effect`, `cooldown`, `major`, `ai_will_do`, `ai_check_months`. |
| `events`, `on_actions` | `core/data/events/`, `core/data/common/on_actions.yaml` | События и точки их вызова — раздел 5. |
| `script_values`, `scripted_triggers`, `scripted_effects` | `core/data/common/decisions.yaml` | Именованные формулы и блоки скрипта для повторного использования. |
| `event_themes`, `map_modes` | `core/data/common/ui.yaml` | Оформление событий; режимы карты без кода (значение + градиент). |
| **любой свой тип** | `plague/data/plague.yaml` (`diseases`) | Движок сохранит его; читайте из JS: `api.content.all('diseases')`. |

Подробные комментарии есть прямо в файлах мода `core` — это лучший справочник по полям.

---

## 5. События и on_actions

```yaml
events:
  my_mod.0001:
    theme: court                  # цвет и значок окна (event_themes)
    icon: "🎻"
    trigger: { is_ruler: yes, gold: 20 }
    weight: { value: 10, add: { value: diplomacy, multiply: 2 } }
    cooldown: { years: 5 }        # или once: true
    immediate:                    # выполняется до показа окна
      random_courtier: { save_scope_as: minstrel }
    options:
      - effect: { add_gold: -20, add_prestige: 30 }
        ai_chance: { value: 50, add: { value: ai_sociability, multiply: 10 } }
      - trigger: { has_trait: greedy }   # вариант виден только жадным
        effect: { add_stress: -10 }
      - effect: {}
    after: {}                     # выполняется после выбора
```

Тексты по умолчанию берутся из локализации: `ev.<id>.t` (заголовок),
`ev.<id>.desc` (описание), `ev.<id>.a`, `.b`, `.c`… (варианты). Можно задать
явно: `title:`, `desc:`, `name:` у варианта — ключом локализации, прямым текстом
или `{ ru: ..., en: ... }`. Описание может зависеть от условий:

```yaml
    desc:
      - trigger: { has_trait: brave }
        desc: ev.my_mod.0001.desc_brave
      - desc: ev.my_mod.0001.desc
```

`hidden: true` — событие без окна (только эффекты), `triggered_only: true` —
пометка, что событие вызывается только из других событий/решений.

Вызвать событие: эффект `trigger_event: my_mod.0001` или
`trigger_event: { id: my_mod.0001, days: 30 }`. Сохранённые скоупы передаются в событие.

**on_actions** — места, где движок обращается к контенту. Каждый может иметь
`effect`, список `events` (вызываются все) и `random_events` (одно случайное по весам,
с шансом `chance` в процентах):

| on_action | Корневой персонаж (root) | Доп. скоупы |
|---|---|---|
| `on_game_start` | каждый правитель при создании мира | |
| `on_player_start` | игрок, выбравший персонажа | |
| `on_monthly_pulse` / `on_yearly_pulse` | каждый правитель | |
| `on_birth` | новорождённый | `scope:mother`, `scope:father` |
| `on_death` | умерший (до наследования) | `scope:killer` |
| `on_marriage` | супруг | `scope:spouse` |
| `on_pregnancy` | мать | `scope:father` |
| `on_coming_of_age` | достигший совершеннолетия | |
| `on_title_gained` | получивший титул | `scope:title` |
| `on_inheritance` | наследник | `scope:predecessor` |
| `on_player_succession` | новый персонаж игрока | `scope:predecessor` |
| `on_war_started` / `on_war_ended` | нападающий | `scope:attacker`, `scope:defender`, `scope:target` |
| `on_battle_won` / `on_battle_lost` | владелец армии | `scope:enemy` |
| `on_stress_level` | персонаж, чей стресс перешёл новую сотню | |

---

## 6. Скриптовый язык

Скрипты — это YAML-блоки трёх видов: **триггеры** (условия), **эффекты**
(действия) и **значения** (числа). Полный список всего, что есть в движке и
включённых модах, — в [`docs/SCRIPT_REFERENCE.md`](SCRIPT_REFERENCE.md)
(генерируется командой `npm run docs:script`).

### Скоупы

Скрипт всегда выполняется «в скоупе» — для персонажа, титула, провинции и т.п.

- `root` — корневой объект (персонаж события, инициатор взаимодействия…);
- `this` — текущий скоуп, `prev` — предыдущий;
- `scope:имя` — сохранённый скоуп (`save_scope_as: имя`, а также готовые:
  `scope:actor`, `scope:recipient`, `scope:target`, `scope:attacker`…);
- ссылки: `liege`, `top_liege`, `father`, `mother`, `spouse`, `primary_heir`,
  `primary_title`, `capital`, `holder`, `county`, `de_jure_liege`…;
- пути через точку: `scope:actor.liege.primary_title`;
- прямые ссылки: `title:k_england`, `character:william`, `province:c_london`.

### Триггеры

```yaml
trigger:
  is_adult: yes                     # да/нет
  has_trait: [brave, zealous]       # любая из черт
  gold: 100                         # число = «не меньше»
  age: ">= 16"                      # сравнение строкой (в кавычках!)
  prestige: { gte: 100, lt: 500 }   # или объектом: gte, gt, lte, lt, eq, ne
  martial: "> scope:recipient.martial"
  tier: ">= duchy"                  # константы county=1 … empire=4
  liege: { has_trait: brave }       # условие для другого скоупа
  any_vassal: { has_trait: craven, count: ">= 2" }
  OR: [ { culture: english }, { culture: norman } ]
  NOT: { is_at_war: yes }
  NOR: [ ... ]
  custom_tooltip: { text: my_mod.need_x, trigger: { gold: 500 } }
```

`custom_tooltip` задаёт понятный игроку текст, если условие не выполнено.

### Эффекты

```yaml
effect:
  - add_gold: 50
  - add_trait: brave
  - add_opinion: { target: scope:recipient, modifier: gift }
  - if:
      limit: { gold: "< 0" }
      then: { add_prestige: -10 }
      else_if: [ { limit: { gold: "> 1000" }, then: { add_prestige: 20 } } ]
      else: { add_stress: -5 }
  - random: { chance: 30, add_trait: wounded }
  - random_list:
      - { weight: 60, add_prestige: 40 }
      - { weight: 40, add_trait: wounded }
  - every_vassal:
      limit: { is_at_war: no }
      add_opinion: { target: root, modifier: feast_guest }
  - random_courtier: { limit: { is_adult: yes }, save_scope_as: knight }
  - ordered_child: { order_by: martial, add_skill: { skill: martial, value: 2 } }
  - scope:knight: { add_trait: knight_errant }
  - trigger_event: { id: my_mod.0002, days: 10 }
  - hidden_effect: { set_flag: secret }   # не показывается в подсказке
  - custom_tooltip: my_mod.something_happens
```

Порядок эффектов сохраняется. Если в одном объекте нужно повторить ключ —
используйте список (как выше), в YAML ключи объекта уникальны.

### Значения (формулы)

```yaml
ai_accept:
  value: -10
  add:
    - { desc: ai.opinion, value: { value: "opinion(scope:actor)", multiply: 0.5 } }
    - { desc: ai.same_culture, limit: { same_culture_as: scope:actor }, value: 10 }
  multiply: 1.2
  if:
    - limit: { has_trait: ambitious }
      add: -20
  min: -100
  max: 100
  round: yes
```

Операции выполняются по порядку ключей: `value`/`base`, `add`, `subtract`,
`multiply`, `divide`, `if`, `min` (нижняя граница), `max` (верхняя), `round`,
`floor`, `ceil`, `abs`. Слагаемые с `desc` показываются игроку в подсказке
(«Согласится: +12 — Мнение +8, Та же культура +10…»).

Можно ссылаться на значения по пути (`scope:actor.gold`), на переменные
(`var:my_counter`, `global_var:x`), на константы (`defines.military.speed`)
и на именованные формулы из `script_values`.

### Тексты

В строках локализации доступны подстановки из контекста скрипта:

```yaml
ev:
  my_mod.0001:
    desc: "[scope:minstrel.first_name] поёт о подвигах [root.dynasty_name]. [scope:minstrel|g:Он/Она] ждёт награды."
```

Свойства: `name`, `first_name`, `full_name`, `title_name`, `rank`,
`culture_name`, `faith_name`, `dynasty_name`, `age`. `|g:муж/жен` выбирает
вариант по полу. `{name}` в фигурных скобках — параметры, которые передаёт код.

### Взаимодействия

```yaml
interactions:
  ask_for_blessing:
    icon: "🙏"
    category: friendly
    is_shown: { scope:recipient: { has_trait: zealous } }
    is_valid: { scope:actor: { piety: 50 } }
    cost: { piety: 50 }
    decider: recipient                 # или guardian — решает сюзерен безземельного получателя
    secondary_actor: { list: [child, courtier], trigger: { is_adult: no } }   # выбор из семьи
    target: { provider: grantable_titles }                                     # выбор титула
    ai_accept: { value: 0, add: [ { desc: ai.opinion, value: "opinion(scope:actor)" } ] }
    on_accept: { scope:actor: { add_modifier: { id: blessed, years: 2 } } }
    on_decline: {}
    ai_targets: [liege, vassal]        # кого рассматривает ИИ
    ai_frequency_months: 12
    ai_will_do: 30
    cooldown: { years: 1 }
    # scheme: murder                   # вместо on_accept — запустить интригу
```

---

## 7. Карта

Карта строится из данных — рисовать границы не нужно.

```yaml
map:
  width: 1000                                 # ширина растра в пикселях
  bounds: { lon: [-11, 6.5], lat: [44.3, 59.6] }
  ref_lat: 52                                 # широта для поправки проекции
  border_noise: 0.9                           # «извилистость» границ
  coast_roughness: 0.28                       # «изрезанность» берегов

landmasses:                                   # контуры суши: [широта, долгота]
  my_island:
    points: [[50.1, -5.1], [50.3, -4.8], [50.0, -4.6]]
    # pixel: true — если точки заданы в пикселях, roughness: 0 — без изломов

provinces:
  c_my_county:
    lat: 50.15                                # «зерно» провинции (или pos: [x, y] в пикселях)
    lon: -4.9
    duchy: d_cornwall                         # де-юре герцогство
    terrain: hills
    culture: english
    faith: catholic
    development: 5
    holdings: [castle, temple]
  w_far_lands: { lat: 45, lon: 6, impassable: true }  # непроходимая окраина

map_links:                                    # морские переправы
  my_ferry: { a: c_my_county, b: c_leon }
```

Провинции «прорастают» по суше от своих зёрен, поэтому, чтобы **добавить
провинцию**, достаточно одной строки. Графство-титул создаётся автоматически
(название — ключ локализации с id провинции).

Проверить результат: `npx tsx tools/render-map.ts screenshots/my-map.png` —
утилита нарисует растр провинций и сообщит о провинциях без соседей.

---

## 8. Локализация

Файлы лежат в `localization/<язык>/*.yaml`. Вложенные ключи склеиваются через точку.

| Что | Ключ |
|---|---|
| Название записи | `<тип в ед. числе>.<id>`: `trait.brave`, `culture.norman`, `decision.hold_feast`, `building.walls`, `casus_belli.claim`… или просто `<id>` (титулы и провинции: `k_england`, `c_london`) |
| Описание | `<тип>_desc.<id>`: `trait_desc.brave`, `decision_desc.hold_feast` |
| Полное название титула | `<id>_full` (иначе «Королевство Англия» из `tier.kingdom` + `k_england`) |
| Титул правителя | `<id>_rank_m` / `<id>_rank_f`, или для культуры: `rank.<культура>.<ранг>.m` |
| Имена персонажей | `name.<Имя>` (если перевода нет — показывается само имя) |
| Династии | `dynasty.<id>`; шаблон новых династий — `dynasty_pattern.<культура>` |
| Тексты событий | `ev.<id>.t`, `ev.<id>.desc`, `ev.<id>.a`… |

Вместо ключа почти везде можно написать текст прямо в данных:
`name: { ru: "Сокольничий", en: "Falconer" }`.

Строки интерфейса движка лежат в `src/locale/`; мод может переопределить любую
из них, просто указав тот же ключ в своих файлах.

---

## 9. JS-моды

Скрипт мода — ES-модуль, указанный в `mod.json` → `scripts`. Он экспортирует
`init(api)` (вызывается после загрузки всех данных) и, при необходимости,
`preload(api)` (вызывается до разбора данных этого мода — например, чтобы
зарегистрировать новый формат файлов).

```js
export function init(api) {
  // 1. Скриптовый язык
  api.script.trigger('is_falconer', { scopes: ['character'], eval: (ctx, scope) => ctx.game.char(scope.id).traits.includes('falconer') });
  api.script.effect('release_falcon', {
    apply: (ctx, scope, arg) => { ctx.game.char(scope.id).prestige += Number(arg) || 10; },
    describe: (ctx, scope, arg) => `+${arg} престижа за сокола`,
  });
  api.script.value('falcons_owned', { get: (ctx, scope) => ctx.game.char(scope.id).vars.falcons ?? 0 });

  // 2. Системы симуляции (вызываются каждый день/месяц/год)
  api.systems.add({ id: 'falconry', order: 100, onMonth(game) { /* ... */ } });
  api.systems.replace('development', { onYear(game) { /* свой рост развития */ } });
  // api.systems.remove('ai');  — отключить встроенную систему целиком

  // 3. Хуки
  api.hooks.on('character.death', ({ game, character, reason }) => { /* ... */ });
  api.hooks.on('war.before_declare', ({ attacker }) => attacker.gold > 0); // false — запретить

  // 4. Реестры
  api.registries.successionAlgorithms.register('my_law', { heirs(game, ruler, law) { return []; } });
  api.registries.cbTargets.register('my_cb_targets', { targets(game, attacker) { return []; } });
  api.registries.modifierProviders.register('my_bonus', { fn: (game, c) => ({ diplomacy: 1 }) });
  api.registries.opinionProviders.register('my_opinion', { fn: (game, a, b) => ({ label: 'Соколы', value: 5 }) });

  // 5. Интерфейс
  api.ui.mapModes.register('falcons', { id: 'falcons', name: { ru: 'Соколы' }, icon: '🦅', color: (game, prov) => '#aa8844' });
  api.ui.topBar.register('falcons', { id: 'falcons', render: (game) => ({ icon: '🦅', text: '3' }) });
  api.ui.panels.register('falcons', { id: 'falcons', name: 'Соколиная охота', icon: '🦅', render: (game, ui) => '<p>HTML</p>' });
  api.ui.characterSections.register('falcons', { id: 'falcons', title: 'Соколы', render: (game, charId) => '...' });
  api.ui.provinceSections.register('falcons', { id: 'falcons', title: 'Соколы', render: (game, provId) => '...' });
}
```

### Что есть в `api`

| Поле | Назначение |
|---|---|
| `api.content` | Хранилище контента: `get(type, id)`, `all(type)`, `ids(type)`, `set`, `delete`, `singleton('defines')`. |
| `api.loc` | Локализация: `t(key, params)`, `add(lang, entries)`. |
| `api.script` | Регистрация `trigger`, `effect`, `value`, `link`, `list`, `constant` + функции интерпретатора (`evalTrigger`, `runEffect`, `evalValue`, `makeContext`…). |
| `api.systems` | `add`, `replace`, `remove`, `get`, `list`. |
| `api.hooks` | `on(name, fn, priority)`. |
| `api.registries` | `successionAlgorithms`, `cbTargets`, `interactionTargets`, `modifierProviders`, `provinceModifierProviders`, `opinionProviders`. |
| `api.ui` | `mapModes`, `panels`, `characterSections`, `provinceSections`, `topBar`, `eventThemes`. |
| `api.world` | Функции мира: `characters` (createCharacter, addTrait, marry…), `titles` (transferTitle, topLiege…), `succession` (killCharacter, heirsOf…), `war` (declareWar, endWar…), `military`, `economy`, `opinion`, `stats`, `interactions`, `schemes`, `decisions`, `ai`. |
| `api.util` | `Rng`, `hashString`, даты, `deepMerge`, шум `fbm`. |

Используйте функции из `api.world`, а не меняйте состояние напрямую: они
поддерживают индексы и вызывают хуки. Если всё же меняете `liege`/`titles`
вручную — вызовите `game.markDirty()`.

**Сохранения.** Всё состояние партии — обычный JSON (`game.state`). Данные мода
храните в `game.modData('my_mod', () => начальное значение)` — они попадут в
сохранение автоматически.

### Хуки

| Хук | Данные | Особенность |
|---|---|---|
| `engine.ready` | `engine` | все моды загружены |
| `game.setup`, `game.loaded`, `game.before_save` | `game` | |
| `day` | `game` | после каждого дня |
| `player.selected`, `player.succession`, `game.over` | | |
| `character.before_death` | `character`, `reason` | **veto**: вернуть `false`, чтобы отменить смерть |
| `character.death`, `character.birth`, `character.marriage` | | |
| `character.trait_added`, `character.trait_removed`, `character.liege_changed` | | |
| `title.transferred`, `succession` | | |
| `title.create`, `title.usurp` | | **veto** |
| `war.before_declare` | `attacker`, `target` | **veto** |
| `war.declared`, `war.ended`, `battle`, `siege.won` | | |
| `army.raised`, `army.disbanded` | | |
| `event.before_fire` | `event`, `target` | **veto** |
| `event.fired`, `event.player` | | |
| `interaction.before` | | **veto** |
| `interaction`, `decision.taken`, `decision.before` (veto) | | |
| `scheme.started`, `scheme.discovered`, `scheme.ended` | | |
| `building.started`, `building.completed` | | |
| `ai.think` | `character` | **veto**: вернуть `false`, чтобы ИИ этого персонажа пропустил ход |
| `economy.income` | `character` | **collect**: верните `{ label, value }`, чтобы добавить статью дохода |
| `on_action.<id>` | `root`, `scopes` | после каждого on_action |

---

## 10. Полная замена контента (total conversion)

Отключите `core` в менеджере модов и включите свой мод. Минимальный набор для
запуска партии:

- `skills`, `traits` (хотя бы личностные), `cultures`, `faiths`, `terrain`, `holdings`;
- `map` + `landmasses` + `provinces` + `titles`;
- `succession_laws`;
- `bookmarks` (дата и владельцы титулов; недостающих правителей движок сгенерирует сам).

Строки интерфейса движка уже встроены (`src/locale`), а всё остальное
(события, решения, войны, интриги) — по желанию.

---

## 11. Инструменты

| Команда | Что делает |
|---|---|
| `npm run dev` | Игра с горячей перезагрузкой: правьте YAML — обновите страницу. |
| `npm run validate` | Проверка всех модов: синтаксис, зависимости, ссылки, неизвестные ключи скриптов, пробный запуск закладок, расхождения локализаций. |
| `npm run sim -- --years 50 --seed 1 --verbose` | Безголовая симуляция: войны, смерти, статистика — для баланса. `--mods core,my_mod` — выбрать моды. |
| `npm run docs:script` | Пересобрать `docs/SCRIPT_REFERENCE.md` (с учётом ваших модов). |
| `npx tsx tools/render-map.ts out.png` | Картинка растра провинций. |
| `npm test` | Автотесты движка. |
