import { describe, it, expect } from 'vitest';
import {
  safeLogoUrl,
  tolzarBrand,
  DEFAULT_PRODUCT_NAME,
  DEFAULT_FAVICON,
} from '../TolzarBranding.vue';

describe('TolzarBranding', () => {
  it('only lets an https image URL become the tab icon', () => {
    expect(safeLogoUrl('https://cdn.example.com/logo.png')).toBe(
      'https://cdn.example.com/logo.png'
    );
    expect(safeLogoUrl('https://cdn.example.com/a/b.SVG?v=2')).toContain(
      'b.SVG'
    );
    expect(safeLogoUrl('http://cdn.example.com/logo.png')).toBe('');
    expect(safeLogoUrl('https://cdn.example.com/logo.html')).toBe('');
    expect(safeLogoUrl('https://cdn.example.com/')).toBe('');
    expect(safeLogoUrl(['java', 'script:alert(1)'].join(''))).toBe('');
    expect(safeLogoUrl('')).toBe('');
    expect(safeLogoUrl(null)).toBe('');
  });

  it('restores the product icon from a constant path, not a captured one', () => {
    expect(DEFAULT_FAVICON).toBe('/favicon-32x32.png');
  });

  it('starts with the product name so no component needs a literal', () => {
    expect(tolzarBrand.productName).toBe(DEFAULT_PRODUCT_NAME);
    expect(DEFAULT_PRODUCT_NAME).toBe('Tolzar');
  });
});
