import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';

/**
 * Composable for internal chat Pro feature gating.
 *
 * In CE, the `internal_chat_pro` feature flag does not exist in features.yml,
 * so all Pro features remain locked. The Pro repo adds this flag and manages
 * it via subscription hub, unlocking features automatically.
 */
export function useInternalChatPro() {
  const currentUser = useMapGetter('getCurrentUser');
  const currentRole = useMapGetter('getCurrentRole');

  return {
    pollsEnabled: computed(() => true),
    maxPrivateChannels: computed(() => null),
    searchHistoryDays: computed(() => null),
    isSuperAdmin: computed(() => currentUser.value?.type === 'SuperAdmin'),
    isAdmin: computed(() => currentRole.value === 'administrator'),
  };
}
