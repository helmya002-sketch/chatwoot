<script setup>
import { computed, ref } from 'vue';
import { getInboxIconByType } from 'dashboard/helper/inbox';
import { useRouter, useRoute } from 'vue-router';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper.js';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import { useExactTimestamp } from 'shared/composables/useExactTimestamp';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import CardMessagePreview from './CardMessagePreview.vue';
import CardMessagePreviewWithMeta from './CardMessagePreviewWithMeta.vue';
import CardPriorityIcon from './CardPriorityIcon.vue';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
  contact: {
    type: Object,
    required: true,
  },
  stateInbox: {
    type: Object,
    required: true,
  },
  accountLabels: {
    type: Array,
    required: true,
  },
});

const exactTimestamp = useExactTimestamp();

const router = useRouter();
const route = useRoute();

const cardMessagePreviewWithMetaRef = ref(null);

const currentContact = computed(() => props.contact);

const currentContactName = computed(() => currentContact.value?.name);
const currentContactThumbnail = computed(() => currentContact.value?.thumbnail);
const currentContactStatus = computed(
  () => currentContact.value?.availabilityStatus
);

const inbox = computed(() => props.stateInbox);

const inboxName = computed(() => inbox.value?.name);

const inboxIcon = computed(() => {
  const { channelType, medium, voiceEnabled } = inbox.value;
  return getInboxIconByType(channelType, medium, 'fill', voiceEnabled);
});

const lastActivityAt = computed(() => {
  const timestamp = props.conversation?.timestamp;
  return timestamp ? shortTimestamp(dynamicTime(timestamp)) : '';
});

// Tolzar: lifecycle chip on the conversation card (respond.io-style sales funnel)
const LIFECYCLE_STYLES = {
  'New Lead': { background: '#e0edff', color: '#1d4ed8' },
  Active: { background: '#d8f5f0', color: '#0e8f84' },
  'Offer Sent Follow up': { background: '#fef3c7', color: '#b45309' },
  'Customer Won': { background: '#dcfce7', color: '#15803d' },
  'Customer Lost': { background: '#fee2e2', color: '#b91c1c' },
};
const LIFECYCLE_LABELS = { 'Offer Sent Follow up': 'Offer Sent' };
const lifecycleStage = computed(
  () => currentContact.value?.custom_attributes?.lifecycle_stage || ''
);
const lifecycleChipStyle = computed(() => {
  const c = LIFECYCLE_STYLES[lifecycleStage.value] || {
    background: '#eef2f7',
    color: '#64748b',
  };
  return {
    ...c,
    display: 'inline-flex',
    alignItems: 'center',
    borderRadius: '999px',
    padding: '1px 8px',
    fontSize: '11px',
    fontWeight: 700,
    lineHeight: '1.5',
  };
});
const lifecycleLabel = computed(
  () => LIFECYCLE_LABELS[lifecycleStage.value] || lifecycleStage.value
);

const hasVisibleLabels = computed(() => {
  const { labels = [] } = props.conversation;
  return props.accountLabels.some(({ title }) => labels.includes(title));
});

const showMessagePreviewWithoutMeta = computed(() => {
  return (
    !cardMessagePreviewWithMetaRef.value?.hasSlaThreshold &&
    !hasVisibleLabels.value
  );
});

const onCardClick = e => {
  const path = frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: props.conversation.id,
    })
  );

  if (e.metaKey || e.ctrlKey) {
    window.open(
      window.chatwootConfig.hostURL + path,
      '_blank',
      'noopener noreferrer nofollow'
    );
    return;
  }
  router.push({ path });
};
</script>

<template>
  <div
    role="button"
    class="flex w-full gap-3 px-3 py-4 transition-all duration-300 ease-in-out cursor-pointer"
    @click="onCardClick"
  >
    <Avatar
      :name="currentContactName"
      :src="currentContactThumbnail"
      :size="24"
      :status="currentContactStatus"
      rounded-full
    />
    <div class="flex flex-col w-full gap-1 min-w-0">
      <div class="flex items-center justify-between h-6 gap-2">
        <h4 class="text-base font-medium truncate text-n-slate-12">
          {{ currentContactName }}
        </h4>
        <div class="flex items-center gap-2">
          <CardPriorityIcon :priority="conversation.priority || null" />
          <div
            v-tooltip.left="inboxName"
            class="flex items-center justify-center flex-shrink-0 rounded-full bg-n-alpha-2 size-5"
          >
            <Icon
              :icon="inboxIcon"
              class="flex-shrink-0 text-n-slate-11 size-3"
            />
          </div>
          <span
            v-tooltip.top="{
              content: exactTimestamp(conversation?.timestamp),
              delay: { show: 500, hide: 0 },
            }"
            class="text-sm text-n-slate-10"
          >
            {{ lastActivityAt }}
          </span>
        </div>
      </div>
      <div v-if="lifecycleStage" class="flex" data-tz-lifecycle>
        <span :style="lifecycleChipStyle">{{ lifecycleLabel }}</span>
      </div>
      <CardMessagePreview
        v-show="showMessagePreviewWithoutMeta"
        :conversation="conversation"
      />
      <CardMessagePreviewWithMeta
        v-show="!showMessagePreviewWithoutMeta"
        ref="cardMessagePreviewWithMetaRef"
        :conversation="conversation"
        :contact="contact"
        :account-labels="accountLabels"
        :has-labels="hasVisibleLabels"
      />
    </div>
  </div>
</template>
