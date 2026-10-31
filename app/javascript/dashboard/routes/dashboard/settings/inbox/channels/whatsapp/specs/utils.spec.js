import {
  initWhatsAppEmbeddedSignup,
  classifySignupEvent,
  SIGNUP_RESULT,
} from '../utils';

describe('WhatsApp Embedded Signup launch (v4)', () => {
  afterEach(() => {
    delete window.FB;
  });

  it('opens the v4 flow: the configuration id, a code, coexistence offered, no v3 session info', async () => {
    let options;
    window.FB = {
      login: (callback, opts) => {
        options = opts;
        callback({ authResponse: { code: 'abc' } });
      },
    };
    await expect(initWhatsAppEmbeddedSignup('cfg-1')).resolves.toBe('abc');
    expect(options.config_id).toBe('cfg-1');
    expect(options.response_type).toBe('code');
    expect(options.extras.featureType).toBe('whatsapp_business_app_onboarding');
    expect(options.extras).not.toHaveProperty('sessionInfoVersion');
  });

  it('reads the v4 finish, coexistence, cancel and error events', () => {
    expect(classifySignupEvent({ event: 'FINISH' }).type).toBe(
      SIGNUP_RESULT.FINISH
    );
    expect(
      classifySignupEvent({ event: 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING' })
        .isCoexistence
    ).toBe(true);
    expect(classifySignupEvent({ event: 'FINISH_ONLY_WABA' }).type).toBe(
      SIGNUP_RESULT.UNSUPPORTED
    );
    expect(
      classifySignupEvent({ event: 'CANCEL', data: { current_step: 'PHONE' } })
        .type
    ).toBe(SIGNUP_RESULT.CANCEL);
    expect(
      classifySignupEvent({ event: 'ERROR', error_message: 'x' }).type
    ).toBe(SIGNUP_RESULT.ERROR);
  });
});
