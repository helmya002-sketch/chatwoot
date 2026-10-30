<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// "You have unsaved changes" as a promise: `await dialogRef.value.ask()` → true to leave, false to stay.
// Shares the app's Dialog (themed, translatable, Esc closes), replacing window.confirm.
const { t } = useI18n();
const dialogRef = ref(null);
let resolver = null;

const settle = v => {
  if (resolver) resolver(v);
  resolver = null;
};
const ask = () =>
  new Promise(resolve => {
    resolver = resolve;
    dialogRef.value?.open();
  });
const onConfirm = () => {
  dialogRef.value?.close();
  settle(true);
};
const onClose = () => settle(false);

defineExpose({ ask });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('TOLZAR_UI.UNSAVED.TITLE')"
    :description="t('TOLZAR_UI.UNSAVED.BODY')"
    :confirm-button-label="t('TOLZAR_UI.UNSAVED.LEAVE')"
    :cancel-button-label="t('TOLZAR_UI.UNSAVED.STAY')"
    @confirm="onConfirm"
    @close="onClose"
  />
</template>
