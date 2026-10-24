<script setup>
import { useAttrs } from 'vue';

// Tolzar: render the inline brand mark (bundled → cache-busts per build), not
// an <img> from globalConfig.logoThumbnail (served with a 1-year cache at a
// stable path, so a file swap never reaches existing browsers).
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
    <rect width="16" height="16" rx="4" fill="#12A594" />
    <path d="M3.6 4.3H12.4V6.3H9V12.4H7V6.3H3.6V4.3Z" fill="white" />
  </svg>
</template>
