<script setup>
/**
 * Tolzar copilot card — surfaces the brain's read of THIS conversation inline in the
 * thread: intent + confidence + lead score, a one-line summary, and the suggested
 * reply, clearly marked as an AI draft. The card never sends anything:
 *  - in a normal inbox, "Use reply" drops the draft into the composer for the agent to
 *    review and send;
 *  - in a listen-only inbox (staff answer from the business's own tool, the composer is
 *    private-note only) the button is "Copy reply" and nothing is inserted.
 * Reads the custom attributes the brain writes (shadow-safe); hides when there is
 * nothing to show. "Why this reply?" (WhyPanel) reads the brain's /explain on demand: what the draft
 * is based on and which checks passed.
 */
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { tolzarBrand } from './TolzarBranding.vue';
import WhyPanel from './WhyPanel.vue';
import { brainGet } from './tolzarBrainApi';
import { checkChips, sourcesLine } from './tolzarReadingPane';

const { t } = useI18n();
const store = useStore();
const chat = useMapGetter('getSelectedChat');
const convAttrs = computed(() => chat.value?.custom_attributes || {});
const contactAttrs = computed(
  () => chat.value?.meta?.sender?.custom_attributes || {}
);
const product = computed(() => tolzarBrand.productName);

// Listen-only inboxes (Tolzar::ListenOnly / mirror): the inbox JSON carries the flag.
const inbox = computed(() =>
  chat.value?.inbox_id
    ? store.getters['inboxes/getInbox'](chat.value.inbox_id)
    : null
);
const isListenOnly = computed(() => inbox.value?.tolzar_listen_only === true);

// The brain's triage category; a workspace's own categories show as written ("trade_partner" ->
// "Trade partner").
const INTENT_KEYS = { lead: 'LEAD', job: 'JOB', spam: 'SPAM', other: 'OTHER' };
const intent = computed(() => {
  const c = String(convAttrs.value.triage_category || '');
  if (!c) return '';
  if (INTENT_KEYS[c]) return t(`TOLZAR_INBOX.COPILOT.INTENT.${INTENT_KEYS[c]}`);
  const words = c.replace(/[_-]+/g, ' ').trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
});
const confidence = computed(() => {
  const c = Number(convAttrs.value.brain_confidence);
  return Number.isFinite(c) ? Math.round(c * 100) : null;
});
// In shadow the brain writes no conversation fields (only its private note), so the card falls back
// to the brain's latest decision for this conversation (/explain): its draft reply. Admins only; for
// anyone else the request is refused and the card stays as it was.
const accountId = useMapGetter('getCurrentAccountId');
const decisionReply = ref('');
const decision = ref(null);
// UI phase 3 (new UI only): the checks and the sources of the draft inline, from the same decision.
const newUi = document.body.classList.contains('tz-ui');
const loadDecision = async id => {
  decisionReply.value = '';
  decision.value = null;
  if (!id || (convAttrs.value.tolzar_suggested_reply && !newUi)) return;
  try {
    const res = await brainGet(accountId.value, 'explain', {
      conversation_id: id,
    });
    if (chat.value?.id === id && res?.ok) {
      decisionReply.value = (res.explanation?.reply || '').trim();
      decision.value = res.explanation || null;
    }
  } catch (e) {
    decisionReply.value = '';
  }
};
watch(() => chat.value?.id, loadDecision, { immediate: true });
const suggestedReply = computed(
  () =>
    (convAttrs.value.tolzar_suggested_reply || '').trim() || decisionReply.value
);
const summary = computed(() =>
  (contactAttrs.value.tolzar_summary || '').trim()
);
const score = computed(() => {
  const n = Number(contactAttrs.value.tolzar_lead_score);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : null;
});
const hint = computed(() => (contactAttrs.value.tolzar_lead_hint || '').trim());

const chips = computed(() => (newUi ? checkChips(decision.value) : []));
const sources = computed(() => (newUi ? sourcesLine(decision.value) : ''));

const hasContent = computed(
  () => !!(suggestedReply.value || summary.value || score.value || intent.value)
);

// "Copied" feedback for the listen-only button; a failed copy says so instead of pretending.
const copyState = ref('');
let copyTimer = null;
const flash = state => {
  copyState.value = state;
  clearTimeout(copyTimer);
  copyTimer = setTimeout(() => {
    copyState.value = '';
  }, 1800);
};
onBeforeUnmount(() => clearTimeout(copyTimer));

const useReply = async () => {
  if (!suggestedReply.value) return;
  if (isListenOnly.value) {
    try {
      await copyTextToClipboard(suggestedReply.value);
      flash('copied');
    } catch (e) {
      flash('failed');
    }
    return;
  }
  emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, suggestedReply.value);
};

const buttonLabel = computed(() => {
  if (copyState.value === 'copied') return t('TOLZAR_INBOX.COPILOT.COPIED');
  return isListenOnly.value
    ? t('TOLZAR_INBOX.COPILOT.COPY_REPLY')
    : t('TOLZAR_INBOX.COPILOT.USE_REPLY');
});
const buttonHint = computed(() =>
  isListenOnly.value
    ? t('TOLZAR_INBOX.COPILOT.COPY_REPLY_HINT')
    : t('TOLZAR_INBOX.COPILOT.USE_REPLY_HINT')
);
</script>

<template>
  <div v-if="hasContent" class="tz-copilot">
    <div class="tz-c-head">
      <span class="tz-c-brand">
        <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <path d="M12 2l2.2 6.3L21 10l-6.8 1.7L12 18l-2.2-6.3L3 10l6.8-1.7z" />
        </svg>
        {{ t('TOLZAR_INBOX.COPILOT.TITLE', { product }) }}
      </span>
      <span v-if="intent" class="tz-c-chip">{{ intent }}</span>
      <span v-if="score" class="tz-c-chip tz-c-score">
        {{ t('TOLZAR_INBOX.COPILOT.SCORE', { score }) }}
      </span>
      <span
        v-if="confidence !== null"
        class="tz-c-conf"
        :aria-label="
          t('TOLZAR_INBOX.COPILOT.CONFIDENCE_ARIA', { pct: confidence })
        "
      >
        {{ t('TOLZAR_INBOX.COPILOT.CONFIDENCE') }}
        <span class="tz-c-bar" aria-hidden="true">
          <i :style="{ width: confidence + '%' }" />
        </span>
        {{ confidence }}%
      </span>
    </div>

    <p v-if="summary" class="tz-c-summary">{{ summary }}</p>

    <div v-if="suggestedReply" class="tz-c-reply">
      <div class="tz-c-lbl-row">
        <span class="tz-c-lbl">
          {{ t('TOLZAR_INBOX.COPILOT.SUGGESTED_REPLY') }}
        </span>
        <span
          class="tz-c-draft"
          :title="t('TOLZAR_INBOX.COPILOT.AI_DRAFT_HINT', { product })"
        >
          {{ t('TOLZAR_INBOX.COPILOT.AI_DRAFT') }}
        </span>
      </div>
      <div class="tz-c-text">{{ suggestedReply }}</div>
      <ul
        v-if="chips.length"
        class="tz-c-checks"
        :aria-label="t('TOLZAR_WHY.CHECKS')"
      >
        <li
          v-for="c in chips"
          :key="c.check"
          :class="c.passed ? 'tz-c-ok' : 'tz-c-bad'"
        >
          <span aria-hidden="true">{{ c.passed ? '✓' : '✗' }}</span>
          {{ t(`TOLZAR_WHY.CHECK.${c.check.toUpperCase()}`) }}
        </li>
      </ul>
      <p v-if="sources" class="tz-c-sources">
        {{ t('TOLZAR_SETTINGS_UI.PANE.SOURCES', { list: sources }) }}
      </p>
      <div class="tz-c-actions">
        <button
          type="button"
          class="tz-c-use"
          :class="{ 'tz-c-use-done': copyState === 'copied' }"
          :title="buttonHint"
          :aria-live="isListenOnly ? 'polite' : null"
          @click="useReply"
        >
          {{ buttonLabel }}
          <svg
            v-if="isListenOnly"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            aria-hidden="true"
          >
            <rect x="9" y="9" width="11" height="11" rx="2" />
            <path d="M5 15V5a1 1 0 0 1 1-1h10" />
          </svg>
          <svg
            v-else
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            aria-hidden="true"
          >
            <path d="M5 12h14M13 6l6 6-6 6" />
          </svg>
        </button>
        <span class="tz-c-hint">
          <template v-if="copyState === 'failed'">
            {{ t('TOLZAR_INBOX.COPILOT.COPY_FAILED') }}
          </template>
          <template v-else>{{ buttonHint }}</template>
        </span>
      </div>
    </div>

    <p v-if="hint" class="tz-c-why">{{ hint }}</p>
    <WhyPanel v-if="suggestedReply && chat?.id" :conversation-id="chat.id" />
  </div>
</template>

<style scoped>
.tz-copilot {
  position: relative;
  /* The card is a direct flex child of the .conversation-panel column (display:flex);
     without flex-shrink:0 flexbox crushes it to ~27px and overflow:hidden clips the body. */
  flex-shrink: 0;
  margin: 10px 16px 14px;
  border-radius: 15px;
  border: 1px solid rgb(var(--slate-5));
  background: linear-gradient(
      180deg,
      rgb(var(--blue-9) / 0.06),
      transparent 34%
    ),
    rgb(var(--surface-1));
  box-shadow: 0 10px 30px -24px rgb(0 0 0 / 0.5);
  padding: 13px 15px;
  overflow: hidden;
}
.tz-copilot::before {
  content: '';
  position: absolute;
  left: 0;
  right: 0;
  top: 0;
  height: 2px;
  background: linear-gradient(90deg, rgb(var(--blue-9)), transparent 68%);
  opacity: 0.75;
}
.tz-c-head {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 9px;
}
.tz-c-brand {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  font-weight: 800;
  letter-spacing: 0.2px;
  color: rgb(var(--blue-9));
}
.tz-c-brand svg {
  width: 15px;
  height: 15px;
}
.tz-c-chip {
  font-size: 10.5px;
  font-weight: 650;
  border-radius: 6px;
  padding: 2px 8px;
  color: rgb(var(--blue-9));
  background: rgb(var(--blue-9) / 0.1);
}
.tz-c-chip.tz-c-score {
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-3, 244 244 245));
}
.tz-c-conf {
  margin-inline-start: auto;
  display: inline-flex;
  align-items: center;
  gap: 7px;
  font-size: 11px;
  color: rgb(var(--slate-11));
}
.tz-c-bar {
  width: 48px;
  height: 5px;
  border-radius: 5px;
  background: rgb(var(--slate-5));
  overflow: hidden;
  display: inline-block;
}
.tz-c-bar i {
  display: block;
  height: 100%;
  background: rgb(var(--blue-9));
}
.tz-c-summary {
  font-size: 12.5px;
  color: rgb(var(--slate-11));
  line-height: 1.55;
  margin: 0 0 11px;
}
.tz-c-reply {
  border: 1px solid rgb(var(--slate-5));
  border-radius: 11px;
  background: rgb(var(--surface-2, 255 255 255));
  padding: 11px 13px;
}
.tz-c-lbl-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 7px;
}
.tz-c-lbl {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.6px;
  text-transform: uppercase;
  color: rgb(var(--slate-11));
}
.tz-c-draft {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.4px;
  text-transform: uppercase;
  border-radius: 5px;
  padding: 1px 6px;
  color: rgb(var(--amber-11, 166 108 11));
  background: rgb(var(--amber-9, 255 197 61) / 0.16);
}
.tz-c-text {
  font-size: 13px;
  color: rgb(var(--slate-12));
  line-height: 1.6;
  white-space: pre-wrap;
}
.tz-c-actions {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 10px;
  margin-top: 11px;
}
.tz-c-use {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  font-weight: 650;
  color: #fff;
  background: linear-gradient(
    180deg,
    rgb(var(--blue-9) / 0.9),
    rgb(var(--blue-9))
  );
  border: 0;
  border-radius: 8px;
  padding: 6px 13px;
  cursor: pointer;
}
.tz-c-use-done {
  background: rgb(var(--teal-9, 18 165 148));
}
.tz-c-use svg {
  width: 13px;
  height: 13px;
  stroke-width: 1.8;
}
.tz-c-hint {
  font-size: 11px;
  color: rgb(var(--slate-11));
  line-height: 1.4;
}
.tz-c-checks {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin: 8px 0 0;
  padding: 0;
  list-style: none;
}
.tz-c-checks li {
  padding: 1px 8px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 600;
}
.tz-c-ok {
  background: rgb(var(--teal-3));
  color: rgb(var(--teal-11));
}
.tz-c-bad {
  background: rgb(var(--ruby-3));
  color: rgb(var(--ruby-11));
}
.tz-c-sources {
  margin: 6px 0 0;
  font-size: 12px;
  color: rgb(var(--slate-11));
}
.tz-c-why {
  font-size: 11.5px;
  color: rgb(var(--slate-11));
  line-height: 1.55;
  border-inline-start: 2px solid rgb(var(--blue-9));
  padding-inline-start: 11px;
  margin: 11px 0 0;
  opacity: 0.95;
}
</style>
