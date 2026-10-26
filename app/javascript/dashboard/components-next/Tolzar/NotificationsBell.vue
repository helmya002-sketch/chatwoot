<script setup>
/**
 * Tolzar #11: a notification bell at the bottom of the sidebar rail.
 * Click → a popover of recent notifications (mentions / assignments / etc.),
 * reusing Chatwoot's InboxCard + the notification store. Each row marks the
 * notification read and opens its conversation; "See all" opens the inbox view.
 */
import { ref, computed, onMounted } from 'vue';
import { onClickOutside } from '@vueuse/core';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRouter } from 'vue-router';
import InboxCard from 'dashboard/components-next/Inbox/InboxCard.vue';

defineProps({
  isCollapsed: { type: Boolean, default: false },
});

const store = useStore();
const router = useRouter();

const isOpen = ref(false);
const rootRef = ref(null);

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

const fetchNotifications = () => {
  store.dispatch('notifications/index', { page: 1, sortOrder: 'desc' });
  store.dispatch('notifications/unReadCount');
};

const toggle = () => {
  isOpen.value = !isOpen.value;
  if (isOpen.value) fetchNotifications();
};

onClickOutside(rootRef, () => {
  isOpen.value = false;
});

const openConversation = async notificationItem => {
  const {
    id,
    primaryActorId,
    primaryActorType,
    primaryActor: { inboxId, id: conversationId } = {},
  } = notificationItem;
  isOpen.value = false;
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
  isOpen.value = false;
  router.push({ name: 'inbox_view' });
};

onMounted(() => {
  store.dispatch('notifications/unReadCount');
});
</script>

<template>
  <div ref="rootRef" class="relative flex items-center">
    <button
      type="button"
      class="tz-bell relative flex items-center justify-center size-8 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 transition-colors"
      :class="{ 'bg-n-alpha-2 text-n-slate-12': isOpen }"
      title="Notifications"
      @click="toggle"
    >
      <span class="i-lucide-bell size-4" />
      <span
        v-if="hasUnread"
        class="absolute -top-0.5 ltr:-right-0.5 rtl:-left-0.5 min-w-[16px] h-4 px-1 flex items-center justify-center rounded-full bg-n-ruby-9 text-white text-[10px] font-semibold leading-none"
      >
        {{ badgeLabel }}
      </span>
    </button>

    <!-- Popover (flyout up-and-right from the rail bottom) -->
    <div
      v-if="isOpen"
      class="absolute bottom-0 ltr:left-full rtl:right-full ltr:ml-2 rtl:mr-2 z-[100] w-[320px] bg-n-alpha-3 backdrop-blur-[100px] outline outline-1 -outline-offset-1 outline-n-weak rounded-xl shadow-lg overflow-hidden"
    >
      <div
        class="flex items-center justify-between px-3 py-2 border-b border-n-weak"
      >
        <span
          class="text-xs font-medium text-n-slate-11 uppercase tracking-wider"
        >
          Notifications
        </span>
        <button
          type="button"
          class="text-xs font-medium text-n-brand hover:underline"
          @click="seeAll"
        >
          See all
        </button>
      </div>
      <div class="max-h-[400px] overflow-y-auto no-scrollbar px-1 py-1">
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
          You have no notifications
        </p>
      </div>
    </div>
  </div>
</template>
