import { fitScale, applyFit, standalonePage, MIN_SCALE } from '../emailFit';

describe('emailFit', () => {
  it('scales only content wider than the pane, never below the floor', () => {
    expect(fitScale(500, 600)).toBe(1);
    expect(fitScale(601, 600)).toBe(1);
    expect(fitScale(800, 600)).toBe(0.75);
    expect(fitScale(4000, 600)).toBe(MIN_SCALE);
    expect(fitScale(0, 600)).toBe(1);
  });

  it('applies the zoom to the inner element from its measured width', () => {
    const outer = { clientWidth: 400 };
    const inner = { scrollWidth: 800, style: { zoom: '' } };
    expect(applyFit(outer, inner)).toBe(0.5);
    expect(inner.style.zoom).toBe('0.5');
    inner.scrollWidth = 300;
    expect(applyFit(outer, inner)).toBe(1);
    expect(inner.style.zoom).toBe('');
  });

  it('wraps sanitised HTML in a printable page with an escaped title', () => {
    const page = standalonePage('<p>Hi</p>', { title: '<b>Offer</b>' });
    expect(page).toContain('<p>Hi</p>');
    expect(page).toContain('&#60;b&#62;Offer');
    expect(page).toContain('@media print');
  });
});
