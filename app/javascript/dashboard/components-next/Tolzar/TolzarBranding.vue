<script setup>
// Tolzar white-label (R11): applies the current workspace's branding app-wide, for everyone in
// it: the brand colour on the brand utility classes, and the product name in the browser tab.
// Read-only endpoint (no settings, no secrets); nothing changes when a workspace has no branding.
import { watch, onBeforeUnmount } from 'vue';

const props = defineProps({ accountId: { type: [Number, String], default: null } });
let observer = null;
let name = '';

const STYLE_ID = 'tz-workspace-brand';
function applyColor(color) {
  let el = document.getElementById(STYLE_ID);
  if (!/^#[0-9a-fA-F]{6}$/.test(color || '')) {
    if (el) el.remove();
    return;
  }
  if (!el) {
    el = document.createElement('style');
    el.id = STYLE_ID;
    document.head.appendChild(el);
  }
  el.textContent = `.bg-n-brand{background-color:${color}!important}.text-n-brand{color:${color}!important}.border-n-brand{border-color:${color}!important}.ring-n-brand\\/20{--tw-ring-color:${color}33!important}`;
}
function retitle() {
  if (name && document.title && !document.title.includes(name)) {
    document.title = document.title.replace(/Tolzar|Chatwoot/g, name);
  }
}
function applyName(productName) {
  name = (productName || '').trim();
  if (observer) observer.disconnect();
  if (!name) return;
  retitle();
  const title = document.querySelector('title');
  if (title) {
    observer = new MutationObserver(retitle);
    observer.observe(title, { childList: true });
  }
}

watch(
  () => props.accountId,
  async id => {
    if (!id) return;
    try {
      const { data } = await window.axios.get(`/api/v1/accounts/${id}/tolzar/branding`);
      const b = data.branding || {};
      applyColor(b.color);
      applyName(b.product_name);
    } catch (e) {
      applyColor('');
      applyName('');
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => observer && observer.disconnect());
</script>

<template>
  <span class="hidden" />
</template>
