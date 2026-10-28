import {
  packUrl,
  fetchPack,
  clearPackCache,
  fieldLabel,
  contactPlace,
  packRows,
  EMPTY_PACK,
} from '../tolzarPack';

const DIVE = {
  ok: true,
  pack: 'tourism-dive',
  fields: [
    {
      key: 'hotel',
      field: 'place_detail',
      kind: 'place',
      label: { en: 'Hotel', de: 'Hotel' },
    },
    {
      key: 'trip_start_date',
      field: 'trip_start',
      kind: 'date',
      label: { en: 'Trip starts', de: 'Reisebeginn' },
    },
    {
      key: 'certification_level',
      field: 'certification',
      kind: 'level',
      label: { en: 'Certification' },
    },
  ],
};
const t = key => `t:${key}`;

describe('tolzarPack', () => {
  beforeEach(() => {
    clearPackCache();
    window.axios = { get: vi.fn() };
  });

  it('reads the pack once per workspace from the read-only door', async () => {
    window.axios.get.mockResolvedValue({ data: DIVE });
    expect(packUrl(3)).toBe('/api/v1/accounts/3/tolzar/pack');
    const a = await fetchPack(3);
    await fetchPack(3);
    expect(window.axios.get).toHaveBeenCalledTimes(1);
    expect(a.pack).toBe('tourism-dive');
    expect(a.fields.map(f => f.key)).toEqual([
      'hotel',
      'trip_start_date',
      'certification_level',
    ]);
  });

  it('shows the generic core only when the brain is not reachable, and retries later', async () => {
    window.axios.get.mockRejectedValueOnce(new Error('offline'));
    expect(await fetchPack(4)).toEqual(EMPTY_PACK);
    window.axios.get.mockResolvedValue({ data: DIVE });
    expect((await fetchPack(4)).pack).toBe('tourism-dive');
    expect(await fetchPack(null)).toEqual(EMPTY_PACK);
  });

  it('labels a field in the UI language, then English, then its generic kind', () => {
    const [hotel, trip, cert] = DIVE.fields;
    expect(fieldLabel(trip, 'de', t)).toBe('Reisebeginn');
    expect(fieldLabel(trip, 'fr-FR', t)).toBe('Trip starts');
    expect(fieldLabel({ ...cert, label: {} }, 'en', t)).toBe(
      't:TOLZAR_CONTACTS.PANE.KIND.LEVEL'
    );
    expect(fieldLabel({ key: 'x', kind: 'odd', label: {} }, 'en', t)).toBe(
      't:TOLZAR_CONTACTS.PANE.KIND.TEXT'
    );
    expect(fieldLabel(hotel, 'de_DE', t)).toBe('Hotel');
  });

  it('puts the pack place first in the table, then the core place', () => {
    const pack = { fields: DIVE.fields };
    expect(contactPlace(pack, { hotel: 'Rixos', location: 'Sharm' })).toBe(
      'Rixos'
    );
    expect(contactPlace(pack, { location: 'Sharm' })).toBe('Sharm');
    expect(
      contactPlace(EMPTY_PACK, { hotel: 'Rixos' }, { city: 'Cairo' })
    ).toBe('Cairo');
  });

  it('splits the pane rows around the core place', () => {
    const rows = packRows(
      { fields: DIVE.fields },
      { hotel: 'Rixos', trip_start_date: '2026-11-02' },
      'en',
      t
    );
    expect(rows.places).toEqual([['Hotel', 'Rixos']]);
    expect(rows.others).toEqual([
      ['Trip starts', '2026-11-02'],
      ['Certification', undefined],
    ]);
    expect(packRows(EMPTY_PACK, {}, 'en', t)).toEqual({
      places: [],
      others: [],
    });
  });
});
