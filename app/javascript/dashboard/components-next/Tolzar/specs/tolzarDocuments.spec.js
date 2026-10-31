import { describe, it, expect } from 'vitest';
import {
  emptyLine,
  lineCents,
  linesTotal,
  toSpec,
  showsField,
  isPlaceholder,
  nextStep,
  checkLogo,
  LOGO_MAX,
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

describe('tolzarDocuments panel helpers', () => {
  const packs = { room_night: ['date', 'until', 'nights'], extra: ['qty'] };

  it('shows only the fields of the line type pack, or all without packs', () => {
    expect(showsField(packs, 'room_night', 'nights')).toBe(true);
    expect(showsField(packs, 'extra', 'date')).toBe(false);
    expect(showsField(null, 'extra', 'date')).toBe(true);
    expect(showsField(packs, 'unknown', 'date')).toBe(true);
  });

  it('finds placeholders', () => {
    expect(isPlaceholder('TBC')).toBe(true);
    expect(isPlaceholder('{{date}}')).toBe(true);
    expect(isPlaceholder('120')).toBe(false);
    expect(isPlaceholder(null)).toBe(false);
  });

  it('gives the next step', () => {
    expect(
      nextStep({ status: 'draft', placeholders: ['lines.0.unit_price'] })
    ).toBe('fill');
    expect(nextStep({ status: 'draft', placeholders: [] })).toBe('issue');
    expect(nextStep({ status: 'issued' })).toBe('send');
    expect(nextStep({ status: 'void' })).toBeNull();
    expect(nextStep(null)).toBeNull();
  });
});

describe('tolzarDocuments logo', () => {
  it('takes a small PNG or JPEG only', () => {
    const png = { type: 'image/png' };
    expect(checkLogo(png, 'data:image/png;base64,AAAA')).toEqual({
      dataUrl: 'data:image/png;base64,AAAA',
    });
    expect(checkLogo({ type: 'image/svg+xml' }, 'data:x')).toEqual({
      error: 'type',
    });
    expect(
      checkLogo(png, `data:image/png;base64,${'A'.repeat(LOGO_MAX)}`)
    ).toEqual({
      error: 'size',
    });
    expect(checkLogo(null, null)).toEqual({ error: 'type' });
  });
});
