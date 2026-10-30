// Tolzar settings panels: the shared Tailwind class sets (same look as the Settings hub).
export const BTN =
  'inline-flex items-center h-9 mt-3 px-4 text-sm font-semibold rounded-xl text-white bg-n-brand border-0 cursor-pointer disabled:opacity-50';
export const BTN_GHOST =
  'inline-flex items-center h-9 mt-3 px-4 text-sm font-semibold rounded-xl text-n-slate-11 bg-n-solid-1 border border-solid border-n-weak cursor-pointer disabled:opacity-50';
export const BTN_DANGER =
  'inline-flex items-center h-9 mt-3 px-4 text-sm font-semibold rounded-xl text-white bg-n-ruby-9 border-0 cursor-pointer disabled:opacity-50';
export const INPUT =
  'box-border w-full px-2.5 py-2 text-[13px] text-n-slate-12 bg-n-solid-1 border border-solid border-n-weak rounded-lg outline-none';
export const LABEL = 'block mt-3 mb-1 text-xs text-n-slate-11';
export const CHECK = 'flex gap-2 items-center mt-3 text-sm text-n-slate-12';
// The old SHADOW_BADGE span is gone: every "runs, sends nothing" state is <ShadowBadge> now.
// Status tones in theme tokens (readable in light and dark; white-label safe).
export const TONE_WARN = 'text-n-amber-11 bg-n-amber-3';
export const TONE_OK = 'text-n-teal-11 bg-n-teal-3';
export const TONE_BAD = 'text-n-ruby-11 bg-n-ruby-3';
export const TONE_MUTED = 'text-n-slate-11 bg-n-slate-3';
// Icon-only buttons: always visible to keyboard users even when the design hides them until hover.
export const HOVER_REVEAL = 'opacity-0 group-hover:opacity-100 focus-visible:opacity-100 focus:opacity-100';
