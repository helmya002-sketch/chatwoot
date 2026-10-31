<script setup>
import {
  computed,
  useTemplateRef,
  ref,
  onMounted,
  onBeforeUnmount,
  watch,
  nextTick,
} from 'vue';
import { Letter } from 'vue-letter';
import { sanitizeTextForRender } from '@chatwoot/utils';
import { allowedCssProperties } from 'lettersanitizer';

import Icon from 'next/icon/Icon.vue';
import { EmailQuoteExtractor } from 'dashboard/helper/emailQuoteExtractor.js';
import FormattedContent from 'next/message/bubbles/Text/FormattedContent.vue';
import BaseBubble from 'next/message/bubbles/Base.vue';
import AttachmentChips from 'next/message/chips/AttachmentChips.vue';
import EmailMeta from './EmailMeta.vue';
import TranslationToggle from 'dashboard/components-next/message/TranslationToggle.vue';
import EmailFullView from './EmailFullView.vue';
import { applyFit } from './emailFit';

import { useMessageContext } from '../../provider.js';
import { MESSAGE_TYPES } from 'next/message/constants.js';
import { useTranslations } from 'dashboard/composables/useTranslations';

const {
  content,
  contentAttributes,
  attachments,
  messageType,
  contactSide,
  showingOriginal,
  isCaptainMessage,
} = useMessageContext();

const isExpandable = ref(false);
const isExpanded = ref(false);
const showQuotedMessage = ref(false);
const contentContainer = useTemplateRef('contentContainer');

// Tolzar: wide e-mails fit the pane (emailFit.js); "Expand email" opens the full view (EmailFullView.vue).
const fitOuter = useTemplateRef('fitOuter');
const fitInner = useTemplateRef('fitInner');
const fitScaleApplied = ref(1);
const showFullView = ref(false);
let resizeObserver = null;

const refit = () =>
  nextTick(() => {
    fitScaleApplied.value = applyFit(fitOuter.value, fitInner.value);
  });

onMounted(() => {
  isExpandable.value = contentContainer.value?.scrollHeight > 400;
  refit();
  if (typeof ResizeObserver !== 'undefined' && fitOuter.value) {
    resizeObserver = new ResizeObserver(refit);
    resizeObserver.observe(fitOuter.value);
  }
});
onBeforeUnmount(() => resizeObserver?.disconnect());

const isOutgoing = computed(() => messageType.value === MESSAGE_TYPES.OUTGOING);
const isIncoming = computed(() => !isOutgoing.value);

const { hasTranslations, translationContent } = useTranslations(
  contentAttributes,
  contactSide
);
const showsTranslation = computed(
  () => hasTranslations.value && !showingOriginal.value
);

const originalEmailText = computed(() => {
  const text =
    contentAttributes?.value?.email?.textContent?.full ?? content.value;
  return sanitizeTextForRender(text);
});

const originalEmailHtml = computed(
  () =>
    contentAttributes?.value?.email?.htmlContent?.full ||
    originalEmailText.value
);

const hasEmailContent = computed(() => {
  return (
    contentAttributes?.value?.email?.textContent?.full ||
    contentAttributes?.value?.email?.htmlContent?.full
  );
});

const messageContent = computed(() =>
  showsTranslation.value ? translationContent.value : content.value
);

const textToShow = computed(() =>
  showsTranslation.value ? translationContent.value : originalEmailText.value
);

const fullHTML = computed(() =>
  showsTranslation.value ? translationContent.value : originalEmailHtml.value
);

const isForwarded = computed(
  () => !!contentAttributes.value?.forwardedMessageId
);

const unquotedHTML = computed(() =>
  isForwarded.value
    ? fullHTML.value
    : EmailQuoteExtractor.extractQuotes(fullHTML.value)
);

const hasQuotedMessage = computed(
  () => !isForwarded.value && EmailQuoteExtractor.hasQuotes(fullHTML.value)
);

// Ensure unique keys for <Letter> when toggling between original and translated views.
// This forces Vue to re-render the component and update content correctly.
const translationKeySuffix = computed(() => {
  if (showingOriginal.value) return 'original';
  if (hasTranslations.value) return 'translated';
  return 'original';
});

const handleSeeOriginal = () => {
  showingOriginal.value = !showingOriginal.value;
};

watch([showQuotedMessage, translationKeySuffix], refit);

const emailSubject = computed(
  () => contentAttributes?.value?.email?.subject || ''
);
const canOpenFull = computed(
  () => isExpandable.value || fitScaleApplied.value < 1
);
</script>

<template>
  <BaseBubble
    class="w-full"
    :class="{
      'bg-n-slate-4': isIncoming,
      'bg-n-solid-blue': isOutgoing,
    }"
    data-bubble-name="email"
  >
    <EmailMeta
      class="p-3"
      :class="{
        'border-b border-n-strong': isIncoming,
        'border-b border-n-slate-8/20': isOutgoing,
      }"
    />
    <section ref="contentContainer" class="p-3">
      <div
        :class="{
          'max-h-[400px] overflow-hidden relative': !isExpanded && isExpandable,
          'overflow-y-scroll relative': isExpanded,
        }"
      >
        <div
          v-if="isExpandable && !isExpanded"
          class="absolute left-0 right-0 bottom-0 h-40 px-8 flex items-end"
          :class="{
            'bg-gradient-to-t from-n-slate-4 via-n-slate-4 via-20% to-transparent':
              isIncoming,
            'bg-gradient-to-t from-n-solid-blue via-n-solid-blue via-20% to-transparent':
              isOutgoing,
          }"
        >
          <button
            class="text-n-slate-12 py-2 px-8 mx-auto text-center flex items-center gap-2"
            @click="showFullView = true"
          >
            <Icon icon="i-lucide-maximize-2" />
            {{ $t('EMAIL_HEADER.EXPAND') }}
          </button>
        </div>
        <FormattedContent
          v-if="isOutgoing && content && !hasEmailContent"
          class="text-n-slate-12"
          :content="messageContent"
        />
        <div v-else ref="fitOuter" class="w-full overflow-hidden">
          <div ref="fitInner">
          <Letter
            v-if="showQuotedMessage"
            :key="`letter-quoted-${translationKeySuffix}`"
            class-name="prose prose-bubble !max-w-none letter-render"
            :allowed-css-properties="[
              ...allowedCssProperties,
              'transform',
              'transform-origin',
            ]"
            :html="fullHTML"
            :text="textToShow"
          />
          <Letter
            v-else
            :key="`letter-unquoted-${translationKeySuffix}`"
            class-name="prose prose-bubble !max-w-none letter-render"
            :html="unquotedHTML"
            :allowed-css-properties="[
              ...allowedCssProperties,
              'transform',
              'transform-origin',
            ]"
            :text="textToShow"
          />
          </div>
        </div>
        <button
          v-if="canOpenFull && !isExpandable"
          type="button"
          class="text-n-slate-11 px-1 leading-none text-sm text-center flex items-center gap-1 mt-2"
          @click="showFullView = true"
        >
          <Icon icon="i-lucide-maximize-2" />
          {{ $t('EMAIL_HEADER.FULL_VIEW') }}
        </button>
        <button
          v-if="hasQuotedMessage"
          class="text-n-slate-11 px-1 leading-none text-sm bg-n-alpha-black2 text-center flex items-center gap-1 mt-2"
          @click="showQuotedMessage = !showQuotedMessage"
        >
          <template v-if="showQuotedMessage">
            {{ $t('CHAT_LIST.HIDE_QUOTED_TEXT') }}
          </template>
          <template v-else>
            {{ $t('CHAT_LIST.SHOW_QUOTED_TEXT') }}
          </template>
          <Icon
            :icon="
              showQuotedMessage
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
          />
        </button>
      </div>
    </section>
    <EmailFullView
      v-if="showFullView"
      :title="emailSubject"
      @close="showFullView = false"
    >
      <Letter
        :key="`letter-full-${translationKeySuffix}-${showQuotedMessage}`"
        class-name="prose prose-bubble !max-w-none letter-render letter-full"
        :html="showQuotedMessage ? fullHTML : unquotedHTML"
        :allowed-css-properties="[
          ...allowedCssProperties,
          'transform',
          'transform-origin',
        ]"
        :text="textToShow"
      />
    </EmailFullView>
    <TranslationToggle
      v-if="!isCaptainMessage"
      class="py-2 px-3"
      :showing-original="showingOriginal"
      @toggle="handleSeeOriginal"
    />
    <section
      v-if="Array.isArray(attachments) && attachments.length"
      class="px-4 pb-4 space-y-2"
    >
      <AttachmentChips :attachments="attachments" class="gap-1" />
    </section>
  </BaseBubble>
</template>

<style lang="scss">
// Tailwind resets break the rendering of google drive link in Gmail messages
// This fixes it using https://developer.mozilla.org/en-US/docs/Web/CSS/Attribute_selectors

.letter-render [class*='gmail_drive_chip'] {
  box-sizing: initial;
  @apply bg-n-slate-4 border-n-slate-6 rounded-md !important;

  a {
    @apply text-n-slate-12 !important;

    img {
      display: inline-block;
    }
  }
}

// Tolzar: responsive e-mail content in the pane (no sideways scroll in normal cases); anything still wider is scaled
// down by emailFit.js. The full view keeps the e-mail's own widths.
.letter-render:not(.letter-full) {
  img,
  video {
    max-width: 100% !important;
    height: auto !important;
  }

  pre {
    white-space: pre-wrap;
  }

  a,
  td,
  p,
  span,
  div {
    overflow-wrap: anywhere;
  }
}

.letter-full img {
  max-width: 100%;
  height: auto;
}

// Email clients (Gmail, Outlook) hardcode dir="ltr" on wrapper elements.
// In RTL apps this forces email content LTR regardless of actual text.
[dir='rtl'] .letter-render [dir='ltr'] {
  direction: inherit;
}
</style>
