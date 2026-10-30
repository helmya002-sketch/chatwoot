<script setup>
/**
 * Tolzar #11: a notification bell at the bottom of the sidebar rail.
 * Click → a popover of recent notifications (mentions / assignments / etc.),
 * reusing Chatwoot's InboxCard + the notification store. Each row marks the
 * notification read and opens its conversation; "See all" opens the inbox view.
 * Opening refetches at most once per 30 s, unless the unread badge changed meanwhile.
 */
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { onClickOutside } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRouter } from 'vue-router';
import InboxCard from 'dashboard/components-next/Inbox/InboxCard.vue';

defineProps({
  isCollapsed: { type: Boolean, default: false },
});

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const isOpen = ref(false);
const rootRef = ref(null);
const buttonRef = ref(null);

const unreadCount = useMapGetter('notifications/getUnreadCount');
const uiFlags = useMapGetter('notifications/getUIFlags');
const records = useMapGetter('notifications/getFilteredNotificationsV4');
const meta = useMapGetter('notifications/getMeta');
const inboxById = useMapGetter('inboxes/getInboxById');

const notifications = computed(() =>
  records
    .value({ page: 1, status: '', type: '', sortOrder: 'desc' })
    .slice(0, 12)
);

const hasUnread = computed(() => (unreadCount.value || 0) > 0);
const badgeLabel = computed(() => {
  const c = unreadCount.value || 0;
  return c > 99 ? '99+' : String(c);
});

const stateInbox = inboxId => inboxById.value(inboxId);

// No refetch storm: the list is fetched when the popover opens, then not again within
// 30 s unless the badge count moved (a new notification arrived or one was read elsewhere).
const REFETCH_MS = 30 * 1000;
let lastFetchAt = 0;
let lastFetchCount = null;
const fetchNotifications = () => {
  const count = unreadCount.value || 0;
  const fresh = Date.now() - lastFetchAt < REFETCH_MS;
  if (fresh && count === lastFetchCount) return;
  lastFetchAt = Date.now();
  lastFetchCount = count;
  store.dispatch('notifications/index', { page: 1, sortOrder: 'desc' });
  store.dispatch('notifications/unReadCount');
};

const close = ({ focus = false } = {}) => {
  if (!isOpen.value) return;
  isOpen.value = false;
  if (focus) buttonRef.value?.focus();
};
const toggle = () => {
  if (isOpen.value) {
    close();
    return;
  }
  isOpen.value = true;
  fetchNotifications();
};
const onKey = e => {
  if (e.key === 'Escape' && isOpen.value) close({ focus: true });
};

onClickOutside(rootRef, () => close());

const openConversation = async notificationItem => {
  const {
    id,
    primaryActorId,
    primaryActorType,
    primaryActor: { inboxId, id: conversationId } = {},
  } = notificationItem;
  close();
  try {
    await store.dispatch('notifications/read', {
      id,
      primaryActorId,
      primaryActorType,
      unreadCount: meta.value.unreadCount,
    });
    store.dispatch('notifications/unReadCount');
  } catch (e) {
    // non-fatal
  }
  if (inboxId && conversationId) {
    router.push({
      name: 'inbox_view_conversation',
      params: { inboxId, type: 'conversation', id: conversationId },
    });
  } else {
    router.push({ name: 'inbox_view' });
  }
};

const seeAll = () => {
  close();
  router.push({ name: 'inbox_view' });
};

onMounted(() => {
  store.dispatch('notifications/unReadCount');
  window.addEventListener('keydown', onKey);
});
onBeforeUnmount(() => window.removeEventListener('keydown', onKey));
</script>

<template>
  <div ref="rootRef" class="relative flex items-center">
    <button
      ref="buttonRef"
      type="button"
      class="tz-bell relative flex items-center justify-center size-8 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 transition-colors"
      :class="{ 'bg-n-alpha-2 text-n-slate-12': isOpen }"
      :title="t('TOLZAR_INBOX.BELL.TITLE')"
      :aria-label="
        hasUnread
          ? `${t('TOLZAR_INBOX.BELL.TITLE')} (${badgeLabel})`
          : t('TOLZAR_INBOX.BELL.TITLE')
      "
      aria-haspopup="dialog"
      :aria-expanded="isOpen ? 'true' : 'false'"
      aria-controls="tz-bell-pop"
      @click="toggle"
    >
      <span class="i-lucide-bell size-4" aria-hidden="true" />
      <span v-if="!isCollapsed" class="ms-2 text-sm">
        {{ t('TOLZAR_INBOX.BELL.TITLE') }}
      </span>
      <span
        v-if="hasUnread"
        class="absolute -top-0.5 ltr:-right-0.5 rtl:-left-0.5 min-w-[16px] h-4 px-1 flex items-center justify-center rounded-full bg-n-ruby-9 text-white text-[10px] font-semibold leading-none"
        aria-hidden="true"
      >
        {{ badgeLabel }}
      </span>
    </button>

    <!-- Popover (flyout up-and-right from the rail bottom) -->
    <div
      v-if="isOpen"
      id="tz-bell-pop"
      role="dialog"
      :aria-label="t('TOLZAR_INBOX.BELL.TITLE')"
      class="absolute bottom-0 ltr:left-full rtl:right-full ltr:ml-2 rtl:mr-2 z-[100] w-[320px] bg-n-alpha-3 backdrop-blur-[100px] outline outline-1 -outline-offset-1 outline-n-weak rounded-xl shadow-lg overflow-hidden"
    >
      <div
        class="flex items-center justify-between px-3 py-2 border-b border-n-weak"
      >
        <span
          class="text-xs font-medium text-n-slate-11 uppercase tracking-wider"
        >
          {{ t('TOLZAR_INBOX.BELL.TITLE') }}
        </span>
        <button
          type="button"
          class="text-xs font-medium text-n-brand hover:underline"
          @click="seeAll"
        >
          {{ t('TOLZAR_INBOX.BELL.SEE_ALL') }}
        </button>
      </div>
      <div
        class="max-h-[min(400px,70vh)] overflow-y-auto no-scrollbar px-1 py-1"
      >
        <InboxCard
          v-for="item in notifications"
          :key="item.id"
          :inbox-item="item"
          :state-inbox="stateInbox(item.primaryActor?.inboxId)"
          class="rounded-lg hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3 cursor-pointer"
          @click="openConversation(item)"
        />
        <p
          v-if="!uiFlags.isFetching && notifications.length === 0"
          class="p-4 text-sm font-medium text-center text-n-slate-10"
        >
          {{ t('TOLZAR_INBOX.BELL.EMPTY') }}
        </p>
      </div>
    </div>
  </div>
</template>
