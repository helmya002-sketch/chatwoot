import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync, existsSync } from 'fs';
import { join } from 'path';
import { gzipSync } from 'zlib';

// Plan A5 build checks: (b) the app stays within its size budget (the source, before minification, so the built
// bundle is smaller still); (c) no network call to any host other than the widget's own (relative URLs only:
// /api/v1/widget/*, /cable), and no inline-HTML sinks.
const DIR = join(__dirname, '..');
const SOURCES = readdirSync(DIR)
  .filter(f => /\.(js|css)$/.test(f))
  .map(f => ({ name: f, text: readFileSync(join(DIR, f), 'utf8') }));
const JS = SOURCES.filter(s => s.name.endsWith('.js'));
const APP_BUDGET_GZIP = 35 * 1024;

describe('tolzar widget build checks', () => {
  it('fits the 35 KB gzip budget (JS + CSS source)', () => {
    const all = Buffer.concat(SOURCES.map(s => Buffer.from(s.text)));
    expect(gzipSync(all).length).toBeLessThan(APP_BUDGET_GZIP);
  });

  it('calls only its own host: no absolute URL in fetch, WebSocket or src', () => {
    JS.forEach(({ name, text }) => {
      const absolute = text.match(
        /(fetch|WebSocket|src\s*=)\s*\(?\s*['"`]https?:\/\//g
      );
      expect(absolute, `${name} calls an absolute URL`).toBeNull();
      expect(text, `${name} builds an http URL`).not.toMatch(
        /['"`]https?:\/\/(?!localhost)[a-z]/i
      );
    });
    const api = JS.find(s => s.name === 'api.js').text;
    expect(api).toContain(
      ['`/api/v1/widget/$', '{path}?$', '{params}`'].join('')
    );
    expect(JS.find(s => s.name === 'cable.js').text).toContain(
      "new URL('/cable', base)"
    );
  });

  it('never writes HTML from strings', () => {
    JS.forEach(({ name, text }) => {
      expect(text, `${name} uses innerHTML`).not.toMatch(
        /\.(innerHTML|outerHTML)\s*=|insertAdjacentHTML|document\.write/
      );
      expect(text, `${name} uses eval`).not.toMatch(/\beval\(|new Function\(/);
    });
  });

  it('has its entry point and page', () => {
    expect(existsSync(join(DIR, '..', 'entrypoints', 'tolzar_widget.js'))).toBe(
      true
    );
    const page = readFileSync(
      join(DIR, '..', '..', 'views', 'widgets', 'tolzar.html.erb'),
      'utf8'
    );
    expect(page).toContain("vite_javascript_tag 'tolzar_widget'");
    expect(page).toContain('type="application/json" id="tz-widget-config"');
  });
});
