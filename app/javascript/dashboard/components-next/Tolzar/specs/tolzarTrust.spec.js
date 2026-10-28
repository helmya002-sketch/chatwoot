import {
  DISCLOSURE_MODES,
  cleanTexts,
  saveDisclosure,
  saveRetention,
  exportContact,
  eraseContact,
  disclosureLine,
  validContactId,
  exportFilename,
} from '../tolzarTrust';

describe('tolzarTrust', () => {
  beforeEach(() => {
    window.axios = {
      get: vi.fn().mockResolvedValue({ data: { ok: true } }),
      post: vi.fn().mockResolvedValue({ data: { ok: true } }),
    };
  });

  it('offers auto / on / off disclosure only', () => {
    expect(DISCLOSURE_MODES).toEqual(['auto', 'on', 'off']);
  });

  it('saves the disclosure without empty overrides', async () => {
    expect(cleanTexts({ en: ' Hi ', de: '  ', fr: null })).toEqual({
      en: 'Hi',
    });
    await saveDisclosure(1, {
      disclosure: 'on',
      texts: { en: 'AI here', de: '' },
    });
    expect(window.axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/tolzar/brain/compliance',
      { disclosure: 'on', texts: { en: 'AI here' } }
    );
  });

  it('saves retention days as numbers', async () => {
    await saveRetention(1, { decisions_days: '90', kv_days: 30 });
    expect(window.axios.post.mock.calls[0][1]).toEqual({
      decisions_days: 90,
      kv_days: 30,
    });
  });

  it('exports and erases one contact through the owner-only features', async () => {
    await exportContact(1, '42');
    expect(window.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/tolzar/brain/dsar_export',
      { params: { contact_id: 42 } }
    );
    await eraseContact(1, '42');
    expect(window.axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/tolzar/brain/dsar_delete',
      { contact_id: 42 }
    );
  });

  it('shows the workspace line, else the generic one', () => {
    const defaults = { en: 'I am an AI', de: 'Ich bin KI' };
    expect(disclosureLine('de', { de: 'Eigene' }, defaults)).toBe('Eigene');
    expect(disclosureLine('de', {}, defaults)).toBe('Ich bin KI');
    expect(disclosureLine('xx', {}, defaults)).toBe('I am an AI');
  });

  it('accepts only real contact ids and names the export file', () => {
    expect(validContactId('12')).toBe(true);
    expect(validContactId('0')).toBe(false);
    expect(validContactId('1; drop')).toBe(false);
    expect(validContactId('')).toBe(false);
    expect(exportFilename(7, new Date('2026-10-28T10:00:00Z'))).toBe(
      'tolzar-contact-7-2026-10-28.json'
    );
  });
});
