// Новый алгоритм наследования «elective»: кандидаты — взрослые члены
// династии и могущественные вассалы; голосуют вассалы правителя.
export function init(api) {
  const { characters, opinion, succession } = api.world;

  api.registries.successionAlgorithms.register('elective', {
    label: { ru: 'Выборы', en: 'Election' },
    heirs(game, ruler, law) {
      const adult = (c) => characters.isAdult(game, c);
      const dyn = ruler.dynasty ? game.living().filter((c) => c.dynasty === ruler.dynasty && c.id !== ruler.id && adult(c)) : [];
      const vassals = game.vassalsOf(ruler.id).filter(adult);
      let candidates = [...new Set([...dyn, ...vassals])];
      if (law.gender === 'male_only') candidates = candidates.filter((c) => !c.female);
      if (!candidates.length) return succession.bloodLine(game, ruler, law.gender);
      const electors = game.vassalsOf(ruler.id).filter((v) => v.death === undefined);
      const score = (cand) =>
        electors.reduce((s, e) => s + opinion.opinion(game, e, cand), 0) + cand.prestige / 50 + (cand.dynasty === ruler.dynasty ? 15 : 0);
      const ranked = candidates.map((c) => ({ c, s: score(c) })).sort((a, b) => b.s - a.s).map((x) => x.c.id);
      const blood = succession.bloodLine(game, ruler, law.gender).filter((id) => !ranked.includes(id));
      return [...ranked, ...blood];
    },
  });

  // Хук: сообщаем игроку, кто победил на выборах.
  api.hooks.on('succession', ({ game, deceased, primary }) => {
    if (deceased.successionLaw !== 'feudal_elective') return;
    const lang = game.loc.lang;
    game.message(
      (lang === 'ru' ? 'Выборы: новым правителем избран ' : 'Election: the new ruler is ') + game.scopeName({ type: 'character', id: primary }, 'full_name'),
      'info',
      { type: 'character', id: primary },
      [deceased.id, primary],
    );
  });
}
