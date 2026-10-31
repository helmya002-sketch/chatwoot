import { describe, it, expect } from 'vitest';
import {
  emptyLine,
  lineCents,
  linesTotal,
  toSpec,
} from '../settings/tolzarDocuments';

describe('tolzarDocuments', () => {
  it('computes line amounts, a discount, and skips a TBC price', () => {
    expect(lineCents({ qty: '2', unit_price: '350.00' })).toBe(70000);
    expect(lineCents({ qty: '', unit_price: '45,5' })).toBe(4550);
    expect(lineCents({ qty: '1', unit_price: 'TBC' })).toBe(0);
    expect(
      linesTotal([
        { qty: '2', unit_price: '350' },
        { qty: '1', unit_price: '-40' },
      ])
    ).toBe(66000);
  });

  it('builds the spec from the editor, dropping empty lines', () => {
    const spec = toSpec({
      guests: 'Sara, Omar ,',
      lines: [
        {
          ...emptyLine(),
          type: 'course',
          description: ' Open Water ',
          qty: '2',
          unit_price: '350',
          date: '2026-12-01',
        },
        emptyLine(),
      ],
      paid: '200',
      stated_total: '',
      notes: ' Meet at 8 ',
      terms: '',
    });
    expect(spec).toEqual({
      guests: [{ name: 'Sara' }, { name: 'Omar' }],
      lines: [
        {
          type: 'course',
          description: 'Open Water',
          qty: '2',
          unit_price: '350',
          date: '2026-12-01',
        },
      ],
      payments: [{ amount: '200' }],
      notes: 'Meet at 8',
    });
  });
});
