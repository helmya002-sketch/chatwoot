// Tolzar keyboard shortcut sheet (round 4, E2; account flag tolzar_inbox_tools): "?" opens the app's own shortcut
// sheet (WootKeyShortcutModal), which then also lists the keys the Tolzar screens use. Only keys that really work are
// listed here; labels live under TOLZAR_INBOX.SHORTCUTS.
export const TOLZAR_SHORTCUT_KEYS = [
  { id: 'help', label: 'SHOW_SHEET', displayKeys: ['?'] },
  { id: 'escape', label: 'CLOSE_MENU', displayKeys: ['Esc'] },
  { id: 'open', label: 'OPEN_FOCUSED', displayKeys: ['Enter', 'Space'] },
  { id: 'tab', label: 'MOVE_FOCUS', displayKeys: ['Tab', 'Shift + Tab'] },
];

const TYPEABLE = ['INPUT', 'TEXTAREA', 'SELECT', 'NINJA-KEYS'];

// True when focus is somewhere the person types (fields, the reply editor), so "?" stays a character there.
export const isTypingTarget = target => {
  if (!target) return false;
  if (TYPEABLE.includes(target.tagName)) return true;
  if (target.isContentEditable || target.contentEditable === 'true')
    return true;
  return String(target.className || '').includes('ProseMirror');
};

// True for a plain "?" press outside a text field (Shift is how "?" is typed, so it is allowed).
export const isShortcutSheetKey = e =>
  !!e &&
  e.key === '?' &&
  !e.ctrlKey &&
  !e.metaKey &&
  !e.altKey &&
  !e.repeat &&
  !isTypingTarget(e.target || document.activeElement);
