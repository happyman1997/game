// Необязательный JS-скрипт мода. Удалите его и поле "scripts" в mod.json,
// если мод состоит только из данных.
export function init(api) {
  // Новое значение для скриптов: сколько у персонажа соколов.
  api.script.value('falcons', {
    scopes: ['character'],
    doc: 'Число соколов у персонажа',
    get: (ctx, scope) => ctx.game.char(scope.id)?.vars.falcons ?? 0,
  });
  // Хук: сокольничие радуются удачной охоте.
  api.hooks.on('decision.taken', ({ game, decision, character }) => {
    if (decision !== 'train_falcon') return;
    const c = game.char(character);
    if (c) c.vars.falcons = (c.vars.falcons ?? 0) + 1;
  });
  api.log('my_mod загружен');
}
