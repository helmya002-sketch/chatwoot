<script setup>
import { useAttrs } from 'vue';

// Tolzar brand mark — a custom royal-blue monogram "T" with a rounded
// signature foot (an ownable letterform, not a generic chat glyph).
// Rendered inline (bundled → cache-busts per build), not an <img> from
// globalConfig.logoThumbnail (served with a 1-year cache at a stable path,
// so a file swap never reaches existing browsers).
const attrs = useAttrs();
</script>

<template>
  <svg
    v-once
    v-bind="attrs"
    width="16"
    height="16"
    viewBox="0 0 16 16"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
  >
    <rect width="16" height="16" rx="4" fill="#3E63DD" />
    <path d="M3 4.3 H13" stroke="#fff" stroke-width="2.6" stroke-linecap="round" />
    <path
      d="M8 4.3 V10.1 a2.4 2.4 0 0 0 2.4 2.4"
      stroke="#fff"
      stroke-width="2.6"
      stroke-linecap="round"
      fill="none"
    />
  </svg>
</template>
