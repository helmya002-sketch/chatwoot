<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { fmtAt } from '../tolzarTime';

// Settings → Channels → Human-agent replies (round 4, c77): every Messenger / Instagram reply sent with Meta's
// Human Agent tag, newest first, with the person who sent it. Read-only; administrators.
const { t, locale } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const rows = ref(null);
const failed = ref(false);
const url = computed(
  () => `/api/v1/accounts/${accountId.value}/tolzar/human_agent_replies`
);

onMounted(async () => {
  try {
    const { data } = await window.axios.get(url.value);
    rows.value = data.replies || [];
  } catch {
    failed.value = true;
  }
});
</script>

<template>
  <div class="max-w-[820px]">
    <p class="mt-0 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_INBOX.REPLY_WINDOW.AUDIT_HINT') }}
    </p>
    <p v-if="failed" class="text-[13px] text-n-ruby-11" role="alert">
      {{ t('TOLZAR_SETTINGS_UI.DOCS.FAILED') }}
    </p>
    <p v-else-if="rows && !rows.length" class="text-[13px] text-n-slate-11">
      {{ t('TOLZAR_INBOX.REPLY_WINDOW.AUDIT_EMPTY') }}
    </p>
    <table v-else-if="rows" class="w-full text-[13px]">
      <thead class="text-xs text-n-slate-11">
        <tr class="border-b border-n-weak">
          <th class="py-2 pe-3 text-start font-medium">
            {{ t('TOLZAR_INBOX.REPLY_WINDOW.AUDIT_WHEN') }}
          </th>
          <th class="py-2 pe-3 text-start font-medium">
            {{ t('TOLZAR_INBOX.REPLY_WINDOW.AUDIT_WHO') }}
          </th>
          <th class="py-2 pe-3 text-start font-medium">
            {{ t('TOLZAR_INBOX.REPLY_WINDOW.AUDIT_CONVERSATION') }}
          </th>
          <th class="py-2 text-start font-medium">
            {{ t('TOLZAR_INBOX.REPLY_WINDOW.AUDIT_TAG') }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="r in rows" :key="r.id" class="border-b border-n-weak">
          <td class="py-2 pe-3 whitespace-nowrap">{{ fmtAt(r.at, locale) }}</td>
          <td class="py-2 pe-3">{{ r.sender }}</td>
          <td class="py-2 pe-3">
            <router-link
              :to="`/app/accounts/${accountId}/conversations/${r.conversation_id}`"
              class="text-n-blue-11 underline"
            >
              #{{ r.conversation_id }}
            </router-link>
            <span class="ms-1 text-n-slate-10">{{ r.inbox }}</span>
          </td>
          <td class="py-2 font-mono text-xs">{{ r.tag }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
