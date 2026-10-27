<script setup>
import { computed, ref, watch } from 'vue';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import {
  messageStamp,
  shortTimestamp,
  dynamicTime,
} from 'shared/helpers/timeHelper';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import { channelFromSource } from 'dashboard/components-next/Tolzar/tolzarChannel';
import MessagePreview from './MessagePreview.vue';
import InboxName from '../InboxName.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import CardLabels from './conversationCardComponents/CardLabels.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import UnreadBadge from 'dashboard/components-next/Conversation/ConversationCard/UnreadBadge.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import VoiceCallStatus from './VoiceCallStatus.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

const props = defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, required: true },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  hideThumbnail: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});

const emit = defineEmits([
  'click',
  'contextmenu',
  'selectConversation',
  'deSelectConversation',
]);

const hovered = ref(false);

const unreadCount = computed(() => props.chat.unread_count);
// Tolzar: mirror conversations all sit in one API inbox; show the guest's real channel
// (WhatsApp / Instagram / email ...) from the mirror's rio_channel_source.
const badgeInbox = computed(() => {
  const real = channelFromSource(
    props.chat?.additional_attributes?.rio_channel_source
  );
  if (!real) return props.inbox;
  return {
    ...real,
    name: [real.name, props.inbox?.name].filter(Boolean).join(' · '),
  };
});
const hasUnread = computed(() => unreadCount.value > 0);
const lastMessageInChat = computed(() => getLastMessage(props.chat));

// Tolzar #14: clock time of the last interaction for today ("time is important,
// like 3 am"); short relative age for older threads.
const lastTimeDisplay = computed(() => {
  const ts = props.chat?.timestamp;
  if (!ts) return '';
  const d = new Date(ts * 1000);
  const n = new Date();
  const sameDay =
    d.getFullYear() === n.getFullYear() &&
    d.getMonth() === n.getMonth() &&
    d.getDate() === n.getDate();
  return sameDay ? messageStamp(ts, 'h:mm a') : shortTimestamp(dynamicTime(ts));
});
// Tolzar #14: "no reply till now" — how long the thread has waited for an agent
// reply (Chatwoot's waiting_since). Only while the thread is open.
const compactAgo = secs => {
  if (secs < 60) return `${Math.max(1, secs)}s`;
  const m = Math.floor(secs / 60);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h`;
  return `${Math.floor(h / 24)}d`;
};
const noReplyFor = computed(() => {
  const w = Number(props.chat?.waiting_since ?? props.chat?.waitingSince);
  if (!Number.isFinite(w) || w <= 0) return '';
  if (props.chat?.status !== 'open') return '';
  const secs = Math.floor(Date.now() / 1000) - w;
  return secs > 60 ? compactAgo(secs) : '';
});

// Tolzar #9: every card shows a Stage so staff can plan at a glance; un-staged
// contacts default to the funnel entry "New Lead".
const lifecycleStage = computed(
  () => props.currentContact?.custom_attributes?.lifecycle_stage || 'New Lead'
);
const lifecycleChipStyle = computed(() => {
  const s = String(lifecycleStage.value).toLowerCase();
  let bg = '#CCFBF1';
  let fg = '#0F766E'; // teal (brand) fallback / "new lead"
  if (/lost/.test(s)) {
    bg = '#FEE2E2';
    fg = '#B91C1C';
  } else if (/won|customer/.test(s)) {
    bg = '#DCFCE7';
    fg = '#15803D';
  } else if (/qualif|lead/.test(s)) {
    bg = '#DBEAFE';
    fg = '#1D4ED8';
  } else if (/open|progress|active|engag|contact|negoti/.test(s)) {
    bg = '#FEF3C7';
    fg = '#B45309';
  } else if (/new/.test(s)) {
    bg = '#E2E8F0';
    fg = '#475569';
  }
  return { backgroundColor: bg, color: fg };
});
const lifecycleLabel = computed(() => lifecycleStage.value);

const voiceCallData = computed(() => {
  const last = lastMessageInChat.value;
  if (last?.content_type !== 'voice_call' || !last.call) {
    return { status: null, direction: null };
  }
  return {
    status: last.call.status,
    direction: last.call.direction === 'outgoing' ? 'outbound' : 'inbound',
  };
});

const showMetaSection = computed(() => {
  return (
    props.showInboxName ||
    (props.showAssignee && props.assignee.name) ||
    props.chat.priority
  );
});

const isAIAssignee = computed(() =>
  ['AgentBot', 'Captain::Assistant'].includes(props.chat?.meta?.assignee_type)
);

const hasSlaPolicyId = computed(
  () => props.chat?.applied_sla?.id && !props.currentContact?.blocked
);

const showLabelsSection = computed(() => {
  return props.chat.labels?.length > 0 || hasSlaPolicyId.value;
});

const messagePreviewClass = computed(() => {
  return [
    hasUnread.value ? 'font-medium text-n-slate-12' : 'text-n-slate-11',
    !props.compact && hasUnread.value ? 'ltr:pr-4 rtl:pl-4' : '',
    props.compact && hasUnread.value ? 'ltr:pr-6 rtl:pl-6' : '',
  ];
});

const onThumbnailHover = () => {
  hovered.value = !props.hideThumbnail;
};

const onThumbnailLeave = () => {
  hovered.value = false;
};

const onSelectConversation = checked => {
  if (checked) {
    emit('selectConversation', props.chat.id, props.inbox.id);
  } else {
    emit('deSelectConversation', props.chat.id, props.inbox.id);
  }
};

const selectedModel = computed({
  get: () => props.selected,
  set: value => onSelectConversation(value),
});

watch(
  () => props.chat.id,
  () => {
    hovered.value = false;
  }
);
</script>

<template>
  <div
    class="relative flex items-start flex-grow-0 flex-shrink-0 w-auto max-w-full py-0 cursor-pointer conversation border-b border-n-slate-3 hover:border-n-surface-1 hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3 group hover:z-[1] before:content-[none] before:absolute before:-top-px before:inset-x-0 before:h-px before:bg-n-surface-1 before:pointer-events-none hover:before:content-['']"
    :class="{
      'active animate-card-select bg-n-background !border-n-surface-1':
        isActiveChat,
      'selected bg-n-slate-2 !border-n-surface-1': selected,
      'px-0': compact,
      'px-3': !compact,
    }"
    @click="$emit('click', $event)"
    @contextmenu="$emit('contextmenu', $event)"
  >
    <div
      v-if="!hideThumbnail"
      class="relative flex-shrink-0"
      :class="!showInboxName ? 'mt-4' : 'mt-8'"
      @mouseenter="onThumbnailHover"
      @mouseleave="onThumbnailLeave"
    >
      <Avatar
        :name="currentContact.name"
        :src="currentContact.thumbnail"
        :size="32"
        :status="currentContact.availability_status"
        hide-offline-status
      >
        <template #overlay="{ size }">
          <label
            v-if="hovered || selected"
            class="flex items-center justify-center rounded-full cursor-pointer absolute inset-0 z-10 backdrop-blur-[2px]"
            :style="{ width: `${size}px`, height: `${size}px` }"
            @click.stop
          >
            <Checkbox v-model="selectedModel" />
          </label>
        </template>
      </Avatar>
      <!-- Tolzar #12: channel badge on the avatar (WhatsApp / email / Messenger / etc.) -->
      <span
        v-if="badgeInbox && badgeInbox.channel_type"
        v-tooltip.top="badgeInbox.name"
        class="tz-channel-badge absolute -bottom-1 ltr:-right-1 rtl:-left-1 z-[11] flex items-center justify-center size-[15px] rounded-full bg-n-background ring-2 ring-n-background"
      >
        <ChannelIcon :inbox="badgeInbox" class="size-[13px]" />
      </span>
    </div>
    <div class="px-0 py-3 flex-1 min-w-0 border-line">
      <div
        v-if="showMetaSection"
        class="flex items-center min-w-0 gap-1"
        :class="{
          'ltr:ml-2 rtl:mr-2': !compact,
          'mx-2': compact,
        }"
      >
        <InboxName
          v-if="showInboxName"
          :inbox="badgeInbox"
          class="flex-1 min-w-0"
        />
        <div
          class="flex items-baseline gap-2 flex-shrink-0"
          :class="{
            'flex-1 justify-between': !showInboxName,
          }"
        >
          <!-- Tolzar #6a: assignee as a circle avatar (name on hover), not text. -->
          <Avatar
            v-if="showAssignee && assignee.name && !isAIAssignee"
            v-tooltip.top="assignee.name"
            :name="assignee.name"
            :src="assignee.thumbnail"
            :size="18"
            rounded-full
            class="flex-shrink-0"
          />
          <span
            v-else-if="showAssignee && assignee.name"
            v-tooltip.top="assignee.name"
            class="inline-flex items-center flex-shrink-0 text-n-slate-11"
          >
            <Icon icon="i-lucide-bot" class="size-3.5 text-n-slate-11" />
          </span>
          <CardPriorityIcon
            :priority="chat.priority"
            class="flex-shrink-0 !size-3.5"
          />
        </div>
      </div>
      <h4
        class="conversation--user text-sm my-0 mx-2 capitalize pt-0.5 text-ellipsis overflow-hidden whitespace-nowrap flex-1 min-w-0 ltr:pr-16 rtl:pl-16 text-n-slate-12"
        :class="hasUnread ? 'font-semibold' : 'font-medium'"
      >
        {{ currentContact.name }}
      </h4>
      <div v-if="lifecycleLabel" class="flex mx-2 mt-1" data-tz-lifecycle>
        <span
          class="inline-flex items-center text-xxs font-semibold leading-none rounded-full px-1.5 py-1 whitespace-nowrap"
          :style="lifecycleChipStyle"
        >
          {{ lifecycleLabel }}
        </span>
      </div>
      <VoiceCallStatus
        v-if="voiceCallData.status"
        key="voice-status-row"
        :status="voiceCallData.status"
        :direction="voiceCallData.direction"
        :message-preview-class="messagePreviewClass"
      />
      <MessagePreview
        v-else-if="lastMessageInChat"
        key="message-preview"
        :message="lastMessageInChat"
        class="my-0 mx-2 leading-6 h-6 flex-1 min-w-0 text-sm"
        :class="messagePreviewClass"
      />
      <p
        v-else
        key="no-messages"
        class="text-n-slate-11 text-sm my-0 mx-2 leading-6 h-6 flex-1 min-w-0 overflow-hidden text-ellipsis whitespace-nowrap"
        :class="messagePreviewClass"
      >
        <fluent-icon
          size="16"
          class="-mt-0.5 align-middle inline-block text-n-slate-10"
          icon="info"
        />
        <span class="mx-0.5">
          {{ $t(`CHAT_LIST.NO_MESSAGES`) }}
        </span>
      </p>
      <div
        class="absolute flex flex-col items-end ltr:right-3 rtl:left-3"
        :class="showMetaSection ? 'top-8' : 'top-4'"
      >
        <!-- Tolzar #14: clock time of the last interaction, + "no reply for X". -->
        <span
          v-tooltip.left="
            chat.timestamp ? messageStamp(chat.timestamp, 'MMM d, h:mm a') : ''
          "
          class="ml-auto font-normal leading-4 text-xxs text-n-slate-11"
        >
          {{ lastTimeDisplay }}
        </span>
        <span
          v-if="noReplyFor"
          v-tooltip.left="'No reply yet'"
          class="inline-flex items-center gap-0.5 mt-1 rounded px-1 py-px text-xxs font-semibold leading-none"
          :style="{
            color: 'rgb(var(--amber-11, 166 108 11))',
            background: 'rgb(var(--amber-9, 255 197 61) / 0.16)',
          }"
        >
          <svg
            viewBox="0 0 24 24"
            class="size-2.5"
            fill="none"
            stroke="currentColor"
            stroke-width="2.2"
          >
            <circle cx="12" cy="12" r="9" />
            <path d="M12 7.5V12l3 2" />
          </svg>
          {{ noReplyFor }}
        </span>
        <UnreadBadge
          v-if="hasUnread"
          :count="unreadCount"
          class="ltr:ml-auto rtl:mr-auto mt-1"
        />
      </div>
      <CardLabels
        v-if="showLabelsSection"
        :conversation-labels="chat.labels"
        class="mt-0.5 mx-2 mb-0"
      >
        <template v-if="hasSlaPolicyId" #before>
          <SLACardLabel :chat="chat" class="ltr:mr-1 rtl:ml-1" />
        </template>
      </CardLabels>
    </div>
  </div>
</template>
