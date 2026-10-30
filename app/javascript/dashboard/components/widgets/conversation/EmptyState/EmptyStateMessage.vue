<script>
import FeaturePlaceholder from './FeaturePlaceholder.vue';
export default {
  components: { FeaturePlaceholder },
  props: {
    message: {
      type: String,
      required: true,
    },
  },
};
</script>

<template>
  <div class="flex flex-col items-center justify-center h-full">
    <div
      class="m-4 flex size-16 items-center justify-center rounded-2xl bg-n-brand/10"
      aria-hidden="true"
    >
      <span class="i-lucide-message-square-text size-8 text-n-brand" />
    </div>
    <span class="text-sm text-n-slate-12 font-medium text-center">
      {{ message }}
      <br />
    </span>
    <!-- Cmd bar, keyboard shortcuts placeholder -->
    <FeaturePlaceholder />
  </div>
</template>
