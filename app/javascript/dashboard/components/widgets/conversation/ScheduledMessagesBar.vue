<script setup>
// Metasync: lista as mensagens agendadas desta conversa acima da caixa de resposta.
import { ref, watch, onMounted, onBeforeUnmount, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useEmitter } from 'dashboard/composables/emitter';
import ScheduledMessagesApi from 'dashboard/api/inbox/scheduledMessages';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  conversationId: { type: [Number, String], default: null },
});

const items = ref([]);
const expanded = ref(true);
const editingId = ref(null);
const editContent = ref('');
const editWhen = ref('');
let timer = null;

const pending = computed(() =>
  items.value.filter(i => i.status === 'pending' || i.status === 'failed')
);

const pad = n => String(n).padStart(2, '0');
const toInputValue = date =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;

const formatWhen = ts =>
  new Date(ts * 1000).toLocaleString('pt-BR', {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

const fetchItems = async () => {
  if (!props.conversationId) {
    items.value = [];
    return;
  }
  try {
    const { data } = await ScheduledMessagesApi.list(props.conversationId);
    items.value = data.payload || [];
  } catch {
    // silencioso: a lista volta na proxima atualizacao
  }
};

useEmitter('metasync:scheduled-messages-changed', fetchItems);

watch(
  () => props.conversationId,
  () => {
    editingId.value = null;
    fetchItems();
  }
);

onMounted(() => {
  fetchItems();
  timer = setInterval(fetchItems, 60000);
});
onBeforeUnmount(() => clearInterval(timer));

const cancelItem = async item => {
  try {
    await ScheduledMessagesApi.cancel(props.conversationId, item.id);
    useAlert('Agendamento cancelado.');
  } catch {
    useAlert('Não foi possível cancelar.');
  }
  fetchItems();
};

const sendNow = async item => {
  try {
    const { data } = await ScheduledMessagesApi.sendNow(
      props.conversationId,
      item.id
    );
    useAlert(
      data.status === 'sent'
        ? 'Mensagem enviada.'
        : `Falhou: ${data.error_message || 'erro ao enviar'}`
    );
  } catch {
    useAlert('Não foi possível enviar agora.');
  }
  fetchItems();
};

const startEdit = item => {
  editingId.value = item.id;
  editContent.value = item.content;
  editWhen.value = toInputValue(new Date(item.scheduled_at * 1000));
};

const saveEdit = async item => {
  const date = new Date(editWhen.value);
  if (!editContent.value.trim() || Number.isNaN(date.getTime())) return;
  try {
    await ScheduledMessagesApi.update(props.conversationId, item.id, {
      content: editContent.value,
      scheduledAt: date.getTime(),
    });
    editingId.value = null;
    useAlert('Agendamento atualizado.');
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não foi possível salvar.');
  }
  fetchItems();
};
</script>

<template>
  <div
    v-if="pending.length"
    class="mx-2 mb-2 rounded-xl border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-sm text-n-slate-12"
  >
    <button
      type="button"
      class="flex w-full items-center gap-2 text-left font-medium"
      @click="expanded = !expanded"
    >
      <span class="i-lucide-clock size-4 text-n-blue-11" />
      <span>
        {{
          pending.length === 1
            ? '1 mensagem agendada'
            : `${pending.length} mensagens agendadas`
        }}
      </span>
      <span
        class="ml-auto size-4"
        :class="expanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
      />
    </button>
    <ul v-if="expanded" class="mt-2 flex flex-col gap-2">
      <li
        v-for="item in pending"
        :key="item.id"
        class="rounded-lg bg-n-solid-1 px-2 py-1.5"
      >
        <template v-if="editingId === item.id">
          <textarea
            v-model="editContent"
            rows="3"
            class="!mb-2 w-full rounded-lg !p-2 text-sm"
          />
          <div class="flex items-center gap-2">
            <input
              v-model="editWhen"
              type="datetime-local"
              class="!mb-0 h-8 flex-1 rounded-lg !px-2 text-sm"
            />
            <NextButton label="Salvar" xs @click="saveEdit(item)" />
            <NextButton
              label="Voltar"
              xs
              slate
              faded
              @click="editingId = null"
            />
          </div>
        </template>
        <template v-else>
          <div class="flex items-start gap-2">
            <div class="min-w-0 flex-1">
              <p class="text-xs text-n-slate-11">
                <span v-if="item.status === 'failed'" class="text-n-ruby-11">{{
                  `Falhou: ${item.error_message || ''} · `
                }}</span>
                {{ formatWhen(item.scheduled_at) }}
                {{ item.user ? `· ${item.user.name}` : '' }}
              </p>
              <p class="line-clamp-2 break-words">{{ item.content }}</p>
            </div>
            <div class="flex flex-shrink-0 gap-1">
              <NextButton
                v-tooltip.top="'Enviar agora'"
                icon="i-lucide-send"
                xs
                slate
                faded
                @click="sendNow(item)"
              />
              <NextButton
                v-if="item.status === 'pending'"
                v-tooltip.top="'Editar'"
                icon="i-lucide-pencil"
                xs
                slate
                faded
                @click="startEdit(item)"
              />
              <NextButton
                v-tooltip.top="'Cancelar agendamento'"
                icon="i-lucide-trash-2"
                xs
                ruby
                faded
                @click="cancelItem(item)"
              />
            </div>
          </div>
        </template>
      </li>
    </ul>
  </div>
</template>
