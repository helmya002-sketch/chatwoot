// Tolzar: the open-source notices of the JavaScript packages shipped in the browser bundles (the
// production "dependencies" of package.json and everything they depend on; devDependencies are build
// tools and are not shipped). Run in the image build, after `pnpm i` and before node_modules is removed:
//
//   node docker/tolzar/js_notices.mjs [package.json dir] > config/tolzar/js_notices.json
//
// Tolzar::OpenSourceNotices reads the JSON and shows it on the in-app "Open-source licences" page.
import fs from 'node:fs';
import path from 'node:path';

const LICENCE_FILE =
  /^(licen[cs]e|copying|notice|mit-licen[cs]e|unlicen[cs]e)(\.|-|$)/i;
const MAX_TEXT = 64 * 1024;
const root = path.resolve(process.argv[2] || '.');

const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'));

// The directory of `name` as node resolves it from `fromDir` (walks up the node_modules chain).
const findPackage = (name, fromDir) => {
  let dir = fromDir;
  for (;;) {
    const candidate = path.join(dir, 'node_modules', name, 'package.json');
    if (fs.existsSync(candidate))
      return fs.realpathSync(path.dirname(candidate));
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
};

const licenceOf = pkg => {
  if (typeof pkg.license === 'string') return pkg.license;
  if (pkg.license && pkg.license.type) return pkg.license.type;
  if (Array.isArray(pkg.licenses))
    return pkg.licenses.map(l => (l && l.type) || String(l)).join(' OR ');
  return 'UNKNOWN';
};

const licenceText = dir =>
  fs
    .readdirSync(dir)
    .filter(
      f => LICENCE_FILE.test(f) && fs.statSync(path.join(dir, f)).isFile()
    )
    .sort()
    .map(f => fs.readFileSync(path.join(dir, f), 'utf8').slice(0, MAX_TEXT))
    .join('\n\n');

const homepageOf = pkg => {
  const repo = pkg.repository;
  const url = (repo && (typeof repo === 'string' ? repo : repo.url)) || '';
  return pkg.homepage || url.replace(/^git\+/, '').replace(/\.git$/, '') || '';
};

const seen = new Map();
const missing = [];
const visit = (name, fromDir) => {
  const dir = findPackage(name, fromDir);
  if (!dir) {
    missing.push(name);
    return;
  }
  if (seen.has(dir)) return;
  const pkg = readJson(path.join(dir, 'package.json'));
  seen.set(dir, {
    name: pkg.name || name,
    version: pkg.version || '',
    licences: [licenceOf(pkg)],
    homepage: homepageOf(pkg),
    author:
      typeof pkg.author === 'string'
        ? pkg.author
        : (pkg.author && pkg.author.name) || '',
    text: licenceText(dir),
  });
  Object.keys({ ...pkg.dependencies, ...pkg.optionalDependencies }).forEach(
    dep => visit(dep, dir)
  );
};

const app = readJson(path.join(root, 'package.json'));
Object.keys(app.dependencies || {}).forEach(dep => visit(dep, root));

const items = [...seen.values()].sort(
  (a, b) => a.name.localeCompare(b.name) || a.version.localeCompare(b.version)
);
process.stdout.write(
  `${JSON.stringify({ generated_at: new Date().toISOString(), items, missing: [...new Set(missing)].sort() })}\n`
);
