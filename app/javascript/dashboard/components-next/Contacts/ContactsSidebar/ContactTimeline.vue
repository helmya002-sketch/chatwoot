<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { money } from 'dashboard/components-next/Tolzar/tolzarBookingResults';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';

// Contact → Timeline (Tolzar round 4, c99; Tolzar::ContactTimeline): conversations, issued documents, bookings and
// the win/loss reason in one list, newest first. Shown only while the workspace has inbox tools on.
const { t, locale } = useI18n();
const route = useRoute();
const events = ref(null);

async function load() {
  events.value = null;
  try {
    const { accountId, contactId } = route.params;
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId}/tolzar/contacts/${contactId}/timeline`
    );
    events.value = data.events || [];
  } catch {
    events.value = [];
  }
}

const when = at => {
  try {
    return new Intl.DateTimeFormat(locale.value, {
      dateStyle: 'medium',
      timeStyle: 'short',
    }).format(new Date(at));
  } catch {
    return at;
  }
};

const title = e => {
  if (e.kind === 'conversation')
    return t('CONTACTS_LAYOUT.SIDEBAR.TIMELINE.CONVERSATION', {
      id: e.id,
      inbox: e.inbox || '',
    });
  if (e.kind === 'document')
    return `${t(`TOLZAR_SETTINGS_UI.DOCS.T_${e.doc_type}`)} ${e.number || ''}`;
  if (e.kind === 'booking')
    return t('CONTACTS_LAYOUT.SIDEBAR.TIMELINE.BOOKING', {
      date: e.starts_on || '—',
    });
  return t(`CONTACTS_LAYOUT.SIDEBAR.TIMELINE.${e.outcome.toUpperCase()}`, {
    reason: t(`TOLZAR_CONTACTS.STAGES.REASON.${e.reason}`),
  });
};

const detail = e => {
  if (e.kind === 'document')
    return [
      t(`TOLZAR_SETTINGS_UI.DOCS.ST_${e.status}`),
      money(e.total_cents, e.currency, locale.value),
    ].join(' · ');
  if (e.kind === 'booking')
    return [
      t(`TOLZAR_SETTINGS_UI.BOOKINGS.ST_${e.status}`),
      money(e.total_cents, e.currency, locale.value),
    ].join(' · ');
  if (e.kind === 'conversation')
    return t(`CONTACTS_LAYOUT.SIDEBAR.TIMELINE.ST_${e.status}`);
  return '';
};

const link = e =>
  e.kind === 'conversation'
    ? frontendURL(
        conversationUrl({ accountId: route.params.accountId, id: e.id })
      )
    : null;

// Search within the contact (round 4, E5; Tolzar::ContactSearch): 2–100 characters, 300 ms debounce. While a query is
// active the hits replace the timeline.
const query = ref('');
const results = ref(null);
let searchTimer = null;
let searchSeq = 0;

const active = () => query.value.trim().length >= 2;

async function search() {
  searchSeq += 1;
  const seq = searchSeq;
  const q = query.value.trim();
  if (q.length < 2) {
    results.value = null;
    return;
  }
  try {
    const { accountId, contactId } = route.params;
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId}/tolzar/contacts/${contactId}/search`,
      { params: { q: q.slice(0, 100) } }
    );
    if (seq === searchSeq) results.value = data.results || [];
  } catch {
    if (seq === searchSeq) results.value = [];
  }
}

watch(query, () => {
  clearTimeout(searchTimer);
  results.value = null;
  searchTimer = setTimeout(search, 300);
});

const resultLink = r =>
  frontendURL(
    conversationUrl({ accountId: route.params.accountId, id: r.conversation_id })
  );

watch(() => route.params.contactId, load, { immediate: true });
watch(
  () => route.params.contactId,
  () => {
    query.value = '';
    results.value = null;
  }
);
</script>

<template>
  <div class="px-6 py-4">
    <input
      v-model="query"
      type="search"
      maxlength="100"
      :placeholder="t('CONTACTS_LAYOUT.SIDEBAR.TIMELINE.SEARCH_PLACEHOLDER')"
      :aria-label="t('CONTACTS_LAYOUT.SIDEBAR.TIMELINE.SEARCH_PLACEHOLDER')"
      class="w-full mb-4 text-sm"
    />
    <template v-if="active()">
      <p v-if="results === null" class="m-0 text-sm text-n-slate-11">
        {{ t('CONTACTS_LAYOUT.SIDEBAR.TIMELINE.SEARCH_LOADING') }}
      </p>
      <p v-else-if="!results.length" class="m-0 text-sm text-n-slate-11">
        {{ t('CONTACTS_LAYOUT.SIDEBAR.TIMELINE.SEARCH_EMPTY') }}
      </p>
      <ol v-else class="m-0 p-0 list-none flex flex-col gap-3">
        <li
          v-for="r in results"
          :key="r.message_id"
          class="ps-3 border-s-2 border-solid border-n-weak"
        >
          <p class="m-0 text-xs text-n-slate-10">{{ when(r.at) }}</p>
          <router-link
            :to="resultLink(r)"
            class="text-sm font-medium text-n-slate-12 hover:underline"
          >
            {{
              t('CONTACTS_LAYOUT.SIDEBAR.TIMELINE.SEARCH_IN', {
                id: r.conversation_id,
              })
            }}
          </router-link>
          <p class="m-0 text-xs text-n-slate-11 break-words">
            {{ r.snippet }}
          </p>
        </li>
      </ol>
    </template>
    <p v-else-if="events === null" class="m-0 text-sm text-n-slate-11">
      {{ t('CONTACTS_LAYOUT.SIDEBAR.TIMELINE.LOADING') }}
    </p>
    <p v-else-if="!events.length" class="m-0 text-sm text-n-slate-11">
      {{ t('CONTACTS_LAYOUT.SIDEBAR.TIMELINE.EMPTY') }}
    </p>
    <ol v-else class="m-0 p-0 list-none flex flex-col gap-3">
      <li
        v-for="e in events"
        :key="`${e.kind}-${e.id || e.at}`"
        class="ps-3 border-s-2 border-solid border-n-weak"
      >
        <p class="m-0 text-xs text-n-slate-10">{{ when(e.at) }}</p>
        <router-link
          v-if="link(e)"
          :to="link(e)"
          class="text-sm font-medium text-n-slate-12 hover:underline"
        >
          {{ title(e) }}
        </router-link>
        <p v-else class="m-0 text-sm font-medium text-n-slate-12">
          {{ title(e) }}
        </p>
        <p v-if="detail(e)" class="m-0 text-xs text-n-slate-11">
          {{ detail(e) }}
        </p>
      </li>
    </ol>
  </div>
</template>
