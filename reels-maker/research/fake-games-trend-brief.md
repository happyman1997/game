# Trend Discovery Brief: несуществующие видеоигры (TikTok, Reels)

Дата: 24.11.2026.

**Методика.** По инструкциям [`trend-discovery`, `creator-profile-teardown` и `outlier-post-finder`](https://github.com/ScrapeCreators/social-media-research-skills) от ScrapeCreators:
- доказательства отделяются от догадок;
- один вирусный пост не называется трендом;
- каждый тренд переводится в формат, который можно сделать самим.

**Ограничение.** Ключа ScrapeCreators API не было, поэтому живых метрик (просмотры, базовые показатели авторов) здесь нет. Доказательства взяты из публикаций Know Your Meme, Kotaku, Time Extension, отраслевых блогов и вики мемов. Цифры просмотров из вторичных источников не проверены.

**Уверенность:** средняя в том, что форматы существуют и работают; низкая в конкретных цифрах.

## Тренды, на которых стоит строить контент

| Тренд | Площадки | Доказательства | Почему важно | Наш формат |
|---|---|---|---|---|
| Вселенная выдуманной игры с ремиксами («Bird Game 3») | TikTok | ИИ-ролик про игру для несуществующей консоли «Xbox 50», октябрь 2025. Затем ремиксы: фейковые балансные патчи, DLC, «анонсы». Один «анонс» — около 3,2 млн просмотров (не проверено) | Зрители сами достраивают лор; сериальность; шутка с номером «3» (значит, были 1 и 2) | `patch` и продолжения в `trailer`; общая «вселенная» игр; номера в названиях |
| Пародии на рекламу мобильных игр («fail ads») | TikTok, YouTube, Reddit | Fail ads названы самым вирусным поджанром фейковой рекламы. Зрители высмеивают такую рекламу в комментариях и роликах-реакциях. Лор «Pink Dragon». Пародийная кампания KFC | Формат узнают все и сразу, крючок срабатывает в первую секунду | `ad` |
| «Забытая игра» / lost media | TikTok | Зернистые записи «забытой классики» вокруг Bird Game 3. Сгенерированная ИИ реклама ретроконсолей обманывала зрителей (май 2026) | Ностальгия и загадка; в комментариях пишут «я в это играл!» | `lost` |
| Посты-идеи несуществующих игр («This Game Does Not Exist») | X/Twitter | Аккаунт с фейковыми идеями игр, с 2022 года | Для интереса хватает концепции и текста | карточки в `trailer`, названия |
| Абсурдная игра-пародия («Man The Game») | TikTok | Know Your Meme, июнь 2024 | Абсурдная завязка сама толкает репосты | названия и крючки |

## Чего не копировать

- **Выдавать фейк за настоящую утечку.** Фейковый «слив» GTA 6, сгенерированный ИИ, вызвал скандал, и автору пришлось объяснять, что это шутка. В каждом нашем посте прямо написано «This game does not exist».
- **Настоящие бренды игр и консолей** (Xbox, GTA, Flappy Bird и т. п.). Это риск жалоб правообладателей. У нас все консоли, студии и игры выдуманы, и генератор не воспроизводит ни одну существующую игру.
- **Сам Bird Game 3.** По одному из источников волна пошла на спад к январю 2026 года. Мы берём механику (вселенная, патчи, сиквелы), а не тему.
- **Трендовые звуки через API.** API TikTok не умеет их прикреплять. В режиме черновиков звук можно добавить вручную перед публикацией.

## Крючки (заложены в генератор)

- `lost`: «found a VHS of a {year} game nobody remembers», «my uncle swears this {console} game was real»
- `ad`: «mobile game ads be like», «99% fail this level. the other 1% also fail»
- `trailer`: «they finally announced {title}», «nobody asked for {title}»
- `patch`: «{title} patch notes are getting out of hand», «(pause to read)»

## Идеи серий

1. **Одна игра — неделя роликов.** Понедельник — найденная кассета, среда — реклама, пятница — патч-ноты, позже — трейлер продолжения. Генератор сам ведёт вселенную (`state/fakegames.json`), так что продолжения и патчи ссылаются на уже показанные игры.
2. **Патч-ноты из комментариев.** Закрепить комментарий «предложи следующий патч» и вписывать лучшие идеи в шаблоны. Когда появится ключ API, это можно автоматизировать через `comment-mining`.
3. **«Сиквел, которого никто не просил».** Номер в названии растёт с каждым продолжением (Goose Racing 64 → 65).

## Тесты для нас (первые 2–3 недели)

1. Выкладывать все четыре формата вперемешку (по умолчанию: lost 32 %, ad 26 %, patch 22 %, trailer 20 %).
2. Каждый ролик оценивать относительно медианы своих же просмотров, как в `outlier-post-finder`: прирост = просмотры / медиана. От 2× — сильный выброс, от 5× — огромный.
3. Когда наберётся хотя бы 10 роликов на формат, сместить доли к победителям: `make_fakegame.py --weights lost=3,ad=2,patch=1,trailer=1` или `"fakegame_args"` в config.json. До 10 роликов выводы не делать.
4. Внутри формата сравнивать крючки: один и тот же формат с разными подписями.

## Источники

- [Bird Game 3 — meme.com](https://meme.com/memes/bird-game-3), [подробнее](https://meme.com/memes/bird-game-3/md)
- [Bird Game 3 fake game — Chiang Rai Times](https://www.chiangraitimes.com/tech/bird-game-3-fake-game/)
- [Bird Game 3 is taking over TikTok — GeekChamp](https://geekchamp.com/?p=217480)
- [This Game Does Not Exist — Know Your Meme](https://knowyourmeme.com/memes/sites/this-game-does-not-exist)
- [Man The Game — Know Your Meme](https://knowyourmeme.com/editorials/guides/is-man-the-game-real-the-viral-tiktok-video-game-and-its-memes-explained)
- [Pink Dragon — Know Your Meme](https://knowyourmeme.com/editorials/guides/what-is-the-pink-dragon-game-going-viral-on-tiktok-pink-dragon-lore-explained)
- [Fake mobile game ads — Udonis](https://www.blog.udonis.co/mobile-marketing/mobile-games/fake-mobile-game-ads), [мемы о рекламе мобильных игр](https://www.blog.udonis.co/mobile-marketing/mobile-games/mobile-game-ads-memes)
- [Почему KFC сделала фейковую рекламу игр — The Drum](https://www.thedrum.com/opinion/2025/04/08/why-we-made-phony-game-ads-reality-kfc)
- [ИИ-реклама ретроконсолей обманывает зрителей — Time Extension](https://timeextension.com/news/2026/05/random-this-isnt-real-is-it-these-annoying-gen-ai-adverts-for-retro-consoles-are-fooling-a-lot-of-people)
- [Автор ИИ-приманки про GTA 6 говорит, что это шутка — Kotaku](https://kotaku.com/account-behind-viral-ai-gta-6-bait-claims-it-was-just-a-joke-2000647720)
- [Исследование о фейковых играх — NSF PAR](https://par.nsf.gov/servlets/purl/10552301)
