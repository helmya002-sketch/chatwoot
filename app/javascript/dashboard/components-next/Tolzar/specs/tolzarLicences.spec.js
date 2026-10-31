import {
  GROUPS,
  licencesView,
  safeUrl,
  filterItems,
  licenceSummary,
  summaryLine,
  itemLabel,
} from '../tolzarLicences';

const DATA = {
  foundation: { name: 'Chatwoot', licences: ['MIT'], text: 'MIT text' },
  groups: {
    gems: [
      { name: 'rails', version: '7.1', licences: ['MIT'], text: 'x' },
      { name: 'nokogiri', version: '1.16', licences: ['MIT'] },
    ],
    javascript: [{ name: 'vue', version: '3.5', licences: ['MIT'] }],
    system: [
      {
        name: 'libvips',
        licences: ['LGPL-2.1-or-later'],
        homepage: 'https://github.com/libvips/libvips/releases',
      },
    ],
  },
  source_offer: [{ name: 'libvips', licences: ['LGPL-2.1-or-later'] }],
};

describe('tolzarLicences', () => {
  it('fills every group and field the page reads', () => {
    const v = licencesView(DATA);
    expect(Object.keys(v.groups)).toEqual(GROUPS);
    expect(v.groups.ai).toEqual([]);
    expect(v.groups.gems[1]).toEqual({
      name: 'nokogiri',
      version: '1.16',
      licences: ['MIT'],
      homepage: '',
      author: '',
      text: '',
      role: '',
    });
    expect(v.foundation.text).toBe('MIT text');
    expect(v.sourceOffer[0].name).toBe('libvips');
  });

  it('copes with an empty or missing answer', () => {
    const v = licencesView(null);
    expect(v.foundation.name).toBe('');
    expect(GROUPS.every(g => v.groups[g].length === 0)).toBe(true);
    expect(v.sourceOffer).toEqual([]);
  });

  it('links only http(s) addresses', () => {
    expect(safeUrl('https://example.org')).toBe('https://example.org');
    expect(safeUrl('data:text/html,x')).toBe('');
    expect(safeUrl('git://github.com/x')).toBe('');
  });

  it('filters by name or licence, case-insensitively', () => {
    const items = licencesView(DATA).groups.gems;
    expect(filterItems(items, '')).toHaveLength(2);
    expect(filterItems(items, 'NOKO').map(i => i.name)).toEqual(['nokogiri']);
    expect(filterItems(licencesView(DATA).groups.system, 'lgpl')).toHaveLength(
      1
    );
  });

  it('summarises licences, most used first', () => {
    const items = [
      ...licencesView(DATA).groups.gems,
      { name: 'a', licences: ['Apache-2.0'] },
      { name: 'b', licences: [] },
    ];
    expect(licenceSummary(items)).toEqual([
      { licence: 'MIT', count: 2 },
      { licence: 'Apache-2.0', count: 1 },
      { licence: 'UNKNOWN', count: 1 },
    ]);
  });

  it('writes the summary and item lines', () => {
    const v = licencesView(DATA);
    expect(summaryLine(v.groups.gems)).toBe('MIT: 2');
    expect(itemLabel(v.groups.gems[0])).toBe('rails 7.1 · MIT');
    expect(itemLabel(v.foundation)).toBe('Chatwoot · MIT');
  });
});
