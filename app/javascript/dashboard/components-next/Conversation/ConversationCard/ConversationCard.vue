<script setup>
import { computed, ref } from 'vue';
import { getInboxIconByType } from 'dashboard/helper/inbox';
import { useRouter, useRoute } from 'vue-router';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper.js';
import {
  dynamicTime,
  shortTimestamp,
  messageStamp,
} from 'shared/helpers/timeHelper';
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
  const ts = props.conversation?.timestamp;
  if (!ts) return '';
  // Owner #14: the clock time of the last interaction for today's threads
  // ("time is important, like 3 am"); the short relative age for older ones.
  const d = new Date(ts * 1000);
  const n = new Date();
  const sameDay =
    d.getFullYear() === n.getFullYear() &&
    d.getMonth() === n.getMonth() &&
    d.getDate() === n.getDate();
  return sameDay ? messageStamp(ts, 'h:mm a') : shortTimestamp(dynamicTime(ts));
});

// Owner #14: "no reply till now" — how long the thread has been waiting for an
// agent reply (Chatwoot's waiting_since). Shown only while the thread is open.
const compactAgo = secs => {
  if (secs < 60) return `${Math.max(1, secs)}s`;
  const m = Math.floor(secs / 60);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h`;
  return `${Math.floor(h / 24)}d`;
};
const noReplyFor = computed(() => {
  const w = Number(props.conversation?.waitingSince);
  if (!Number.isFinite(w) || w <= 0) return '';
  if (props.conversation?.status !== 'open') return '';
  const secs = Math.floor(Date.now() / 1000) - w;
  return secs > 60 ? compactAgo(secs) : '';
});

// Tolzar: lifecycle chip on the conversation card (respond.io-style sales funnel)
// Tolzar: muted, eye-safe lifecycle pill colors (calmer for long shifts)
const LIFECYCLE_STYLES = {
  'New Lead': { background: '#e9eefb', color: '#3e63dd' },
  Active: { background: '#e6f2ef', color: '#4e9488' },
  'Offer Sent Follow up': { background: '#f6edd6', color: '#9a6b2f' },
  'Customer Won': { background: '#e7f1ea', color: '#4a8560' },
  'Customer Lost': { background: '#f6e7e6', color: '#b5564f' },
};
const LIFECYCLE_LABELS = { 'Offer Sent Follow up': 'Offer Sent' };
// Owner #9: every card shows a Stage so staff can plan at a glance; un-staged
// contacts default to the funnel entry "New Lead".
const lifecycleStage = computed(
  () => currentContact.value?.custom_attributes?.lifecycle_stage || 'New Lead'
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
    fontWeight: 600,
    lineHeight: '1.5',
  };
});
const lifecycleLabel = computed(
  () => LIFECYCLE_LABELS[lifecycleStage.value] || lifecycleStage.value
);

// Tolzar: a quiet "why" line on the card (the brain's lead hint).
const tolzarHint = computed(
  () => currentContact.value?.custom_attributes?.tolzar_lead_hint || ''
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
            v-if="noReplyFor"
            v-tooltip.top="'No reply yet'"
            class="inline-flex items-center gap-0.5 flex-shrink-0 rounded px-1.5 py-0.5 text-xs font-semibold"
            :style="{
              color: 'rgb(var(--amber-11, 166 108 11))',
              background: 'rgb(var(--amber-9, 255 197 61) / 0.16)',
            }"
          >
            <svg
              viewBox="0 0 24 24"
              class="size-3"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            >
              <circle cx="12" cy="12" r="9" />
              <path d="M12 7.5V12l3 2" />
            </svg>
            {{ noReplyFor }}
          </span>
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
      <div
        v-if="tolzarHint"
        class="text-xs truncate text-n-slate-11"
        data-tz-why
      >
        {{ tolzarHint }}
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
