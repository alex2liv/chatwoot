<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import DashboardAppFrame from 'dashboard/components/widgets/DashboardApp/Frame.vue';

const METASYNC_URL = 'https://campanhas.metasyncdigital.com.br/';

const { t } = useI18n();

// Reuses the same lazy-mount contract Frame.vue expects from its original
// caller (ConversationBox.vue): it only renders the iframe once `isVisible`
// flips from false to true (see its `hasOpenedAtleastOnce` watcher), so we
// mirror that transition here instead of passing `is-visible` as always true.
const isVisible = ref(false);
onMounted(() => {
  isVisible.value = true;
});
</script>

<template>
  <div class="flex flex-col h-full">
    <div class="flex justify-end px-4 py-2">
      <a
        :href="METASYNC_URL"
        target="_blank"
        rel="noopener noreferrer"
        class="text-sm text-n-blue-11 underline"
      >
        {{ t('CAMPAIGN.METASYNC.OPEN_NEW_TAB') }}
      </a>
    </div>
    <div class="flex-1 min-h-0">
      <DashboardAppFrame
        :config="[{ type: 'frame', url: METASYNC_URL }]"
        :current-chat="{}"
        :is-visible="isVisible"
        :position="0"
      />
    </div>
  </div>
</template>
