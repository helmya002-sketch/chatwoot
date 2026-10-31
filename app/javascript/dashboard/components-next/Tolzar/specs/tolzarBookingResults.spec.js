import { describe, it, expect } from 'vitest';
import { money, resultsView } from '../tolzarBookingResults';

describe('tolzarBookingResults', () => {
  it('formats money per currency', () => {
    expect(money(12050, 'EUR', 'en')).toBe('€120.50');
    expect(money(0, 'USD', 'en')).toBe('$0.00');
    expect(money(100, 'NOPE', 'en')).toBe('NOPE 1.00');
  });

  it('keeps switched-off parts out and orders statuses and types', () => {
    const v = resultsView({
      days: 7,
      documents: {
        issued: 3,
        cancelled: 1,
        by_type: { quote: 2, voucher: 1 },
        money: [{ currency: 'EUR', total_cents: 9000 }],
      },
      bookings: null,
    });
    expect(v.days).toBe(7);
    expect(v.bookings).toBeNull();
    expect(v.documents.byType).toEqual([
      { type: 'voucher', n: 1 },
      { type: 'quote', n: 2 },
    ]);
  });

  it('fills every booking status, zero when missing', () => {
    const v = resultsView({ bookings: { by_status: { confirmed: 4 } } });
    expect(v.bookings.byStatus.map(s => s.n)).toEqual([0, 4, 0, 0]);
    expect(v.documents).toBeNull();
    expect(resultsView(null).days).toBe(30);
  });
});
