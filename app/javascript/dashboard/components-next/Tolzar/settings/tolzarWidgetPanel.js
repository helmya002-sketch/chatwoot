// Tolzar website widget panel helpers (pure, unit-tested): WCAG contrast of white text on the widget colour.

function channel(c) {
  const v = c / 255;
  return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
}

export function luminance(hex) {
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || '').trim());
  if (!m) return null;
  const n = parseInt(m[1], 16);
  return (
    0.2126 * channel((n >> 16) & 255) +
    0.7152 * channel((n >> 8) & 255) +
    0.0722 * channel(n & 255)
  );
}

// Contrast of white text on the colour; null for an invalid colour.
export function whiteContrast(hex) {
  const l = luminance(hex);
  return l == null ? null : Math.round((1.05 / (l + 0.05)) * 100) / 100;
}

// 'aa' (≥ 4.5), 'large' (≥ 3, large text only) or 'fail'.
export function contrastLevel(hex) {
  const c = whiteContrast(hex);
  if (c == null) return 'fail';
  if (c >= 4.5) return 'aa';
  return c >= 3 ? 'large' : 'fail';
}
