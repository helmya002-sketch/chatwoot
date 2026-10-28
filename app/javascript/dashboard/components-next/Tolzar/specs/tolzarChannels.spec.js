import {
  saveSms,
  previewSms,
  smsEnvRows,
  saveCrm,
  previewCrm,
  crmEnvRows,
  crmMapRows,
  mapFromRows,
  runSummary,
  saveCommerce,
  syncCatalogue,
  orderStatus,
  commerceEnvRows,
} from '../tolzarChannels';

const url = f => `/api/v1/accounts/2/tolzar/brain/${f}`;

describe('tolzarChannels', () => {
  beforeEach(() => {
    window.axios = {
      get: vi.fn().mockResolvedValue({ data: { ok: true } }),
      post: vi.fn().mockResolvedValue({ data: { ok: true } }),
    };
  });

  it('always saves SMS in shadow, whatever the form holds', async () => {
    await saveSms(2, {
      provider: 'twilio',
      from: '+4917',
      key_env: 'TW_KEY',
      mode: 'live',
    });
    expect(window.axios.post.mock.calls[0][0]).toBe(url('sms'));
    expect(window.axios.post.mock.calls[0][1].mode).toBe('shadow');
    await previewSms(2, '+49170', 'Hi');
    expect(window.axios.post).toHaveBeenLastCalledWith(url('sms_preview'), {
      to: '+49170',
      text: 'Hi',
    });
  });

  it('shows env names and presence for SMS, CRM and the shop', () => {
    expect(
      smsEnvRows({
        settings: { key_env: 'TW_KEY', account_sid_env: 'TW_SID' },
        env_present: { key_env: true },
      })
    ).toEqual([
      { field: 'account_sid_env', name: 'TW_SID', present: false },
      { field: 'key_env', name: 'TW_KEY', present: true },
    ]);
    expect(
      crmEnvRows({ settings: { key_env: 'HS' }, key_present: true })
    ).toEqual([{ field: 'key_env', name: 'HS', present: true }]);
    expect(commerceEnvRows({ settings: {}, env_present: {} })).toEqual([]);
  });

  it('saves the CRM mapping (api_domain only for Zoho) and previews a contact', async () => {
    await saveCrm(2, {
      provider: 'hubspot',
      key_env: 'HS',
      direction: 'both',
      field_map: { email: 'email' },
      api_domain: 'x',
    });
    const body = window.axios.post.mock.calls[0][1];
    expect(body).toMatchObject({
      provider: 'hubspot',
      direction: 'both',
      read_crm: false,
      enabled: false,
    });
    expect(body).not.toHaveProperty('api_domain');
    await saveCrm(2, {
      provider: 'zoho',
      api_domain: 'https://www.zohoapis.eu',
    });
    expect(window.axios.post.mock.calls[1][1].api_domain).toBe(
      'https://www.zohoapis.eu'
    );
    await previewCrm(2, '9');
    expect(window.axios.post).toHaveBeenLastCalledWith(
      url('crm_sync_preview'),
      { contact_id: 9 }
    );
  });

  it('builds the mapping table and back', () => {
    const rows = crmMapRows(
      ['name', 'email'],
      { email: 'Email' },
      { name: 'a+b', email: 'email' }
    );
    expect(rows).toEqual([
      { field: 'name', crm: '', placeholder: 'a+b' },
      { field: 'email', crm: 'Email', placeholder: 'email' },
    ]);
    expect(mapFromRows(rows)).toEqual({ email: 'Email' });
  });

  it('summarises a dry run', () => {
    expect(
      runSummary({
        at: '2026-10-28T09:00:00+00:00',
        contacts_checked: 4,
        changes: [{}, {}],
        crm_read: false,
      })
    ).toEqual({
      at: '2026-10-28 09:00',
      checked: 4,
      changes: 2,
      crmRead: false,
    });
    expect(runSummary(null).checked).toBe(0);
  });

  it('connects a shop, syncs the catalogue and looks up an order', async () => {
    await saveCommerce(2, {
      provider: 'shopify',
      shop_domain: 'a.myshopify.com',
      agent_id: 'sales',
    });
    expect(window.axios.post.mock.calls[0][0]).toBe(url('commerce'));
    await syncCatalogue(2, 'sales');
    expect(window.axios.post).toHaveBeenLastCalledWith(
      url('commerce_catalogue_sync'),
      { agent_id: 'sales' }
    );
    await syncCatalogue(2);
    expect(window.axios.post).toHaveBeenLastCalledWith(
      url('commerce_catalogue_sync'),
      {}
    );
    await orderStatus(2, '1001');
    expect(window.axios.post).toHaveBeenLastCalledWith(
      url('commerce_order_status'),
      { order_number: '1001' }
    );
  });
});
