<script setup>
// Metasync: botao de figurinhas (igual ao WhatsApp) ao lado do Enviar.
import { ref, computed } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useAlert } from 'dashboard/composables';
import { useEmitter } from 'dashboard/composables/emitter';
import MetasyncStickersApi from 'dashboard/api/metasyncStickers';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['send']);

const TXT = {
  title: 'Figurinhas',
  mine: 'Minhas',
  company: 'Da empresa',
  emptyMine:
    'Nenhuma figurinha salva ainda. Clique com o botão direito numa figurinha ou imagem da conversa e escolha "Salvar nas minhas figurinhas".',
  emptyCompany:
    'A empresa ainda não tem figurinhas. Um administrador pode salvar clicando com o botão direito numa figurinha da conversa.',
  remove: 'Apagar figurinha',
  manage: 'Organizar',
  done: 'Pronto',
  manageHint: 'Clique na lixeira para apagar as figurinhas que não quer mais.',
  removed: 'Figurinha removida.',
  removeError: 'Não foi possível remover.',
  loadError: 'Não foi possível carregar as figurinhas.',
};

const open = ref(false);
const tab = ref('mine');
const managing = ref(false);
const loading = ref(false);
const data = ref({
  mine: [],
  company: [],
  limits: {},
  can_manage_company: false,
});

const items = computed(() => data.value[tab.value] || []);
const counter = computed(
  () => `${items.value.length}/${data.value.limits?.[tab.value] ?? 30}`
);
const canRemove = computed(
  () => tab.value === 'mine' || data.value.can_manage_company
);

const fetchStickers = async () => {
  loading.value = true;
  try {
    const response = await MetasyncStickersApi.list();
    data.value = response.data;
  } catch {
    useAlert(TXT.loadError);
  } finally {
    loading.value = false;
  }
};

useEmitter('metasync:stickers-changed', () => {
  if (open.value) fetchStickers();
});

const toggle = () => {
  if (props.disabled) return;
  open.value = !open.value;
  managing.value = false;
  if (open.value) fetchStickers();
};

const choose = sticker => {
  if (managing.value) return;
  open.value = false;
  emit('send', { id: sticker.id, url: sticker.url });
};

const removeSticker = async sticker => {
  try {
    await MetasyncStickersApi.remove(sticker.id);
    useAlert(TXT.removed);
    await fetchStickers();
    if (!items.value.length) managing.value = false;
  } catch {
    useAlert(TXT.removeError);
  }
};
</script>

<template>
  <OnClickOutside class="relative" @trigger="open = false">
    <NextButton
      v-tooltip.top-end="TXT.title"
      icon="i-lucide-sticker"
      slate
      faded
      sm
      type="button"
      :disabled="disabled"
      class="flex-shrink-0"
      @click="toggle"
    />
    <div
      v-if="open"
      class="absolute bottom-10 right-0 z-50 w-80 rounded-xl border border-n-weak bg-n-alpha-3 backdrop-blur-[100px] p-3 shadow-lg"
    >
      <div class="mb-2 flex items-center gap-1">
        <button
          v-for="key in ['mine', 'company']"
          :key="key"
          type="button"
          class="rounded-lg px-2 py-1 text-sm"
          :class="
            tab === key
              ? 'bg-n-alpha-2 font-medium text-n-slate-12'
              : 'text-n-slate-11 hover:bg-n-alpha-1'
          "
          @click="tab = key"
        >
          {{ TXT[key] }}
        </button>
        <span class="ml-auto text-xs text-n-slate-11">{{ counter }}</span>
        <button
          v-if="canRemove && items.length"
          type="button"
          class="rounded-lg px-2 py-1 text-xs"
          :class="
            managing
              ? 'bg-n-ruby-9 text-white'
              : 'text-n-slate-11 hover:bg-n-alpha-1'
          "
          @click="managing = !managing"
        >
          {{ managing ? TXT.done : TXT.manage }}
        </button>
      </div>
      <p v-if="managing" class="mb-2 text-xs text-n-slate-11">
        {{ TXT.manageHint }}
      </p>
      <div
        v-if="!loading && !items.length"
        class="px-1 py-4 text-center text-xs text-n-slate-11"
      >
        {{ tab === 'mine' ? TXT.emptyMine : TXT.emptyCompany }}
      </div>
      <div v-else class="grid max-h-64 grid-cols-4 gap-2 overflow-y-auto">
        <div
          v-for="sticker in items"
          :key="sticker.id"
          class="group relative aspect-square"
        >
          <button
            type="button"
            class="size-full rounded-lg p-1 hover:bg-n-alpha-2"
            :class="{ 'opacity-60': managing }"
            @click="choose(sticker)"
          >
            <img
              :src="sticker.url"
              alt=""
              loading="lazy"
              class="size-full object-contain"
            />
          </button>
          <button
            v-if="canRemove"
            v-tooltip.top="TXT.remove"
            type="button"
            class="absolute right-1 top-1 size-6 items-center justify-center rounded-full bg-n-ruby-9 text-white shadow"
            :class="managing ? 'flex' : 'hidden group-hover:flex'"
            @click.stop="removeSticker(sticker)"
          >
            <span class="i-lucide-trash-2 size-3.5" />
          </button>
        </div>
      </div>
    </div>
  </OnClickOutside>
</template>
