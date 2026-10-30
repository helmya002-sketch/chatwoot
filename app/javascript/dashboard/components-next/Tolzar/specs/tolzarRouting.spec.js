import {
  parseKeywords,
  keywordText,
  routingModel,
  routingForm,
  routingPatch,
} from '../tolzarRouting';

const VIEW = {
  version: 4,
  viewer_role: 'owner',
  routing_editor: true,
  merged: {
    teams: { north: 11, south: 22 },
    destinations: {
      north: { team: 'north', location: 'North branch', name: 'North' },
      south: { team: 'south', location: 'South branch' },
    },
    team_descriptions: { north: 'The north team' },
    categories: [{ key: 'lead' }, { key: 'complaint', handover: true }],
    rules: {
      destination_keywords: { north: ['uptown'] },
      category_keywords: { complaint: ['refund'] },
    },
    templates: {
      handover: { en: 'A colleague will reply.', de: 'Ein Kollege antwortet.' },
      handover_owners: { en: 'Our team takes this one.' },
    },
  },
};

describe('tolzarRouting', () => {
  it('parses keywords: trimmed, lower-case, no repeats, commas or lines', () => {
    expect(parseKeywords(' Uptown, MALL\nuptown,, ')).toEqual([
      'uptown',
      'mall',
    ]);
    expect(keywordText(['a', 'b'])).toBe('a, b');
  });

  it('reads places, teams, the always-a-person words and the hand-over message', () => {
    const m = routingModel(VIEW);
    expect(m.places).toEqual([
      { key: 'north', name: 'North', team: 'north', keywords: ['uptown'] },
      { key: 'south', name: 'South branch', team: 'south', keywords: [] },
    ]);
    expect(m.handoverCategory).toBe('complaint');
    expect(m.alwaysPerson).toEqual(['refund']);
    expect(m.keywordsEditable).toBe(true);
    expect(m.owner).toBe(true);
  });

  it('sends only what changed', () => {
    const m = routingModel(VIEW);
    const f = routingForm(m);
    expect(routingPatch(m, f)).toEqual({});
    f.places.north.keywords = 'uptown, Mall';
    f.places.south.name = 'South';
    f.teamDescriptions.south = 'The south team';
    f.alwaysPerson = 'refund, lawyer';
    f.handover.de = 'Gleich antwortet ein Kollege.';
    f.handoverOwners.en = 'A manager will reply personally.';
    expect(routingPatch(m, f)).toEqual({
      'rules.destination_keywords.north': ['uptown', 'mall'],
      'destinations.south.name': 'South',
      'team_descriptions.south': 'The south team',
      'rules.category_keywords.complaint': ['refund', 'lawyer'],
      'templates.handover.de': 'Gleich antwortet ein Kollege.',
      'templates.handover_owners.en': 'A manager will reply personally.',
    });
  });

  it('never sends keywords while the brain keeps them locked', () => {
    const m = routingModel({ ...VIEW, routing_editor: false });
    const f = routingForm(m);
    f.places.north.keywords = 'something else';
    f.alwaysPerson = 'other';
    expect(routingPatch(m, f)).toEqual({});
  });

  it('copes with a workspace without places or a hand-over category', () => {
    const m = routingModel({ version: 0, merged: {} });
    expect(m.places).toEqual([]);
    expect(m.handoverCategory).toBeNull();
    expect(routingPatch(m, routingForm(m))).toEqual({});
  });
});
