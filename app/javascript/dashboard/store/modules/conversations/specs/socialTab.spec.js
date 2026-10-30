import { applyPageFilters, filterBySocial } from '../helpers';

// Tolzar's optional Social tab: comment threads only in the Social view, and out of the other views when on.
describe('#filterBySocial', () => {
  it('keeps everything with the setting off', () => {
    expect(filterBySocial(true, undefined, false, true)).toBe(true);
    expect(filterBySocial(true, undefined, false, false)).toBe(true);
  });

  it('moves comment threads out of the normal views with the setting on', () => {
    expect(filterBySocial(true, undefined, true, true)).toBe(false);
    expect(filterBySocial(true, 'mention', true, true)).toBe(false);
    expect(filterBySocial(true, undefined, true, false)).toBe(true);
  });

  it('shows only comment threads in the Social view', () => {
    expect(filterBySocial(true, 'social', true, true)).toBe(true);
    expect(filterBySocial(true, 'social', true, false)).toBe(false);
    expect(filterBySocial(false, 'social', true, true)).toBe(false);
  });
});

describe('#applyPageFilters with the Social tab', () => {
  const comment = {
    status: 'open',
    inbox_id: 1,
    meta: {},
    additional_attributes: { tolzar_comment: { platform: 'facebook' } },
  };
  const dm = { status: 'open', inbox_id: 1, meta: {}, additional_attributes: {} };

  it('reads the comment marker from the conversation', () => {
    const on = { status: 'open', socialTab: true };
    expect(applyPageFilters(comment, on)).toBe(false);
    expect(applyPageFilters(dm, on)).toBe(true);
    expect(applyPageFilters(comment, { ...on, conversationType: 'social' })).toBe(true);
    expect(applyPageFilters(comment, { status: 'open' })).toBe(true);
  });
});
