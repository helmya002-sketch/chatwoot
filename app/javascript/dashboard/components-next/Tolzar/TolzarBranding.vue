<script>
import { reactive } from 'vue';

// The product's own name and tab icon; a workspace's branding replaces them while it is open.
export const DEFAULT_PRODUCT_NAME = 'Tolzar';
export const DEFAULT_FAVICON = '/favicon-32x32.png';

// The current workspace's branding, readable by any Tolzar component (copilot card, briefing,
// contact panel) so the product name never has to be a literal there.
export const tolzarBrand = reactive({
  productName: DEFAULT_PRODUCT_NAME,
  color: '',
  logoUrl: '',
});

// Only an https image URL may become the tab icon.
export const safeLogoUrl = url => {
  const s = String(url || '');
  if (!/^https:\/\//.test(s)) return '';
  try {
    const { pathname } = new URL(s);
    return /\.(png|jpe?g|gif|webp|svg|ico)$/i.test(pathname) ? s : '';
  } catch {
    return '';
  }
};
</script>

<script setup>
// Tolzar white-label (R11): applies the current workspace's branding app-wide, for everyone in
// it: the brand colour on the brand utility classes, the product name in the browser tab, and the
// logo as the tab icon.
// Read-only endpoint (no settings, no secrets); nothing changes when a workspace has no branding.
import { watch, onBeforeUnmount } from 'vue';

const props = defineProps({
  accountId: { type: [Number, String], default: null },
});
let observer = null;
let name = '';

const STYLE_ID = 'tz-workspace-brand';
function applyColor(color) {
  let el = document.getElementById(STYLE_ID);
  if (!/^#[0-9a-fA-F]{6}$/.test(color || '')) {
    if (el) el.remove();
    tolzarBrand.color = '';
    return;
  }
  if (!el) {
    el = document.createElement('style');
    el.id = STYLE_ID;
    document.head.appendChild(el);
  }
  el.textContent = `.bg-n-brand{background-color:${color}!important}.text-n-brand{color:${color}!important}.border-n-brand{border-color:${color}!important}.ring-n-brand\\/20{--tw-ring-color:${color}33!important}`;
  tolzarBrand.color = color;
}
// The logo (an https image URL) as the browser-tab icon; without one, Tolzar's own icon comes
// back from its constant path, whatever workspace was open before.
function applyLogo(url) {
  const safe = safeLogoUrl(url);
  tolzarBrand.logoUrl = safe;
  const link = document.querySelector('link[rel~="icon"]');
  if (!link) return;
  link.href = safe || DEFAULT_FAVICON;
}
function retitle() {
  if (name && document.title && !document.title.includes(name)) {
    document.title = document.title.replace(/Tolzar|Chatwoot/g, name);
  }
}
function applyName(productName) {
  name = (productName || '').trim();
  tolzarBrand.productName = name || DEFAULT_PRODUCT_NAME;
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
      const { data } = await window.axios.get(
        `/api/v1/accounts/${id}/tolzar/branding`
      );
      const b = data.branding || {};
      applyColor(b.color);
      applyName(b.product_name);
      applyLogo(b.logo_url);
    } catch (e) {
      applyColor('');
      applyName('');
      applyLogo('');
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => observer && observer.disconnect());
</script>

<template>
  <span class="hidden" />
</template>
