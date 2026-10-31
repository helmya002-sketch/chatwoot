<script setup>
import { ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// A themed yes/no (or type-to-confirm) dialog as a promise. Replaces window.confirm/prompt.
//   const ok = await confirmRef.value.ask({ title, description, confirmLabel, danger: true });
//   const typed = await confirmRef.value.ask({ ..., input: { label, placeholder, match: 'DELETE' } });
// Resolves false when dismissed; with `input`, resolves the typed string (or false).
const dialogRef = ref(null);
const opts = ref({});
const text = ref('');
let resolver = null;

const settle = v => {
  if (resolver) resolver(v);
  resolver = null;
};
const ask = (o = {}) =>
  new Promise(resolve => {
    opts.value = o;
    text.value = o.input?.initial || '';
    resolver = resolve;
    dialogRef.value?.open();
  });
const confirm = () => {
  const v = opts.value.input ? text.value : true;
  dialogRef.value?.close();
  settle(v);
};
const disabled = () => {
  const i = opts.value.input;
  if (!i) return false;
  if (i.match) return text.value.trim() !== String(i.match).trim();
  return i.required ? !text.value.trim() : false;
};

defineExpose({ ask });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :type="opts.danger ? 'alert' : 'edit'"
    :title="opts.title || ''"
    :description="opts.description || ''"
    :confirm-button-label="opts.confirmLabel || ''"
    :cancel-button-label="opts.cancelLabel || ''"
    :disable-confirm-button="disabled()"
    @confirm="confirm"
    @close="settle(false)"
  >
    <template v-if="opts.input">
      <label v-if="opts.input.label" class="block mt-3 mb-1 text-xs text-n-slate-11">{{ opts.input.label }}</label>
      <input
        v-model="text"
        class="box-border w-full px-2.5 py-2 text-[13px] text-n-slate-12 bg-n-solid-1 border border-solid border-n-weak rounded-lg outline-none"
        :placeholder="opts.input.placeholder || ''"
        :aria-label="opts.input.label"
        @keydown.enter.prevent="!disabled() && confirm()"
      />
    </template>
  </Dialog>
</template>
