// Tolzar UI phase 2 shell helpers (pure, unit-tested): the "AI live" card's summary from the workspace settings
// view (GET tolzar/workspace/settings: inbox_modes {id: {mode}}, kill_switch_on).

export function aiLiveSummary(settings, inboxCount = 0) {
  if (!settings) return { state: 'shadow', live: 0, shadow: inboxCount };
  const modes = settings.inbox_modes || {};
  const live = Object.values(modes).filter(
    m => (m && m.mode) === 'live'
  ).length;
  const shadow = Math.max(inboxCount - live, 0);
  if (settings.kill_switch_on)
    return { state: 'stopped', live: 0, shadow: inboxCount };
  return { state: live > 0 ? 'live' : 'shadow', live, shadow };
}
