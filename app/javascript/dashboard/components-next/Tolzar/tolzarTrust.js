// Tolzar "Trust & privacy": AI disclosure (plugins/compliance.py), retention (retention.py) and
// one contact's brain data, GDPR export / erasure (dsar.py).
import { brainGet, brainPost } from './tolzarBrainApi';

export const DISCLOSURE_MODES = ['auto', 'on', 'off'];
export const DISCLOSURE_LANGS = ['en', 'de', 'fr', 'ar', 'it', 'es'];

// Empty overrides fall back to the generic line: don't store them.
export const cleanTexts = texts =>
  Object.fromEntries(
    Object.entries(texts || {})
      .map(([k, v]) => [k, String(v || '').trim()])
      .filter(([, v]) => v)
  );

export const getDisclosure = accountId => brainGet(accountId, 'compliance');
export const saveDisclosure = (accountId, { disclosure, texts }) =>
  brainPost(accountId, 'compliance', { disclosure, texts: cleanTexts(texts) });

export const getRetention = accountId => brainGet(accountId, 'retention');
export const saveRetention = (accountId, cfg) =>
  brainPost(accountId, 'retention', {
    decisions_days: Number(cfg.decisions_days),
    kv_days: Number(cfg.kv_days),
    // The audit field was shown but never sent (29 Oct QA): every save reset it in the brain.
    ...(cfg.audit_days === undefined ? {} : { audit_days: Number(cfg.audit_days) }),
  });

export const exportContact = (accountId, contactId) =>
  brainGet(accountId, 'dsar_export', { contact_id: Number(contactId) });
export const eraseContact = (accountId, contactId) =>
  brainPost(accountId, 'dsar_delete', { contact_id: Number(contactId) });

// The line each language would show: the workspace's own text, else the generic one.
export const disclosureLine = (lang, texts, defaults) =>
  (texts && texts[lang]) ||
  (defaults && defaults[lang]) ||
  (defaults && defaults.en) ||
  '';

export const validContactId = v =>
  /^\d+$/.test(String(v ?? '').trim()) && Number(v) > 0;

export const exportFilename = (contactId, at = new Date()) =>
  `tolzar-contact-${contactId}-${at.toISOString().slice(0, 10)}.json`;
