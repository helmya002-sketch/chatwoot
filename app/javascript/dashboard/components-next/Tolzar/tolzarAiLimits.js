// Tolzar "AI" settings: negotiation limits, agent <-> team mapping, tuning proposals
// (plugins/negotiation.py, agent_teams.py, tuning.py). Approving a proposal never changes the
// agent: the owner pastes the edit into the agent's instructions.
import { brainGet, brainPost } from './tolzarBrainApi';

export const parsePerks = v =>
  (Array.isArray(v) ? v : String(v || '').split('\n'))
    .map(p => String(p).trim())
    .filter(Boolean);

// Standing policies ("children under 6 free"): facts replies may state without being an offer.
// Mirrors the brain's cleaning: whitespace collapsed, empty rows dropped, each row cut to
// MAX_POLICY_CHARS, duplicates dropped, at most MAX_POLICIES rows.
export const MAX_POLICIES = 30;
export const MAX_POLICY_CHARS = 200;
export const parsePolicies = v => {
  const rows = (Array.isArray(v) ? v : String(v || '').split('\n'))
    .map(p =>
      String(p ?? '')
        .split(/\s+/)
        .filter(Boolean)
        .join(' ')
    )
    .filter(Boolean)
    .map(p => p.slice(0, MAX_POLICY_CHARS));
  return [...new Set(rows)].slice(0, MAX_POLICIES);
};

// Mirrors the brain: the tighter of the max discount and the floor; 0 when off.
export const allowedDiscount = s => {
  if (!s || !s.enabled) return 0;
  return Math.max(
    0,
    Math.min(Number(s.max_discount_pct) || 0, 100 - (Number(s.floor_pct) || 0))
  );
};

export const getNegotiation = accountId => brainGet(accountId, 'negotiation');
export const saveNegotiation = (accountId, s) =>
  brainPost(accountId, 'negotiation', {
    enabled: !!s.enabled,
    floor_pct: Number(s.floor_pct),
    max_discount_pct: Number(s.max_discount_pct),
    perks: parsePerks(s.perks),
    // Left out when the form never loaded them, so an older form can't wipe the list.
    ...(s.policies !== undefined
      ? { policies: parsePolicies(s.policies) }
      : {}),
  });

export const getAgentTeams = accountId => brainGet(accountId, 'agent_teams');
export const saveAgentTeams = (accountId, teams) =>
  brainPost(accountId, 'agent_teams', { teams });

// One row per Chatwoot team, with the agent the brain has for it ('' = the default agent).
export const teamRows = (teams, map) =>
  (teams || []).map(t => ({
    id: String(t.id),
    name: t.name,
    agent: (map && map[String(t.id)]) || '',
  }));
export const teamsFromRows = rows =>
  Object.fromEntries(rows.map(r => [r.id, r.agent || '']));

export const getTuning = accountId => brainGet(accountId, 'tuning');
export const runTuning = accountId => brainPost(accountId, 'tuning_run');
// status: 'approved' | 'rejected'; edit: the edit's number, or omitted for the whole proposal.
export const decideTuning = (accountId, date, status, edit) =>
  brainPost(accountId, 'tuning_decide', {
    date,
    status,
    ...(edit !== undefined && edit !== null ? { edit } : {}),
  });
