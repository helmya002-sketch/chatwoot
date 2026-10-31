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

watch(() => route.params.contactId, load, { immediate: true });
</script>

<template>
  <div class="px-6 py-4">
    <p v-if="events === null" class="m-0 text-sm text-n-slate-11">
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
