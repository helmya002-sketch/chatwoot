<script setup>
import { onMounted, onBeforeUnmount, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { standalonePage } from './emailFit';

// Tolzar: "Open full email". A large modal (~90vw × 90vh, Esc closes) with the e-mail at full width and its own
// vertical scroll. The slot is the same sanitised <Letter> the bubble renders, so sanitisation and remote-image
// rules are unchanged; the new window and print use that rendered, already-sanitised HTML.
const props = defineProps({ title: { type: String, default: '' } });
const emit = defineEmits(['close']);
const { t } = useI18n();
const body = useTemplateRef('body');

const onKey = e => {
  if (e.key === 'Escape') emit('close');
};
onMounted(() => document.addEventListener('keydown', onKey));
onBeforeUnmount(() => document.removeEventListener('keydown', onKey));

const openWindow = print => {
  const html = body.value ? body.value.innerHTML : '';
  const win = window.open('', '_blank', 'noopener=no,width=1100,height=900');
  if (!win) return;
  win.opener = null;
  win.document.open();
  win.document.write(standalonePage(html, { title: props.title }));
  win.document.close();
  if (print) {
    win.focus();
    win.print();
  }
};
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-[9999] flex items-center justify-center bg-n-alpha-black1/60 p-[5vh_5vw]"
      role="dialog"
      aria-modal="true"
      :aria-label="t('EMAIL_HEADER.FULL_VIEW')"
      @click.self="emit('close')"
    >
      <div
        class="flex flex-col w-[90vw] h-[90vh] rounded-xl bg-n-solid-1 shadow-xl overflow-hidden"
      >
        <div
          class="flex items-center gap-2 px-4 py-2 border-b border-n-weak"
        >
          <span class="flex-1 min-w-0 text-sm font-medium truncate text-n-slate-12">
            {{ title || t('EMAIL_HEADER.FULL_VIEW') }}
          </span>
          <button
            type="button"
            class="flex items-center gap-1 px-2 py-1 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2"
            @click="openWindow(false)"
          >
            <Icon icon="i-lucide-external-link" />
            {{ t('EMAIL_HEADER.OPEN_WINDOW') }}
          </button>
          <button
            type="button"
            class="flex items-center gap-1 px-2 py-1 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2"
            @click="openWindow(true)"
          >
            <Icon icon="i-lucide-printer" />
            {{ t('EMAIL_HEADER.PRINT') }}
          </button>
          <button
            type="button"
            class="p-1 rounded-md text-n-slate-11 hover:bg-n-alpha-2"
            :aria-label="t('EMAIL_HEADER.CLOSE')"
            @click="emit('close')"
          >
            <Icon icon="i-lucide-x" />
          </button>
        </div>
        <div ref="body" class="flex-1 overflow-auto p-6 bg-white text-[#0F172A]">
          <slot />
        </div>
      </div>
    </div>
  </Teleport>
</template>
