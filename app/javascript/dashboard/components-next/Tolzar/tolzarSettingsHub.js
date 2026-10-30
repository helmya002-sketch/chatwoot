// Pure helpers for the Settings hub (routes/dashboard/tolzar/TolzarSettingsHub.vue): section
// lookup and search, the export poll, the broadcast audience picker. No Vue, no network.
import { STAGE_ATTRIBUTES } from './tolzarStages';

// Every section key of [group, keys] pairs.
export const sectionKeys = sections => sections.flatMap(([, keys]) => keys);
export const isSection = (sections, key) =>
  !!key && sectionKeys(sections).includes(String(key));

// Case- and accent-insensitive "does the nav label or the hint mention this".
const fold = s =>
  String(s || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();

// The groups that still have a matching section for `query` ('' keeps everything).
// `text(key)` gives the searchable words of one section (its NAV label + HINT).
export const filterSections = (sections, query, text) => {
  const q = fold(query).trim();
  if (!q) return sections;
  const words = q.split(/\s+/).filter(Boolean);
  return sections
    .map(([group, keys]) => [
      group,
      keys.filter(k => {
        const hay = fold(text(k));
        return words.every(w => hay.includes(w));
      }),
    ])
    .filter(([, keys]) => keys.length);
};

// Export polling: every 15 s, up to 10 minutes, until a new export shows up.
export const EXPORT_POLL_MS = 15000;
export const EXPORT_POLL_MAX = 40;
const newest = list =>
  Math.max(0, ...(list || []).map(x => Date.parse(x.created_at) || 0));
// True once `after` holds an export that `before` did not (more rows, or a newer created_at).
export const exportArrived = (before, after) =>
  (after || []).length > (before || []).length || newest(after) > newest(before);

// Broadcast audience: the fields a workspace can target by. Stage fields come first (their value
// is picked from the pipeline's stages); then the workspace's own contact attributes.
export const audienceFields = (definitions = []) => {
  const seen = new Set();
  const out = [];
  STAGE_ATTRIBUTES.forEach(k => {
    seen.add(k);
    out.push({ key: k, label: k, stage: true });
  });
  (definitions || [])
    .filter(d => d && d.attribute_model === 'contact_attribute' && d.attribute_key)
    .forEach(d => {
      if (seen.has(d.attribute_key)) return;
      seen.add(d.attribute_key);
      out.push({
        key: d.attribute_key,
        label: d.attribute_display_name || d.attribute_key,
        stage: false,
        values: Array.isArray(d.attribute_values) ? d.attribute_values : [],
      });
    });
  return out;
};
export const isStageField = key => STAGE_ATTRIBUTES.includes(String(key));
