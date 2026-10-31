// Tolzar: every translated Tolzar locale file (dashboard JSON and the tolzar: block of config/locales) has exactly
// the English keys and keeps every placeholder and plural "|" form, so a translated screen never shows a raw key.
import enAgents from '../locale/en/tolzarAgents.json';
import enDashboard from '../locale/en/tolzarDashboard.json';
import enInbox from '../locale/en/tolzarInbox.json';
import enPwa from '../locale/en/tolzarPwa.json';
import enSettingsUi from '../locale/en/tolzarSettingsUi.json';
import enUi from '../locale/en/tolzarUi.json';
import arAgents from '../locale/ar/tolzarAgents.json';
import arDashboard from '../locale/ar/tolzarDashboard.json';
import arInbox from '../locale/ar/tolzarInbox.json';
import arPwa from '../locale/ar/tolzarPwa.json';
import arSettingsUi from '../locale/ar/tolzarSettingsUi.json';
import arUi from '../locale/ar/tolzarUi.json';
import arIndex from '../locale/ar';
import enYml from '../../../../../config/locales/en.yml';
import arYml from '../../../../../config/locales/ar.yml';
import deAgents from '../locale/de/tolzarAgents.json';
import deDashboard from '../locale/de/tolzarDashboard.json';
import deInbox from '../locale/de/tolzarInbox.json';
import dePwa from '../locale/de/tolzarPwa.json';
import deSettingsUi from '../locale/de/tolzarSettingsUi.json';
import deUi from '../locale/de/tolzarUi.json';
import deIndex from '../locale/de';
import deYml from '../../../../../config/locales/de.yml';

const EN = {
  tolzarAgents: enAgents,
  tolzarDashboard: enDashboard,
  tolzarInbox: enInbox,
  tolzarPwa: enPwa,
  tolzarSettingsUi: enSettingsUi,
  tolzarUi: enUi,
};

const LOCALES = {
  ar: {
    index: arIndex,
    yml: arYml.ar.tolzar,
    files: {
      tolzarAgents: arAgents,
      tolzarDashboard: arDashboard,
      tolzarInbox: arInbox,
      tolzarPwa: arPwa,
      tolzarSettingsUi: arSettingsUi,
      tolzarUi: arUi,
    },
  },
  de: {
    index: deIndex,
    yml: deYml.de.tolzar,
    files: {
      tolzarAgents: deAgents,
      tolzarDashboard: deDashboard,
      tolzarInbox: deInbox,
      tolzarPwa: dePwa,
      tolzarSettingsUi: deSettingsUi,
      tolzarUi: deUi,
    },
  },
};

const flatten = (obj, prefix = '') =>
  Object.entries(obj).reduce((acc, [key, value]) => {
    const path = prefix ? `${prefix}.${key}` : key;
    if (value && typeof value === 'object') {
      return { ...acc, ...flatten(value, path) };
    }
    return { ...acc, [path]: value };
  }, {});

const placeholders = text => (String(text).match(/\{[^{}]*\}/g) || []).sort();
const pluralForms = text => String(text).split(' | ').length;
const railsPlaceholders = text =>
  (String(text).match(/%\{[^{}]*\}/g) || []).sort();

describe('Tolzar locale parity', () => {
  Object.entries(LOCALES).forEach(([locale, { index, yml, files }]) => {
    describe(locale, () => {
      it('config/locales tolzar block: same keys and %{placeholders}', () => {
        const enFlat = flatten(enYml.en.tolzar);
        const trFlat = flatten(yml);
        expect(Object.keys(trFlat).sort()).toEqual(Object.keys(enFlat).sort());
        Object.entries(enFlat).forEach(([key, value]) => {
          expect([key, railsPlaceholders(trFlat[key])]).toEqual([
            key,
            railsPlaceholders(value),
          ]);
        });
      });

      Object.entries(EN).forEach(([name, en]) => {
        const enFlat = flatten(en);
        const trFlat = flatten(files[name]);

        it(`${name}: same keys as English`, () => {
          expect(Object.keys(trFlat).sort()).toEqual(
            Object.keys(enFlat).sort()
          );
        });

        it(`${name}: keeps every placeholder and plural form`, () => {
          Object.entries(enFlat).forEach(([key, value]) => {
            expect([key, placeholders(trFlat[key])]).toEqual([
              key,
              placeholders(value),
            ]);
            expect([key, pluralForms(trFlat[key])]).toEqual([
              key,
              pluralForms(value),
            ]);
          });
        });

        it(`${name}: is loaded by the ${locale} locale index`, () => {
          Object.keys(files[name]).forEach(top => {
            expect(index[top]).toEqual(files[name][top]);
          });
        });
      });
    });
  });
});
