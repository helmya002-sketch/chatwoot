<script setup>
import { useAttrs } from 'vue';

// Tolzar brand mark — a royal-blue chat bubble with an AI spark ("intelligent
// conversations"). Rendered inline (bundled → cache-busts per build), not an
// <img> from globalConfig.logoThumbnail (served with a 1-year cache at a stable
// path, so a file swap never reaches existing browsers).
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
    <!-- chat bubble (white) + tail -->
    <rect x="2.6" y="2.9" width="10.8" height="7.1" rx="2.3" fill="#fff" />
    <path
      d="M4.75 8.9 L4.75 12.25 A0.5 0.5 0 0 0 5.57 12.62 L8.7 9.5 Z"
      fill="#fff"
    />
    <!-- 4-point AI spark (knocked out to brand blue) -->
    <path
      d="M8 3.75c.28 1.72.55 1.99 2.27 2.27-1.72.28-1.99.55-2.27 2.27-.28-1.72-.55-1.99-2.27-2.27 1.72-.28 1.99-.55 2.27-2.27Z"
      fill="#3E63DD"
    />
  </svg>
</template>
