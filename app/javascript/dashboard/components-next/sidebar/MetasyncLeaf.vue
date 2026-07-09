<script setup>
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  label: {
    type: String,
    required: true,
  },
  icon: {
    type: [String, Object],
    default: null,
  },
});

const METASYNC_URL = 'https://campanhas.metasyncdigital.com.br/';

// Opens Metasync in a new tab instead of following the sidebar's internal
// router-link navigation (the fallback route it points to is only reached
// when this handler is bypassed, e.g. middle-click / "open in new tab").
const openMetasync = () => {
  window.open(METASYNC_URL, '_blank', 'noopener,noreferrer');
};
</script>

<template>
  <div class="contents" @click.stop.prevent="openMetasync">
    <span v-if="icon" class="size-4 grid place-content-center rounded-full">
      <Icon :icon="icon" class="size-4 inline-block" />
    </span>
    <div class="flex-1 truncate min-w-0 text-sm">{{ props.label }}</div>
  </div>
</template>
