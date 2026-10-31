// Tolzar booking documents: the draft editor's pure helpers (DocumentsRegisterPanel.vue). The server checks
// everything again (Tolzar::DocumentSpec); these only keep the editor's total and placeholders honest.

export const PLACEHOLDER = /(\bTBC\b|\{\{.*?\}\}|\?\?)/i;

let seq = 0;
export function emptyLine() {
  seq += 1;
  return {
    key: `line-${seq}`,
    type: 'service',
    description: '',
    date: '',
    qty: '1',
    unit_price: '',
  };
}

const cents = v => {
  const n = Number(String(v ?? '').replace(',', '.'));
  return Number.isFinite(n) ? Math.round(n * 100) : 0;
};

export function lineCents(line) {
  if (PLACEHOLDER.test(String(line.unit_price))) return 0;
  const qty = String(line.qty ?? '').trim() === '' ? 1 : Number(line.qty);
  return Number.isFinite(qty) ? Math.round(qty * cents(line.unit_price)) : 0;
}

export function linesTotal(lines) {
  return (lines || []).reduce((sum, l) => sum + lineCents(l), 0);
}

// The editor's fields -> the document spec the API takes.
export function toSpec(d) {
  const guests = String(d.guests || '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean)
    .map(name => ({ name }));
  const lines = (d.lines || [])
    .filter(
      l =>
        String(l.description || '').trim() || String(l.unit_price || '').trim()
    )
    .map(l => ({
      type: l.type,
      description: String(l.description || '').trim(),
      qty: String(l.qty || '').trim() || '1',
      unit_price: String(l.unit_price || '').trim(),
      ...(l.date ? { date: l.date } : {}),
      // Bookings (c102): the last day, and who or what the line uses (a boat, a room, a guide).
      ...(l.until ? { until: l.until } : {}),
      ...(String(l.resource || '').trim()
        ? { resource: String(l.resource).trim() }
        : {}),
    }));
  const spec = { guests, lines };
  if (String(d.paid || '').trim())
    spec.payments = [{ amount: String(d.paid).trim() }];
  if (String(d.stated_total || '').trim())
    spec.stated_total = String(d.stated_total).trim();
  if (String(d.notes || '').trim()) spec.notes = d.notes.trim();
  if (String(d.terms || '').trim()) spec.terms = d.terms.trim();
  return spec;
}

// Whether a line type's pack shows a field (Tolzar::DocumentPacks.line_types, from documents_settings). Without
// the pack list every field shows, so the editor still works if the settings call failed.
export function showsField(lineTypes, type, field) {
  const fields = lineTypes && lineTypes[type];
  return Array.isArray(fields) ? fields.includes(field) : true;
}

export function isPlaceholder(value) {
  return PLACEHOLDER.test(String(value ?? ''));
}

// The panel's next step for a document: draft -> issue, issued -> send; cancelled has none.
export function nextStep(doc) {
  if (!doc) return null;
  if (doc.status === 'draft')
    return (doc.placeholders || []).length ? 'fill' : 'issue';
  return doc.status === 'issued' ? 'send' : null;
}

// The document logo (Tolzar::DocumentBranding::LOGO_MAX): a PNG or JPEG read into a data URL, kept in the workspace.
export const LOGO_MAX = 90000;

export function checkLogo(file, dataUrl) {
  if (!file || !['image/png', 'image/jpeg'].includes(file.type))
    return { error: 'type' };
  if (!dataUrl || dataUrl.length > LOGO_MAX) return { error: 'size' };
  return { dataUrl };
}

export function readLogo(file) {
  if (!file || !['image/png', 'image/jpeg'].includes(file.type))
    return Promise.resolve({ error: 'type' });
  return new Promise(resolve => {
    const reader = new FileReader();
    reader.onload = () => resolve(checkLogo(file, String(reader.result)));
    reader.onerror = () => resolve({ error: 'read' });
    reader.readAsDataURL(file);
  });
}
