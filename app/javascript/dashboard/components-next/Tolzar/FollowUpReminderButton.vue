<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';

// Conversation header → Remind me (Tolzar round 4, E4; Tolzar::FollowUpReminder): "remind me in 1 / 2 / 3 days if
// the customer doesn't answer", for the signed-in person only. A customer message cancels it by itself; when it is
// due, an in-app notification arrives. Shown only while the workspace has inbox tools on.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const { t, locale } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const open = ref(false);
const busy = ref(false);
const reminder = ref(null);
const DAYS = [1, 2, 3];

const url = () =>
  `/api/v1/accounts/${accountId.value}/tolzar/conversations/${props.conversationId}/follow_up`;

async function load() {
  reminder.value = null;
  try {
    const { data } = await window.axios.get(url());
    reminder.value = data.reminder || null;
  } catch {
    reminder.value = null;
  }
}

async function change(request) {
  if (busy.value) return;
  busy.value = true;
  open.value = false;
  try {
    const { data } = await request();
    reminder.value = data.reminder || null;
    useAlert(
      reminder.value
        ? t('TOLZAR_INBOX.FOLLOW_UP.SET')
        : t('TOLZAR_INBOX.FOLLOW_UP.CANCELLED')
    );
  } catch {
    useAlert(t('TOLZAR_INBOX.FOLLOW_UP.FAILED'));
  } finally {
    busy.value = false;
  }
}

const remind = days => change(() => window.axios.post(url(), { days }));
const cancel = () => change(() => window.axios.delete(url()));

const dueLabel = computed(() => {
  if (!reminder.value) return '';
  try {
    const when = new Intl.DateTimeFormat(locale.value, {
      weekday: 'short',
      hour: 'numeric',
      minute: '2-digit',
    }).format(new Date(reminder.value.due_at));
    return t('TOLZAR_INBOX.FOLLOW_UP.DUE', { when });
  } catch {
    return t('TOLZAR_INBOX.FOLLOW_UP.DUE', { when: reminder.value.due_at });
  }
});

watch(() => props.conversationId, load, { immediate: true });
</script>

<template>
  <div class="relative" @keydown.esc="open = false">
    <Button
      v-tooltip="reminder ? dueLabel : t('TOLZAR_INBOX.FOLLOW_UP.TOOLTIP')"
      :label="reminder ? dueLabel : t('TOLZAR_INBOX.FOLLOW_UP.BUTTON')"
      icon="i-lucide-alarm-clock"
      :variant="reminder ? 'solid' : 'faded'"
      :color="reminder ? 'amber' : 'slate'"
      size="sm"
      :is-loading="busy"
      aria-haspopup="menu"
      :aria-expanded="open ? 'true' : 'false'"
      @click="open = !open"
    />
    <div
      v-if="open"
      class="absolute end-0 top-full z-50 mt-2 w-64 p-1 rounded-xl border border-solid border-n-weak bg-n-solid-1 shadow-lg"
      role="menu"
    >
      <p class="m-0 px-2 py-1.5 text-xs text-n-slate-11">
        {{ t('TOLZAR_INBOX.FOLLOW_UP.HINT') }}
      </p>
      <button
        v-for="d in DAYS"
        :key="d"
        type="button"
        role="menuitem"
        class="w-full px-2 py-1.5 text-sm text-start rounded-lg text-n-slate-12 hover:bg-n-alpha-2"
        @click="remind(d)"
      >
        {{ t('TOLZAR_INBOX.FOLLOW_UP.IN_DAYS', { n: d }, d) }}
      </button>
      <button
        v-if="reminder"
        type="button"
        role="menuitem"
        class="w-full px-2 py-1.5 text-sm text-start rounded-lg text-n-ruby-11 hover:bg-n-alpha-2"
        @click="cancel"
      >
        {{ t('TOLZAR_INBOX.FOLLOW_UP.CANCEL') }}
      </button>
    </div>
  </div>
</template>
