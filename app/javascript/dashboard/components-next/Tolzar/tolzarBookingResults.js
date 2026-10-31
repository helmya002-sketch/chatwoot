// Tolzar Results → Bookings card helpers (pure, unit-tested): the API's report (Tolzar::BookingResults) as rows the
// card shows. Money stays per currency; a part that is switched off (null) is left out.

const STATUS_ORDER = ['draft', 'confirmed', 'completed', 'cancelled'];
const TYPE_ORDER = ['voucher', 'quote', 'confirmation', 'payment_summary'];

export function money(cents, currency, locale = 'en') {
  const value = Number(cents || 0) / 100;
  try {
    return new Intl.NumberFormat(locale, {
      style: 'currency',
      currency,
    }).format(value);
  } catch {
    return `${currency || ''} ${value.toFixed(2)}`.trim();
  }
}

export function resultsView(report) {
  const r = report || {};
  const docs = r.documents;
  const books = r.bookings;
  return {
    days: r.days || 30,
    documents: docs
      ? {
          issued: docs.issued || 0,
          cancelled: docs.cancelled || 0,
          byType: TYPE_ORDER.filter(ty => (docs.by_type || {})[ty]).map(ty => ({
            type: ty,
            n: docs.by_type[ty],
          })),
          money: docs.money || [],
        }
      : null,
    bookings: books
      ? {
          byStatus: STATUS_ORDER.map(st => ({
            status: st,
            n: (books.by_status || {})[st] || 0,
          })),
          money: books.money || [],
        }
      : null,
  };
}
