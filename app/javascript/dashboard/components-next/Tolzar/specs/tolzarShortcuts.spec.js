import {
  isShortcutSheetKey,
  isTypingTarget,
  TOLZAR_SHORTCUT_KEYS,
} from '../tolzarShortcuts';

const key = (k, extra = {}) => ({
  key: k,
  target: { tagName: 'DIV', className: '' },
  ...extra,
});

describe('tolzarShortcuts', () => {
  it('opens the sheet on a plain "?" outside text fields', () => {
    expect(isShortcutSheetKey(key('?', { shiftKey: true }))).toBe(true);
    expect(isShortcutSheetKey(key('/'))).toBe(false);
    expect(isShortcutSheetKey(key('?', { ctrlKey: true }))).toBe(false);
    expect(isShortcutSheetKey(key('?', { metaKey: true }))).toBe(false);
    expect(isShortcutSheetKey(key('?', { repeat: true }))).toBe(false);
    expect(isShortcutSheetKey(null)).toBe(false);
  });

  it('leaves "?" alone while typing', () => {
    expect(isShortcutSheetKey(key('?', { target: { tagName: 'INPUT' } }))).toBe(
      false
    );
    expect(isTypingTarget({ tagName: 'TEXTAREA' })).toBe(true);
    expect(isTypingTarget({ tagName: 'SELECT' })).toBe(true);
    expect(isTypingTarget({ tagName: 'DIV', isContentEditable: true })).toBe(
      true
    );
    expect(
      isTypingTarget({ tagName: 'DIV', className: 'ProseMirror-focused' })
    ).toBe(true);
    expect(isTypingTarget({ tagName: 'BUTTON', className: '' })).toBe(false);
  });

  it('lists each shortcut once with keys to show', () => {
    const ids = TOLZAR_SHORTCUT_KEYS.map(s => s.id);
    expect(new Set(ids).size).toBe(ids.length);
    TOLZAR_SHORTCUT_KEYS.forEach(s =>
      expect(s.displayKeys.length).toBeGreaterThan(0)
    );
  });
});
