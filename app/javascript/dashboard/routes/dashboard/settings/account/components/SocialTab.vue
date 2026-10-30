<script setup>
// Tolzar: the optional Social tab (owner 30 Oct). On, public social threads (Facebook / Instagram comments)
// get their own Social view and leave the normal inbox views; off (the default), one inbox as before.
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const isEnabled = ref(false);
const { currentAccount, updateAccount } = useAccount();

watch(
  currentAccount,
  () => {
    isEnabled.value = !!currentAccount.value?.settings?.tolzar_social_tab;
  },
  { deep: true, immediate: true }
);

const toggleSocialTab = async () => {
  try {
    await updateAccount({ tolzar_social_tab: isEnabled.value });
    useAlert(t('TOLZAR_SOCIAL.SETTING.SUCCESS'));
  } catch (error) {
    useAlert(t('TOLZAR_SOCIAL.SETTING.ERROR'));
  }
};
</script>

<template>
  <SectionLayout
    :title="t('TOLZAR_SOCIAL.SETTING.TITLE')"
    :description="t('TOLZAR_SOCIAL.SETTING.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch v-model="isEnabled" @change="toggleSocialTab" />
      </div>
    </template>
  </SectionLayout>
</template>
