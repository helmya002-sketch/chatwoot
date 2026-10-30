import { describe, it, expect } from 'vitest';
import {
  sectionKeys,
  isSection,
  filterSections,
  exportArrived,
  EXPORT_POLL_MS,
  EXPORT_POLL_MAX,
  audienceFields,
  isStageField,
} from '../tolzarSettingsHub';

const SECTIONS = [
  ['workspace', ['usage', 'audit', 'export']],
  ['team', ['sla', 'qa']],
];
const TEXT = {
  usage: 'Usage What this workspace used in the last 30 days.',
  audit: 'Audit log Who changed what, and when.',
  export: 'Export Everything this workspace holds in one file.',
  sla: 'Response times Flag conversations where a customer waited too long.',
  qa: 'Quality & coaching Every conversation scored against your rubric.',
};
const text = k => TEXT[k];

describe('tolzarSettingsHub', () => {
  it('knows its section keys', () => {
    expect(sectionKeys(SECTIONS)).toEqual(['usage', 'audit', 'export', 'sla', 'qa']);
    expect(isSection(SECTIONS, 'sla')).toBe(true);
    expect(isSection(SECTIONS, 'nope')).toBe(false);
    expect(isSection(SECTIONS, '')).toBe(false);
    expect(isSection(SECTIONS, undefined)).toBe(false);
  });

  it('filters sections by label and hint, dropping empty groups', () => {
    expect(filterSections(SECTIONS, '', text)).toBe(SECTIONS);
    expect(filterSections(SECTIONS, '   ', text)).toBe(SECTIONS);
    expect(filterSections(SECTIONS, 'WAITED', text)).toEqual([['team', ['sla']]]);
    expect(filterSections(SECTIONS, 'workspace', text)).toEqual([
      ['workspace', ['usage', 'export']],
    ]);
    // every word must match, in any order
    expect(filterSections(SECTIONS, 'file holds', text)).toEqual([
      ['workspace', ['export']],
    ]);
    expect(filterSections(SECTIONS, 'zzz', text)).toEqual([]);
  });

  it('ignores accents when searching', () => {
    const t = k => (k === 'sla' ? 'Délais de réponse' : '');
    expect(filterSections(SECTIONS, 'delais', t)).toEqual([['team', ['sla']]]);
  });

  it('notices when a new export arrives, and polls every 15 s for 10 minutes at most', () => {
    const before = [{ created_at: '2026-10-30T10:00:00Z' }];
    expect(exportArrived(before, before)).toBe(false);
    expect(exportArrived(before, [])).toBe(false);
    expect(exportArrived([], [{ created_at: '2026-10-30T10:01:00Z' }])).toBe(true);
    // the server keeps at most 5: a newer row can replace an older one without growing the list
    expect(exportArrived(before, [{ created_at: '2026-10-30T10:05:00Z' }])).toBe(true);
    expect(exportArrived(null, null)).toBe(false);
    expect(EXPORT_POLL_MS).toBe(15000);
    expect((EXPORT_POLL_MS * EXPORT_POLL_MAX) / 60000).toBe(10);
  });

  it('offers stage fields first, then the workspace\'s contact attributes, without duplicates', () => {
    const fields = audienceFields([
      { attribute_model: 'contact_attribute', attribute_key: 'lifecycle_stage', attribute_display_name: 'Stage' },
      { attribute_model: 'contact_attribute', attribute_key: 'plan', attribute_display_name: 'Plan', attribute_values: ['free', 'pro'] },
      { attribute_model: 'conversation_attribute', attribute_key: 'topic' },
      null,
    ]);
    expect(fields[0]).toEqual({ key: 'lifecycle_stage', label: 'lifecycle_stage', stage: true });
    expect(fields.filter(f => f.key === 'lifecycle_stage')).toHaveLength(1);
    expect(fields.find(f => f.key === 'plan')).toEqual({
      key: 'plan',
      label: 'Plan',
      stage: false,
      values: ['free', 'pro'],
    });
    expect(fields.some(f => f.key === 'topic')).toBe(false);
    expect(isStageField('lifecycle_stage')).toBe(true);
    expect(isStageField('plan')).toBe(false);
    expect(audienceFields().length).toBeGreaterThan(0);
  });
});
