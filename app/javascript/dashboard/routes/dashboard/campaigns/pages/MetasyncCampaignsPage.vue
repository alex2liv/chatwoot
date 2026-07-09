<script setup>
import { onMounted } from 'vue';
import { useI18n } from 'vue-i18n';

const METASYNC_URL = 'https://campanhas.metasyncdigital.com.br/';

const { t } = useI18n();

onMounted(() => {
  window.location.href = METASYNC_URL;
});
</script>

<template>
  <div
    class="flex flex-col items-center justify-center h-full gap-2 text-n-slate-11"
  >
    <p>{{ t('CAMPAIGN.METASYNC.REDIRECTING') }}</p>
    <a
      :href="METASYNC_URL"
      target="_blank"
      rel="noopener noreferrer"
      class="text-n-blue-11 underline"
    >
      {{ t('CAMPAIGN.METASYNC.OPEN_LINK') }}
    </a>
  </div>
</template>
