import {
  saveSms,
  previewSms,
  saveCrm,
  previewCrm,
  credentialFields,
  credentialLabelKey,
  crmMapRows,
  mapFromRows,
  runSummary,
  saveCommerce,
  syncCatalogue,
  orderStatus,
  ORDER_CHAT_CHANNELS,
  WIDGET_CHANNEL,
  channelLabelKey,
  parseHosts,
  orderChatSettings,
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

  it('sends only typed keys of the provider, never env var names', async () => {
    await saveSms(
      2,
      {
        provider: 'twilio',
        from: '+4917',
        key_env: 'OLD',
        account_sid_env: 'OLD',
      },
      { api_key: ' tok ', account_sid: '', api_secret: 'nope' }
    );
    const body = window.axios.post.mock.calls[0][1];
    expect(body.api_key).toBe('tok');
    expect(body).not.toHaveProperty('account_sid');
    expect(body).not.toHaveProperty('api_secret');
    expect(body).not.toHaveProperty('key_env');
    expect(body).not.toHaveProperty('account_sid_env');
    expect(body).not.toHaveProperty('clear_credentials');

    await saveSms(
      2,
      { provider: 'unifonic', from: 'ACME' },
      { account_sid: 'x' }
    );
    expect(window.axios.post.mock.calls[1][1]).not.toHaveProperty(
      'account_sid'
    );
  });

  it('removes one key with clear_credentials', async () => {
    await saveCrm(2, { provider: 'hubspot', key_env: 'HS' }, {}, ['api_key']);
    const crm = window.axios.post.mock.calls[0][1];
    expect(crm.clear_credentials).toEqual(['api_key']);
    expect(crm).not.toHaveProperty('key_env');
    expect(crm).not.toHaveProperty('api_key');

    await saveCommerce(
      2,
      {
        provider: 'woocommerce',
        shop_domain: 'shop.example.com',
        key_env: 'K',
        secret_env: 'S',
      },
      { api_key: 'ck_1' },
      ['api_secret']
    );
    const shop = window.axios.post.mock.calls[1][1];
    expect(shop).toMatchObject({
      api_key: 'ck_1',
      clear_credentials: ['api_secret'],
    });
    expect(shop).not.toHaveProperty('key_env');
    expect(shop).not.toHaveProperty('secret_env');
  });

  it('saves the order-in-chat settings: opt-in, trimmed pattern, numeric daily cap', async () => {
    await saveCommerce(2, {
      provider: 'shopify',
      shop_domain: 'a.myshopify.com',
    });
    expect(window.axios.post.mock.calls[0][1]).toMatchObject({
      order_chat: false,
      order_pattern: '',
    });
    expect(window.axios.post.mock.calls[0][1]).not.toHaveProperty(
      'order_lookups_per_day'
    );
    await saveCommerce(2, {
      provider: 'shopify',
      order_chat: true,
      order_pattern: ' #?\\d{4,8} ',
      order_lookups_per_day: '50',
    });
    expect(window.axios.post.mock.calls[1][1]).toMatchObject({
      order_chat: true,
      order_pattern: '#?\\d{4,8}',
      order_lookups_per_day: 50,
    });
    await saveCommerce(2, { provider: 'shopify', order_lookups_per_day: 0 });
    expect(window.axios.post.mock.calls[2][1].order_lookups_per_day).toBe(0);
  });

  it('asks for the credential fields of each provider, with provider labels', () => {
    expect(credentialFields('sms', 'twilio')).toEqual([
      'account_sid',
      'api_key',
    ]);
    expect(credentialFields('sms', 'unifonic')).toEqual(['api_key']);
    expect(credentialFields('crm', 'zoho')).toEqual(['api_key']);
    expect(credentialFields('commerce', 'zid')).toEqual([
      'api_key',
      'api_secret',
    ]);
    expect(credentialFields('commerce', 'shopify')).toEqual(['api_key']);
    expect(credentialLabelKey('commerce', 'woocommerce', 'api_secret')).toBe(
      'TOLZAR_SETTINGS.CHANNELS.CRED.woocommerce_api_secret'
    );
    expect(credentialLabelKey('crm', 'hubspot', 'api_key')).toBe(
      'TOLZAR_SETTINGS.CHANNELS.CRED.crm_api_key'
    );
  });

  it('saves the CRM mapping (api_domain only for Zoho) and previews a contact', async () => {
    await saveCrm(2, {
      provider: 'hubspot',
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

  it('summarises a dry run with the time in the viewer\'s locale, never the raw ISO slice', () => {
    const s = runSummary(
      {
        at: '2026-10-28T09:00:00+00:00',
        contacts_checked: 4,
        changes: [{}, {}],
        crm_read: false,
      },
      'en'
    );
    expect(s).toMatchObject({ checked: 4, changes: 2, crmRead: false });
    expect(s.at).toContain('2026');
    expect(s.at).not.toBe('2026-10-28 09:00');
    expect(s.at).not.toContain('T09');
    expect(runSummary({ at: '2026-10-28T09:00:00+00:00' }, 'de').at).toContain('2026');
    expect(runSummary(null).checked).toBe(0);
    expect(runSummary(null).at).toBe('');
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

  it('order chat: channel picker, widget only with allow_widget, tracking hosts', async () => {
    expect(ORDER_CHAT_CHANNELS).toContain(WIDGET_CHANNEL);
    expect(channelLabelKey('Channel::FacebookPage')).toBe(
      'TOLZAR_SETTINGS.CHANNELS.ORDER_CHANNEL.FacebookPage'
    );
    expect(
      parseHosts('Track.Example.com, https://x.example/a  track.example.com')
    ).toEqual(['track.example.com', 'x.example']);
    expect(
      orderChatSettings({
        order_chat_channels: [
          'Channel::Whatsapp',
          WIDGET_CHANNEL,
          'Channel::Bogus',
        ],
        allow_widget: false,
        tracking_hosts: 'a.example',
      })
    ).toEqual({
      order_chat_channels: ['Channel::Whatsapp'],
      allow_widget: false,
      tracking_hosts: ['a.example'],
    });
    expect(
      orderChatSettings({
        order_chat_channels: [WIDGET_CHANNEL],
        allow_widget: true,
      })
    ).toEqual({
      order_chat_channels: [WIDGET_CHANNEL],
      allow_widget: true,
      tracking_hosts: [],
    });
    expect(orderChatSettings({ allow_widget: true })).toEqual({
      order_chat_channels: [],
      allow_widget: false,
      tracking_hosts: [],
    });
    await saveCommerce(2, {
      provider: 'shopify',
      shop_domain: 'a.myshopify.com',
      order_chat: true,
      order_chat_channels: ['Channel::Email'],
      tracking_hosts: ['t.example'],
    });
    expect(window.axios.post.mock.calls.at(-1)[1]).toMatchObject({
      order_chat: true,
      order_chat_channels: ['Channel::Email'],
      allow_widget: false,
      tracking_hosts: ['t.example'],
    });
  });
});
