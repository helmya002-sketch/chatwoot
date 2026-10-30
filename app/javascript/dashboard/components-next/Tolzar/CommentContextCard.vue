<script setup>
// Tolzar: what a Facebook / Instagram comment thread is about, at the top of the conversation. The post,
// ad, reel or story the customer commented on (Tolzar::MetaCommentContextJob stores it on
// additional_attributes.tolzar_comment.context): picture, text or caption, type and a link to open it.
// While the job runs (a few seconds after the first comment) the card shows the link Meta sent, if any.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  comment: { type: Object, required: true },
});

const { t } = useI18n();
const context = computed(() => props.comment?.context || {});
const platform = computed(() =>
  props.comment?.platform === 'instagram' ? 'INSTAGRAM' : 'FACEBOOK'
);
const TYPES = ['post', 'photo', 'video', 'reel', 'story', 'ad'];
const typeLabel = computed(() => {
  const type = TYPES.includes(context.value.type) ? context.value.type : 'post';
  return t(`TOLZAR_COMMENT_CONTEXT.TYPE.${type.toUpperCase()}`);
});
const text = computed(
  () => context.value.text || props.comment?.post_text || ''
);
const link = computed(
  () => context.value.permalink || props.comment?.permalink || ''
);
const loading = computed(() => !props.comment?.context);
const unavailable = computed(() => !!context.value.unavailable);
const expanded = ref(false);
const pictureFailed = ref(false);
const picture = computed(() =>
  pictureFailed.value ? '' : context.value.thumbnail_path || ''
);

watch(
  () => props.comment,
  () => {
    expanded.value = false;
    pictureFailed.value = false;
  }
);
</script>

<template>
  <li class="px-4 pt-3 pb-1 list-none" data-clarity-mask="True">
    <div
      class="w-full max-w-md overflow-hidden border rounded-xl bg-n-alpha-1 border-n-weak"
    >
      <div
        class="flex items-center gap-2 px-3 py-2 border-b border-n-weak text-xs font-medium text-n-slate-11"
      >
        <span
          class="i-lucide-message-square-text size-3.5"
          aria-hidden="true"
        />
        <span>
          {{
            $t('TOLZAR_COMMENT_CONTEXT.HEADING', {
              type: typeLabel,
              platform: $t(`TOLZAR_COMMENT_CONTEXT.PLATFORM.${platform}`),
            })
          }}
        </span>
      </div>
      <div class="flex gap-3 p-3">
        <img
          v-if="picture"
          :src="picture"
          :alt="$t('TOLZAR_COMMENT_CONTEXT.PICTURE_ALT')"
          class="size-16 shrink-0 rounded-lg object-cover bg-n-alpha-2"
          loading="lazy"
          @error="pictureFailed = true"
        />
        <div class="min-w-0 flex-1 text-sm">
          <p v-if="loading" class="text-n-slate-10">
            {{ $t('TOLZAR_COMMENT_CONTEXT.LOADING') }}
          </p>
          <p v-else-if="unavailable" class="text-n-slate-10">
            {{ $t('TOLZAR_COMMENT_CONTEXT.UNAVAILABLE') }}
          </p>
          <p
            v-else-if="text"
            class="whitespace-pre-line text-n-slate-12 break-words"
            :class="expanded ? '' : 'line-clamp-3'"
          >
            {{ text }}
          </p>
          <p v-else class="text-n-slate-10">
            {{ $t('TOLZAR_COMMENT_CONTEXT.NO_TEXT') }}
          </p>
          <div class="mt-1.5 flex flex-wrap items-center gap-3 text-xs">
            <button
              v-if="text && text.length > 160"
              type="button"
              class="text-n-iris-11 hover:underline"
              @click="expanded = !expanded"
            >
              {{
                expanded
                  ? $t('TOLZAR_COMMENT_CONTEXT.LESS')
                  : $t('TOLZAR_COMMENT_CONTEXT.MORE')
              }}
            </button>
            <a
              v-if="link"
              :href="link"
              target="_blank"
              rel="noopener noreferrer nofollow"
              class="inline-flex items-center gap-1 text-n-iris-11 hover:underline"
            >
              {{
                $t('TOLZAR_COMMENT_CONTEXT.OPEN', {
                  platform: $t(`TOLZAR_COMMENT_CONTEXT.PLATFORM.${platform}`),
                })
              }}
              <span class="i-lucide-external-link size-3" aria-hidden="true" />
            </a>
          </div>
        </div>
      </div>
    </div>
  </li>
</template>
