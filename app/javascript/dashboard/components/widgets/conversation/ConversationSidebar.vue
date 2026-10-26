<script setup>
import { computed } from 'vue';
import ContactPanel from 'dashboard/routes/dashboard/conversation/ContactPanel.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import wootConstants from 'dashboard/constants/globals';
import { useResizablePane } from 'dashboard/composables/useResizablePane';

defineProps({
  currentChat: {
    required: true,
    type: Object,
  },
});

const { uiSettings, updateUISettings } = useUISettings();
const { width: windowWidth } = useWindowSize();

// Tolzar #2: draggable conversation↔contact-pane boundary (desktop only, where
// the pane is a static flex sibling; on mobile it is a full-width overlay).
const tzDesktop = computed(() => windowWidth.value >= 768);
const {
  widthStyle: tzContactStyle,
  startDrag: tzContactDrag,
  reset: tzContactReset,
} = useResizablePane('tz_contact_width', { min: 300, max: 520 });

const activeTab = computed(() => {
  const { is_contact_sidebar_open: isContactSidebarOpen } = uiSettings.value;

  if (isContactSidebarOpen) {
    return 0;
  }
  return null;
});

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

const closeContactPanel = () => {
  if (isSmallScreen.value && uiSettings.value?.is_contact_sidebar_open) {
    updateUISettings({
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
  }
};
</script>

<template>
  <div
    v-on-click-outside="[
      () => closeContactPanel(),
      {
        ignore: [
          'dialog.ProseMirror-prompt-backdrop',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    class="bg-n-surface-2 h-full overflow-hidden flex flex-col fixed top-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out ltr:right-0 rtl:left-0 md:relative md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[360px] 2xl:w-[360px] shadow-lg md:shadow-none"
    :class="[
      {
        'md:flex': activeTab === 0,
        'md:hidden': activeTab !== 0,
      },
    ]"
    :style="tzDesktop ? tzContactStyle : {}"
  >
    <!-- Tolzar #2: drag to resize the contact pane; double-click to reset -->
    <div
      v-if="tzDesktop"
      class="tz-resize-left"
      title="Drag to resize · double-click to reset"
      @pointerdown="e => tzContactDrag(e, 'start')"
      @dblclick="tzContactReset"
    />
    <div class="flex flex-1 overflow-auto">
      <ContactPanel
        v-show="activeTab === 0"
        :conversation-id="currentChat.id"
        :inbox-id="currentChat.inbox_id"
      />
    </div>
  </div>
</template>

<style scoped>
/* Tolzar #2: left-edge resize handle for the contact pane (kept inside the
   pane's overflow:hidden box so it is never clipped) */
.tz-resize-left {
  position: absolute;
  top: 0;
  bottom: 0;
  inset-inline-start: 0;
  width: 7px;
  z-index: 30;
  cursor: col-resize;
  touch-action: none;
}
.tz-resize-left::after {
  content: '';
  position: absolute;
  top: 0;
  bottom: 0;
  inset-inline-start: 1px;
  width: 2px;
  background: transparent;
  transition: background 0.12s ease;
}
.tz-resize-left:hover::after,
.tz-resize-left:active::after {
  background: rgb(var(--blue-9));
}
</style>
