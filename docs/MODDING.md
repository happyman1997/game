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
| **Скрипты на GDScript** | GDScript (язык Godot, похож на Python) | Новые механики (системы симуляции), новые триггеры/эффекты для скриптов, алгоритмы наследования, типы войн, режимы карты, панели и виджеты интерфейса |

Готовые примеры:

- [`mods/tournaments`](../mods/tournaments) — мод **без кода**: новые черты, постройка, решение с цепочкой событий, режим карты и правки чужого контента директивами слияния;
- [`mods/plague`](../mods/plague) — **мод со скриптом на GDScript**: собственный тип контента `diseases`, система эпидемий, триггеры и эффекты для скриптов, режим карты, виджет, панель;
- [`mods/elective_monarchy`](../mods/elective_monarchy) — **расширение реестра**: новый алгоритм наследования (выборы вассалами);
- [`docs/mod-template`](mod-template) — заготовка: скопируйте в папку модов и переименуйте.

---

## 1. Быстрый старт

1. Создайте папку `my_mod` в папке модов игрока — «Документы/Crown and Dynasty/mods»
   (или в `mods/` проекта, если работаете с исходниками).
2. Положите в неё `mod.json`:

   ```json
   {
     "id": "my_mod",
     "name": { "ru": "Мой мод", "en": "My mod" },
     "version": "1.0.0",
     "dependencies": ["core"]
   }
   ```

3. Создайте `my_mod/data/traits.yaml`:

   ```yaml
   traits:
     falconer:
       category: lifestyle
       icon: "🦅"
       modifiers: { prowess: 1, monthly_prestige: 0.2 }
   ```

4. И перевод `my_mod/localization/ru/my_mod.yaml`:

   ```yaml
   trait:
     falconer: Сокольничий
   trait_desc:
     falconer: Знаток соколиной охоты.
   ```

5. Запустите игру — мод появится в меню «Моды» и будет включён (новые моды,
   появившиеся в папке, включаются сами; выключенные вами остаются выключенными). Если правите
   файлы при открытой игре, нажмите в менеджере модов «Обновить список» и
   «Применить» — контент перезагрузится без перезапуска.
6. Проблемы (опечатки в YAML, ссылки на несуществующие черты, неизвестные ключи
   скриптов) видны в главном меню («Проблемы модов») или через
   `godot --headless --path . -s tools/validate.gd` (см. раздел 12).

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
| `scripts` | Скрипты на GDScript (`.gd`) с функцией `init(api)`. |
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
| `skills` | `core/data/common/skills.yaml` | Навыки. Новый навык автоматически становится значением в скриптах. `mean`/`spread` — среднее и разброс при рождении (по умолчанию 6 и 5; историческим персонажам без указанного навыка — на 1 выше), `inherit_spread` — разброс вокруг среднего родителей, `hide_if_zero` — не показывать нулевой навык (редкий дар вроде чародейства). |
| `traits` | `core/data/common/traits.yaml` | Черты: `category`, `icon`, `modifiers`, `opposites`, `compatibility`, `genetic`/`birth_chance`/`inherit_chance`, `education`, `ai`, `monthly_death_chance`, `monthly_cure_chance`, `duration_days`, `group`, `color` (цвет плашки), `concealed` (скрытая черта — см. «Крюки и секреты»), `portrait` (как черта меняет портрет — см. ниже). |
| `cultures` | `core/data/common/cultures.yaml` | `color`, `male_names`, `female_names`, `dynasty_pattern` (`name`/`place`), `succession_law`, `skin`/`hair`, `modifiers`. |
| `faiths` | там же | `religion`, `color`, `icon`, `doctrines` (`polygamy`), `virtues`, `sins`, `modifiers`. |
| `terrain`, `holdings`, `buildings` | `core/data/common/economy.yaml` | Местность (оборона, скорость, высота рельефа), владения (налог, ополчение, крепость), постройки (`holding`, `requires`, `cost`, `days`, `modifiers`, `owner_modifiers`, `trigger`). |
| `map`, `landmasses`, `provinces`, `map_links` | `core/data/map/` | Карта — см. раздел 7. |
| `titles` | `core/data/map/titles.yaml` | Иерархия де-юре: `tier`, `liege`, `color`, `capital`, `coa` (герб), `no_create`. Графства создаются из провинций автоматически. |
| `dynasties`, `characters`, `bookmarks` | `core/data/history/` | Исторические персонажи и стартовые даты. |
| `succession_laws` | `core/data/common/laws_and_modifiers.yaml` | `algorithm` (`partition`, `primogeniture`, `seniority` или свой из скрипта мода), `gender`, `change_cost`, `can_change`. |
| `opinion_modifiers`, `modifiers` | там же | Модификаторы мнения (`value`, `decay`, `years`, `stacking`) и временные модификаторы персонажей/провинций. |
| `casus_belli` | `core/data/common/war.yaml` | Поводы к войне: `targets` (поставщик целей), `is_valid`, `cost`, `on_victory`, `on_white_peace`, `on_defeat`, `ai_will_do`, `truce_years`, `war_name`, `manual` (не предлагать игроку и ИИ — только для скриптов, например мятежей). |
| `interactions` | `core/data/common/interactions.yaml` | Взаимодействия персонажей (см. раздел 6). |
| `schemes` | `core/data/common/schemes.yaml` | Интриги: `progress`, `success_chance`, `discovery_chance`, `on_success`, `on_failure`, `on_discovered`. |
| `decisions` | `core/data/common/decisions.yaml` | `is_shown`, `is_valid`, `cost`, `effect`, `cooldown`, `major`, `ai_will_do`, `ai_check_months`. |
| `events`, `on_actions` | `core/data/events/`, `core/data/common/on_actions.yaml` | События и точки их вызова — раздел 5. |
| `script_values`, `scripted_triggers`, `scripted_effects` | `core/data/common/decisions.yaml` | Именованные формулы и блоки скрипта для повторного использования. |
| `event_themes`, `map_modes` | `core/data/common/ui.yaml` | Оформление событий; режимы карты без кода (значение + градиент). |
| `lifestyles`, `focuses`, `perks` | `core/data/common/lifestyles.yaml` | Образ жизни: фокусы и деревья перков — раздел 10. |
| `council_positions`, `council_tasks` | `core/data/common/council.yaml` | Совет: должности и задачи — раздел 10. |
| `factions` | `core/data/common/factions.yaml` | Фракции вассалов и их мятежи — раздел 10. |
| `regiment_types` | `core/data/common/regiments.yaml` | Профессиональные войска — раздел 10. |
| **любой свой тип** | `plague/data/plague.yaml` (`diseases`) | Движок сохранит его; читайте из скрипта: `api.content.all("diseases")`. |

Подробные комментарии есть прямо в файлах мода `core` — это лучший справочник по полям.

**Вид на портрете.** Черта может менять процедурный портрет (только видимая
зрителю черта — тайный вампир выглядит как все, пока его тайна не раскрыта):

```yaml
traits:
  vampire:
    portrait:
      skin: "#e2d8de"      # оттенок кожи...
      skin_amount: 0.55    # ...и насколько он перекрывает родной (0–1)
      pale: true           # без румянца
      eyes: "#a01018"      # цвет радужки
      glow: "#ff3030"      # свечение глаз
      fangs: true          # клыки
      ageless: 33          # видимый возраст не старше
      # ещё: undead (пустые глазницы, оскал), aura (сияние за головой), hood (капюшон),
      # marks (светящиеся руны), hair (цвет волос), no_hair
```

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

Мод может завести и **свой** on_action: опишите его в `on_actions` и вызывайте
из скрипта `game.on_action("on_arcane_pulse", {"type": "character", "id": c.id})` (так мод `arcana`
раз в несколько лет устраивает правителям «мистический» пульс событий) — другие
моды смогут добавлять туда свои события обычным слиянием (`events: { $append: [...] }`).

---

## 6. Скриптовый язык

Скрипты — это YAML-блоки трёх видов: **триггеры** (условия), **эффекты**
(действия) и **значения** (числа). Полный список всего, что есть в движке и
включённых модах, — в [`docs/SCRIPT_REFERENCE.md`](SCRIPT_REFERENCE.md)
(генерируется командой `godot --headless --path . -s tools/script_docs.gd`).

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
  width: 1400                                 # ширина растра в пикселях
  bounds: { lon: [-11, 19.5], lat: [44.3, 64.5] }
  ref_lat: 54                                 # широта для поправки проекции
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

Регион удобно описывать отдельным файлом — так устроена Скандинавия в
`core/data/map/scandinavia.yaml`: контуры суши, графства, титулы, переправы,
непроходимые земли и даже решение «Норвежское вторжение» в одном файле, а
персонажи и владельцы — в `core/data/history/scandinavia_1066.yaml` (закладка
дополняется слиянием: `playable: { $append: [...] }`, `holders: {...}`).
Если область карты расширяется (`bounds`), заселите новые земли зёрнами
провинций или непроходимыми окраинами (`impassable: true`), иначе их
захватят ближайшие провинции.

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

Строки интерфейса движка лежат в `locale/`; мод может переопределить любую
из них, просто указав тот же ключ в своих файлах.

---

## 9. Скрипты на GDScript

Скрипт мода — файл `.gd`, указанный в `mod.json` → `scripts`. Это обычный
класс GDScript (`extends RefCounted`) с функцией `init(api: ModApi)`, которую
движок вызывает после загрузки данных всех модов. Необязательная
`preload_mod(info)` вызывается раньше — до разбора данных этого мода
(например, чтобы зарегистрировать новый формат файлов в `info.formats`).

Весь движок — это классы GDScript с глобальными именами (`Game`, `Chars`,
`Titles`, `Succession`, `Wars`, `Military`, `Economy`, `Opinion`, `Stats`,
`Interactions`, `Schemes`, `Decisions`, `Ai`, механики `Lifestyles`,
`Council`, `Prison`, `Factions`, `Regiments`, `Secrets`, `Laws`, `Knights`),
поэтому скрипт мода может пользоваться любой функцией мира напрямую.

```gdscript
extends RefCounted


func init(api: ModApi) -> void:
	# 1. Скриптовый язык
	api.trigger("is_falconer", {"scopes": ["character"], "doc": "Сокольничий",
		"eval": func(ctx, scope, _arg): return ctx.game.ch(scope.id).traits.has("falconer")})
	api.effect("release_falcon", {
		"apply": func(ctx, scope, arg): ctx.game.ch(scope.id).prestige += Data.num(arg, 10),
		"describe": func(_ctx, _scope, arg): return "+%s престижа за сокола" % arg,
	})
	api.value("falcons_owned", {"get": func(ctx, scope, _arg): return Data.num(ctx.game.ch(scope.id).vars.get("falcons"))})

	# 2. Системы симуляции (on_day / on_month / on_year / on_character_month)
	api.add_system({"id": "falconry", "order": 100,
		"on_character_month": func(game: Game, c: Dictionary): pass})  # каждый персонаж — в свой день месяца
	api.replace_system("development", {"on_year": func(game: Game): pass})  # своё развитие
	# api.remove_system("ai")  — отключить встроенную систему целиком

	# 3. Хуки: в обработчик приходит словарь данных (в нём всегда есть game)
	api.on("character.death", func(p: Dictionary): print(p.character.id, " умер: ", p.reason))
	api.on("war.before_declare", func(p: Dictionary): return p.attacker.gold > 0)  # false — запретить

	# 4. Реестры мира
	api.registries.succession_algorithms.register("my_law", {"heirs": func(game, ruler, law): return []}, api.owner)
	api.registries.cb_targets.register("my_cb_targets", {"targets": func(game, attacker): return []}, api.owner)
	api.registries.modifier_providers.register("my_bonus", {"fn": func(game, c): return {"diplomacy": 1}}, api.owner)
	api.registries.opinion_providers.register("my_opinion", {"fn": func(game, a, b): return {"label": "Соколы", "value": 5}}, api.owner)

	# 5. Интерфейс
	api.ui.map_modes.register("falcons", {"id": "falcons", "name": {"ru": "Соколы", "en": "Falcons"}, "icon": "🦅",
		"color": func(game: Game, prov: String): return "#aa8844"})
	api.ui.top_bar.register("falcons", {"id": "falcons", "render": func(game: Game): return {"icon": "🦅", "text": "3"}})
	api.ui.panels.register("falcons", {"id": "falcons", "name": "Соколиная охота", "icon": "🦅",
		"render": func(game: Game, ui) -> Control:
			var l := Label.new()
			l.text = "Соколов при дворе: 3"
			return l})
	api.ui.character_sections.register("falcons", {"id": "falcons", "title": "Соколы",
		"render": func(game: Game, char_id: String, ui): return "[b]3[/b] сокола"})  # BBCode или Control
	api.ui.province_sections.register("falcons", {"id": "falcons", "title": "Соколы",
		"render": func(game: Game, prov_id: String, ui): return null})
```

Иконки интерфейса: можно указать эмодзи (`"🦅"`) или имя встроенной
нарисованной иконки (`"crown"`, `"swords"`, `"castle"`…, полный список —
`ui/art/icons.gd`); свою иконку добавляет `Icons.register("falcon", "<svg-тело 24×24>")`.
Панель мода получает `ui` — объект приложения: `ui.open_character(id)`,
`ui.open_province(id, true)`, `ui.open_tab(id)`, `ui.toast(text)`.

### Что есть в `api`

| Поле / метод | Назначение |
|---|---|
| `api.owner` | id мода (им помечаются зарегистрированные элементы). |
| `api.content` | Хранилище контента: `get_def(type, id)`, `all(type)`, `ids(type)`, `has`, `set_def`, `remove`, `singleton("defines")`. |
| `api.loc` | Локализация: `t(key, params)`, `add(lang, entries)`. |
| `api.trigger`, `api.effect`, `api.value`, `api.link`, `api.list`, `api.constant` | Регистрация элементов скриптового языка. Интерпретатор — класс `Interp` (`eval_trigger`, `run_effect`, `eval_value`), контекст — `ScriptContext.make(game, root, scopes)`. |
| `api.add_system`, `api.replace_system`, `api.remove_system`, `api.get_system`, `api.list_systems` | Системы симуляции. |
| `api.on(name, fn, priority)`, `api.emit` | Хуки. |
| `api.registries` | `succession_algorithms`, `cb_targets`, `interaction_targets`, `interaction_deciders`, `modifier_providers`, `province_modifier_providers`, `opinion_providers`, `content_validators`. Поставщик модификаторов возвращает словарь или массив `[{label, modifiers}]`; `label` может быть `Callable() -> String` — подпись считается только для подсказки (характеристики пересчитываются часто). |
| `api.add_feature`, `api.has_feature`, `api.list_features` | Механики; `EngineFeature.eval_modifiers(ctx, scope, mods)` — модификаторы со скриптовыми значениями. |
| `api.ui` | `map_modes`, `panels`, `character_sections`, `province_sections`, `top_bar`, `alerts`, `event_themes`. |
| `api.formats` | Форматы файлов данных (YAML, JSON и свои). |
| `api.log(msg)` | Сообщение в консоль с именем мода. |

Используйте функции мира (`Chars.add_trait`, `Titles.transfer_title`,
`Succession.kill_character`, `Wars.declare_war`…), а не меняйте состояние
напрямую: они поддерживают индексы и вызывают хуки. Если всё же меняете
`liege`/`titles` вручную — вызовите `game.mark_dirty()` (сброс всех кэшей)
или дешевле — `game.mark_chars_dirty([id, ...])` для затронутых персонажей.

**Сохранения.** Всё состояние партии — обычные словари (`game.state`),
сохранение — это их JSON. Данные мода храните в
`game.mod_data("my_mod", func(): return {начальное значение})` — они попадут в
сохранение автоматически.

**Ошибки.** Ошибка в скрипте мода прерывает только текущий вызов (хук,
систему, отрисовку) и пишется в консоль; игра продолжается.

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
| `war.score` | `war` | **collect**: верните `{ label, value }` (или массив) — слагаемое счёта войны (плюс — в пользу нападающих) |
| `army.power_bonus` | `army`, `enemies`, `location` | **collect**: число — прибавка к силе армии в бою и в оценках ИИ |
| `military.strength_bonus` | `character` | **collect**: прибавка к «военной силе» для решений ИИ о войне |
| `battle.commander_survived` | `war`, `commander`, `captor` | полководец проигравших выжил (механика темницы берёт его в плен) |
| `perk.gained`, `lifestyle.focus_changed` | `character`, `perk`/`focus` | |
| `council.appointed`, `council.dismissed`, `council.task_fired` | `liege`, `position`, … | |
| `prison.before_imprison` | `jailer`, `prisoner`, `reason` | **veto** |
| `prison.imprisoned`, `prison.released` | `prisoner`, `jailer`, `reason` | |
| `faction.created`, `faction.joined`, `faction.left`, `faction.dissolved`, `faction.ultimatum` | `faction`, … | |
| `regiment.recruited` | `character`, `regiment` | |
| `hook.added`, `hook.used` | `owner`, `target`, `strong` | |
| `secret.added`, `secret.learned`, `secret.blackmailed`, `secret.exposed` | `owner`, `secret`, `knower`/`exposer` | |
| `law.changed` | `character`, `law`, `previous` | |

> **Потоки.** Мир считается в отдельном потоке симуляции, поэтому хуки
> и эффекты вызываются **не** в главном потоке Godot. Из них нельзя трогать
> узлы сцены и интерфейс — только состояние игры через `api`/`game`.
> Функции интерфейса из мода (виджеты верхней панели, разделы, режимы карты,
> подсказки) вызываются в главном потоке, когда симуляция стоит на границе
> дня, — в них мир можно читать и менять как обычно.

---

## 10. Механики: образ жизни, совет, темница, фракции, отряды, секреты, законы, рыцари

Крупные подсистемы в стиле CK3 устроены как **механики** (`engine/features`).
Механика — модуль, который при запуске регистрирует свои системы, триггеры,
эффекты, поставщиков модификаторов и проверки контента — ровно теми же
средствами, что доступны скриптам модов. Поэтому:

- **всё содержимое механик — данные** в моде `core`: должности совета, перки,
  фракции, типы отрядов меняются и дополняются обычным YAML со слиянием;
- **любую механику можно выключить** из данных — например, для мода без совета:

  ```yaml
  defines:
    disabled_features: [council, factions]
  ```

  (доступны `lifestyles`, `council`, `prison`, `factions`, `regiments`,
  `secrets`, `laws`, `knights`;
  интерфейс скрывает вкладки и разделы выключенных механик). Словарь скриптов
  механики (её триггеры, эффекты, значения) остаётся зарегистрированным, так что
  чужие данные, которые его упоминают, не ломаются — на пустом состоянии
  триггеры просто ложны. А записи с полем `requires_feature: <механика>`
  (у любого типа контента) при отключении механики удаляются — так помечены,
  например, взаимодействия с пленниками и поводы к мятежам;
- **свою механику** мод добавляет через `api.add_feature(MyFeature.new())`, где
  `MyFeature` наследует `EngineFeature` и переопределяет `register_script(engine)` и `install(engine)`.

Все числа механик — в `defines` (`lifestyle`, `council`, `prison`, `factions`,
`regiments`, `secrets`, `hooks`, `knights`).

### Образ жизни

```yaml
lifestyles:
  stewardship_lifestyle: { skill: stewardship, icon: "💰", order: 3 }   # xp_mult: 0.5 — путь вдвое медленнее
focuses:
  focus_wealth:
    lifestyle: stewardship_lifestyle
    modifiers: { stewardship: 1, tax_mult: 0.1 }
    ai_will_do: 1                       # вес при выборе ИИ (умножается на навык)
perks:
  master_builder: { lifestyle: stewardship_lifestyle, tree: architect, modifiers: { build_cost_mult: -0.15 } }
  royal_architect:
    lifestyle: stewardship_lifestyle
    tree: architect
    requires: master_builder            # или список
    trait: architect                    # черта за завершение дерева
    effect: { add_prestige: 100 }       # эффект при открытии (необязательно)
```

Взрослые персонажи копят опыт текущего образа жизни: `(base_xp + навык × xp_per_skill) × (1 + lifestyle_xp_mult) × xp_mult`
в месяц (`xp_mult` — поле образа жизни, по умолчанию 1); перк стоит `perk_cost + perk_cost_growth × открытых перков`. ИИ выбирает
фокус и перки сам (по `ai_will_do`), игрок — во вкладке «Образ жизни».
Скрипт: `has_perk`, `has_focus`, `has_lifestyle`, `num_perks`, `lifestyle_xp`,
`add_perk`, `remove_perk`, `set_focus`, `add_lifestyle_xp`.

### Совет

```yaml
council_positions:
  court_chaplain:
    skill: learning
    candidate: { same_faith_as: scope:liege }   # кто может занять (root — кандидат)
council_tasks:
  develop_domain:
    position: steward
    liege_modifiers:                            # модификаторы правителя; root — советник
      tax_mult: { value: stewardship, multiply: 0.01 }
    monthly_chance: { value: stewardship, multiply: 0.6 }   # % в месяц
    monthly_effect:
      scope:liege:
        random_domain_province: { add_development: 1 }
    ai_will_do: 10                              # root — правитель
```

Кандидаты — совершеннолетние придворные, вассалы и супруги правителя. ИИ
заполняет места лучшими по навыку и раз в год меняет слабых. Советник лучше
относится к правителю (`defines.council.councillor_opinion`), снятый — обижается.
Скрипт: `is_councillor` (yes/no/должность), `has_council_task`, `council_size`,
ссылки по id должностей (`root.marshal`, `scope:liege.spymaster`), список
`councillor`, `neighboring_county`, эффекты `appoint_councillor`, `discover_scheme_against`.

### Темница

Взаимодействия с пленниками — обычные `interactions` с полем `prisoner`:
`never` (по умолчанию — с пленником недоступно), `only` (только с пленником),
`allowed`. Выкуп решает не сам пленник, а плательщик: `decider: payer`
(свои «решающие» регистрируются в `registries.interactionDeciders`).

Правителей берут в плен при взятии их столицы, полководцев — после
проигранных сражений; плен вражеского лидера даёт `leader_captured_warscore`
очков войны. Пленник не правит, не командует и не ведёт интриги.
Скрипт: `is_imprisoned`, `is_imprisoned_by`, `has_imprisonment_reason`
(законный повод: раскрытая интрига, модификатор мнения из
`crime_opinion_modifiers`, флаг от `mark_criminal`), `prison_months`,
`ransom_cost`, `num_prisoners`, список `prisoner`, эффекты `imprison`,
`release_from_prison`, `mark_criminal`. Казнь — обычный `death: { reason: execution, killer: … }`.

### Фракции

```yaml
factions:
  independence_faction:
    cb: independence_revolt          # повод к войне с manual: yes
    can_join: { is_vassal: yes }     # root — вассал, scope:liege — сюзерен
    ai_join: { value: -10, add: { value: "opinion(scope:liege)", multiply: -0.8 } }
    ai_accept_demands: { value: -60, add: { value: scope:faction.faction_power, multiply: 0.35 } }
    on_demands_accepted:
      scope:faction: { every_faction_member: { become_independent: yes } }
  claimant_faction:
    claimant: yes                    # нужен претендент с претензией на основной титул сюзерена
    …
```

Когда сила фракции превышает `power_threshold`% силы сюзерена, копится
недовольство; на 100% — ультиматум. ИИ-сюзерен решает по `ai_accept_demands`,
игроку приходит событие `faction.0001` (его можно заменить). Отказ —
война с поводом `cb`, где все члены фракции — нападающие; в эффектах повода
доступны `scope:war` (списки `war_attacker`, `war_defender`) и `scope:claimant`.
Скоуп фракции: значения `faction_power`, `faction_discontent`,
`num_faction_members`; ссылки `faction_leader`, `faction_target`,
`faction_claimant`; список `faction_member`; эффекты `faction_enforce_demands`,
`faction_start_war`, `add_faction_discontent`. Для персонажа: `is_in_faction`,
`is_faction_leader`, `joined_faction`, `join_faction`, `leave_faction`,
`seize_primary_title`.

### Профессиональные войска

```yaml
regiment_types:
  pikemen:
    size: 100            # воинов в отряде
    power: 2.4           # сколько ополченцев стоит один воин
    cost: { gold: 50 }
    upkeep: 0.35         # в месяц; в поднятой армии × raised_upkeep_mult
    counters: { heavy_cavalry: 0.6 }   # до 60% силы рыцарей снимается, если пикинёров не меньше
    terrain: { hills: 0.2 }            # бонус к силе на местности
    can_recruit: { culture: [english, norse] }
    ai_will_do: 10
```

Поднятая армия забирает отряды правителя, потери в бою переносятся на
отряды, после роспуска они пополняются (`reinforce_rate`). Сила армии в бою
и в оценках ИИ складывается через хук `army.power_bonus` — мод может
добавить свои бонусы (например, от рыцарей-персонажей).
Скрипт: `has_regiment`, `num_regiments`, `regiment_cap`, `regiment_power`, `add_regiment`.

### Крюки и секреты

**Крюк** — рычаг давления на персонажа (`add_hook: { target, strong: yes, years }`).
Во взаимодействиях с `ai_accept` игрок может отметить «Использовать крюк» —
решающий обязан согласиться; слабый крюк при этом тратится, сильный уходит на
перерыв (`defines.hooks.strong_hook_cooldown_years`). ИИ тоже давит крюками,
когда очень хочет получить согласие. Запретить крюк во взаимодействии:
`hookable: no`. Скрипт: `has_hook_on`, `has_strong_hook_on`, `can_use_hook_on`,
`num_hooks`, `add_hook`, `remove_hook`.

**Секреты** (механика `secrets`) — постыдные тайны персонажей:

```yaml
secret_types:
  secret_murder:
    hook: strong                     # какой крюк даёт шантаж
    severity: 100                    # шантажируют и разоблачают самым тяжёлым
    discovered_by: [spouse, close_family, courtier]   # кто может случайно узнать
    discovery_chance: 0.4            # % в месяц
    on_expose:                       # root — владелец, scope:exposer, scope:secret_target
      - add_prestige: -200
      - liege: { add_opinion: { target: root, modifier: exposed_murderer } }
```

Секреты появляются из данных: интрига убийства даёт `secret_murder`, удачное
соблазнение женатого — `secret_lover`, событие о казначее — `secret_embezzler`
(`add_secret: { type, target }`). Их раскрывают задача тайного советника
«Поиск секретов» (`discover_secret`) и случайные свидетели. Взаимодействия
«Шантажировать» и «Разоблачить секрет» используют эффекты `blackmail` и
`expose_secret`. Скрипт: `has_secret`, `knows_secret_of`, `num_secrets`,
`num_known_secrets`, список `known_secret_owner`.

**Скрытые черты.** Черта с `concealed: <тип секрета>` видна только тем, кто знает
этот секрет её владельца (и самому владельцу): остальные не видят её плашку,
изменённый портрет и не учитывают её в мнении (`compatibility`). Раскрыть черту
всем — эффект `reveal_trait: <черта>` (обычно в `on_expose` секрета). В разбивке
характеристик вклад скрытой черты растворяется в базовом значении. Модификатор,
который выдаёт тайную природу, помечается `concealed: <черта>` — его видят только
те, кто видит эту черту (`bloodthirst: { concealed: vampire, ... }`).

Модификатор провинции с `wards_off_dead: yes` (мод `arcana`: освящённая
земля, благословение светлого чародея) не даёт мёртвым восстать — так любой мод
может добавить свою защиту от нежити. Триггер
`has_trait` проверяет истину, `has_known_trait` — то, что видят все:

```yaml
traits:
  vampire: { category: supernatural, concealed: secret_vampire }
secret_types:
  secret_vampire:
    on_expose: [ { reveal_trait: vampire }, { add_prestige: -400 } ]
```

### Законы державы

```yaml
law_groups:
  crown_authority: { default: crown_authority_1, cooldown_years: 5, is_shown: { tier: ">= duchy" } }
realm_laws:
  crown_authority_2:
    group: crown_authority
    level: 2
    modifiers: { vassal_tax_mult: 0.25, vassal_levy_mult: 0.25, vassal_opinion: -5 }
    change_cost: { prestige: 300 }
    can_change: { NOT: { any_vassal: { count: ">= 2", opinion: { target: root, value: "< -20" } } } }
```

Закон меняется на одну ступень за раз. Уровень доступен как значение
`<группа>_level` (`crown_authority_level`) — так, например, `revoke_title`
требует власти короны не ниже 1, а на уровне 3 отзыв титулов перестаёт быть
тиранией. Скрипт: `has_realm_law`, `set_realm_law`. Новая группа законов —
просто новая запись `law_groups` и её законы.

### Рыцари

Рыцарями правителя становятся самые доблестные придворные и вассалы,
прошедшие `scripted_triggers.knight_candidate` (её легко заменить — например,
разрешить женщин-рыцарей). Их число — `defines.knights.cap_by_tier` и
характеристика `knight_cap`; каждое очко доблести стоит `power_per_prowess`
ополченцев в главной армии. Рыцари получают раны и гибнут в сражениях.
Скрипт: `is_knight`, `num_knights`, `knights_power`, список `knight`.

### Оповещения

Круглые значки слева вверху — реестр `api.ui.alerts`:

```gdscript
api.ui.alerts.register("my_alert", {
	"id": "my_alert",
	"check": func(game: Game):
		if game.player.gold > 1000:
			return {"icon": "💰", "kind": "good", "text": "Казна полна!", "action": {"tab": "decisions"}}
		return null,
})
```

`action` открывает вкладку (`tab`), персонажа, титул или провинцию.
Регистрация с id встроенного оповещения заменяет его.

---

## 11. Полная замена контента (total conversion)

Отключите `core` в менеджере модов и включите свой мод. Минимальный набор для
запуска партии:

- `skills`, `traits` (хотя бы личностные), `cultures`, `faiths`, `terrain`, `holdings`;
- `map` + `landmasses` + `provinces` + `titles`;
- `succession_laws`;
- `bookmarks` (дата и владельцы титулов; недостающих правителей движок сгенерирует сам).

Строки интерфейса движка уже встроены (`locale/`), а всё остальное
(события, решения, войны, интриги) — по желанию.

---

## 12. Инструменты

Инструменты запускаются через Godot из папки проекта (с исходниками игры);
моды берутся встроенные и из «Документы/Crown and Dynasty/mods».

| Команда | Что делает |
|---|---|
| `godot --path .` | Запуск игры из исходников (или F5 в редакторе Godot). |
| `godot --headless --path . -s tools/validate.gd` | Проверка всех модов: синтаксис, зависимости, ссылки (в том числе в аргументах скриптов: `has_trait: brave`, `add_opinion: { modifier: … }`), неизвестные ключи скриптов, пробный запуск закладок, расхождения локализаций. Код возврата 1 при ошибках. |
| `godot --headless --path . -s tools/sim.gd -- --years 50 --seed 1 --verbose` | Безголовая симуляция: войны, смерти, крупнейшие державы — для баланса. `--mods core,my_mod` — выбрать моды, `--bookmark id` — закладку. |
| `godot --headless --path . -s tools/script_docs.gd` | Пересобрать `docs/SCRIPT_REFERENCE.md` (с учётом ваших модов). |
| `godot --headless --path . -s tests/run.gd` | Автотесты движка. |
| `godot --headless --path . -s tools/make_icons.gd` | Пересобрать иконки приложения из `assets/icon.svg`. |
