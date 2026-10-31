// Tolzar: wide HTML e-mails (600–800 px newsletters) fit the reading pane instead of scrolling sideways.
// The sanitised e-mail renders with responsive rules first (letter-render CSS in Index.vue); whatever is still wider
// than the pane is scaled down with CSS zoom from the measured scrollWidth. Never below MIN_SCALE: beyond that the
// "Open full email" view is the better way to read it.

export const MIN_SCALE = 0.45;

// The zoom that makes content of `contentWidth` fit `paneWidth` (1 = no change).
export const fitScale = (contentWidth, paneWidth) => {
  const content = Number(contentWidth) || 0;
  const pane = Number(paneWidth) || 0;
  if (!content || !pane || content <= pane + 1) return 1;
  return Math.max(MIN_SCALE, Math.floor((pane / content) * 1000) / 1000);
};

// Measures `inner` inside `outer` and sets the zoom; returns the scale applied.
export const applyFit = (outer, inner) => {
  if (!outer || !inner) return 1;
  inner.style.zoom = '';
  const scale = fitScale(inner.scrollWidth, outer.clientWidth);
  inner.style.zoom = scale === 1 ? '' : String(scale);
  return scale;
};

// A standalone, printable page around already-sanitised e-mail HTML (for "Open in new window" and print).
export const standalonePage = (bodyHtml, { title = '', dir = 'auto' } = {}) => {
  const safeTitle = String(title).replace(
    /[<>&"]/g,
    c => `&#${c.charCodeAt(0)};`
  );
  return `<!doctype html><html dir="${dir === 'rtl' ? 'rtl' : 'auto'}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>${safeTitle}</title>
<style>body{margin:24px auto;max-width:960px;padding:0 16px;font:15px/1.55 Inter,Arial,sans-serif;color:#0F172A;background:#fff}
img{max-width:100%;height:auto}pre{white-space:pre-wrap}a{overflow-wrap:anywhere}
@media print{body{margin:0;max-width:none}}</style></head><body>${bodyHtml}</body></html>`;
};
