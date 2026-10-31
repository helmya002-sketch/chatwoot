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
