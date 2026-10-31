<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

// Settings → Integrations → Webhooks → edit (round 4, H2; Tolzar::WebhookDelivery): the webhook's last 50
// deliveries (time, event, result, duration). Administrators; hidden when the workspace has it off (404).
const props = defineProps({
  webhookId: { type: [Number, String], required: true },
});

const { t, locale } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const rows = ref(null);

async function load() {
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/webhooks/${props.webhookId}/deliveries`
    );
    rows.value = data.deliveries || [];
  } catch {
    rows.value = null;
  }
}

const when = at => new Date(at).toLocaleString(locale.value);
const result = row => {
  if (row.ok) return t('TOLZAR_SETTINGS_UI.WEBHOOK_LOG.OK');
  if (row.status)
    return t('TOLZAR_SETTINGS_UI.WEBHOOK_LOG.STATUS', { status: row.status });
  if (row.error === 'blocked_url')
    return t('TOLZAR_SETTINGS_UI.WEBHOOK_LOG.BLOCKED_URL');
  if (row.error === 'unreachable')
    return t('TOLZAR_SETTINGS_UI.WEBHOOK_LOG.UNREACHABLE');
  return t('TOLZAR_SETTINGS_UI.WEBHOOK_LOG.FAILED');
};

watch(() => props.webhookId, load, { immediate: true });
</script>

<template>
  <section v-if="rows" class="px-8 pb-6">
    <h3 class="m-0 text-sm font-semibold text-n-slate-12">
      {{ t('TOLZAR_SETTINGS_UI.WEBHOOK_LOG.TITLE') }}
    </h3>
    <p class="mt-1 mb-2 text-xs text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.WEBHOOK_LOG.HINT') }}
    </p>
    <p v-if="!rows.length" class="m-0 text-xs text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.WEBHOOK_LOG.EMPTY') }}
    </p>
    <ul v-else class="overflow-auto p-0 m-0 max-h-60 list-none">
      <li
        v-for="(row, i) in rows"
        :key="i"
        class="flex gap-3 py-1 text-xs border-b border-solid border-n-weak text-n-slate-12"
      >
        <span class="w-40 shrink-0 text-n-slate-11">{{ when(row.at) }}</span>
        <span class="flex-1 truncate">{{ row.event }}</span>
        <span :class="row.ok ? 'text-n-teal-11' : 'text-n-ruby-11'">
          {{ result(row) }}
        </span>
        <span
          v-if="row.duration_ms != null"
          class="w-16 text-end text-n-slate-11"
        >
          {{ t('TOLZAR_SETTINGS_UI.WEBHOOK_LOG.MS', { n: row.duration_ms }) }}
        </span>
      </li>
    </ul>
  </section>
</template>
