// Tolzar UI phase 3 reading pane helpers (pure, unit-tested): the AI draft's check chips and its sources line,
// from the brain's decision (/explain: checks [{check, passed}], based_on [{ref, title, snippet}]).

export const CHIP_CHECKS = [
  'price_guard',
  'output_policy',
  'language',
  'grounding',
];

export function checkChips(decision) {
  const list = Array.isArray(decision?.checks) ? decision.checks : [];
  return CHIP_CHECKS.map(name => list.find(c => c?.check === name))
    .filter(Boolean)
    .map(c => ({ check: c.check, passed: !!c.passed }));
}

// "Price list, FAQ: delivery" — the first three sources by title (or snippet), without duplicates.
export function sourcesLine(decision, max = 3) {
  const list = Array.isArray(decision?.based_on) ? decision.based_on : [];
  const names = [];
  list.forEach(s => {
    const name = String(s?.title || s?.snippet || '')
      .trim()
      .slice(0, 60);
    if (name && !names.includes(name)) names.push(name);
  });
  const shown = names.slice(0, max).join(', ');
  return names.length > max ? `${shown} +${names.length - max}` : shown;
}
