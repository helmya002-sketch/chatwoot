import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync } from 'fs';
import { join } from 'path';

// Plan A5 (a): nothing from npm ends up in the widget. Every import in the app's own files (and its entry) is
// a relative path inside app/javascript/tolzar-widget.
const DIR = join(__dirname, '..');
const files = readdirSync(DIR)
  .filter(f => f.endsWith('.js'))
  .map(f => join(DIR, f))
  .concat(join(DIR, '..', 'entrypoints', 'tolzar_widget.js'));

describe('tolzar widget dependencies', () => {
  it('imports only its own modules', () => {
    files.forEach(file => {
      const src = readFileSync(file, 'utf8');
      const specs = [
        ...src.matchAll(/^\s*import\s[^'"]*['"]([^'"]+)['"]/gm),
      ].map(m => m[1]);
      specs.forEach(spec => {
        const own =
          spec.startsWith('./') || spec.startsWith('../tolzar-widget/');
        expect(own, `${file} imports ${spec}`).toBe(true);
      });
    });
  });
});
