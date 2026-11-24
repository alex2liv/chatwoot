<script setup>
// Metasync: botao de relogio ao lado do Enviar para agendar a mensagem.
import { ref, computed } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['schedule']);

const TXT = {
  title: 'Agendar envio',
  custom: 'Escolher dia e hora',
  confirm: 'Agendar',
};

const open = ref(false);
const customValue = ref('');

const pad = n => String(n).padStart(2, '0');
const toInputValue = date =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;

const at = (daysAhead, hour, minute = 0) => {
  const d = new Date();
  d.setDate(d.getDate() + daysAhead);
  d.setHours(hour, minute, 0, 0);
  return d;
};

const nextMonday = () => {
  const d = at(0, 9);
  const diff = (8 - d.getDay()) % 7 || 7;
  d.setDate(d.getDate() + diff);
  return d;
};

const formatOption = date =>
  date.toLocaleString('pt-BR', {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

const quickOptions = computed(() => {
  const inOneHour = new Date(Date.now() + 60 * 60 * 1000);
  inOneHour.setSeconds(0, 0);
  return [
    { label: 'Daqui a 1 hora', date: inOneHour },
    { label: 'Amanhã de manhã', date: at(1, 8) },
    { label: 'Amanhã à tarde', date: at(1, 14) },
    { label: 'Segunda de manhã', date: nextMonday() },
  ];
});

const minValue = computed(() => toInputValue(new Date()));

const toggle = () => {
  if (props.disabled) return;
  if (!open.value) {
    const d = new Date(Date.now() + 60 * 60 * 1000);
    customValue.value = toInputValue(d);
  }
  open.value = !open.value;
};

const choose = date => {
  open.value = false;
  emit('schedule', date.getTime());
};

const chooseCustom = () => {
  if (!customValue.value) return;
  const date = new Date(customValue.value);
  if (Number.isNaN(date.getTime())) return;
  choose(date);
};
</script>

<template>
  <OnClickOutside class="relative" @trigger="open = false">
    <NextButton
      v-tooltip.top-end="TXT.title"
      icon="i-lucide-clock"
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
      class="absolute bottom-10 right-0 z-50 w-72 rounded-xl border border-n-weak bg-n-alpha-3 backdrop-blur-[100px] p-3 shadow-lg"
    >
      <p class="mb-2 text-sm font-medium text-n-slate-12">{{ TXT.title }}</p>
      <button
        v-for="option in quickOptions"
        :key="option.label"
        type="button"
        class="flex w-full items-center justify-between rounded-lg px-2 py-1.5 text-sm text-n-slate-12 hover:bg-n-alpha-2"
        @click="choose(option.date)"
      >
        <span>{{ option.label }}</span>
        <span class="text-xs text-n-slate-11">{{
          formatOption(option.date)
        }}</span>
      </button>
      <div class="mt-2 border-t border-n-weak pt-2">
        <label class="mb-1 block text-xs text-n-slate-11">{{
          TXT.custom
        }}</label>
        <div class="flex gap-2">
          <input
            v-model="customValue"
            type="datetime-local"
            :min="minValue"
            class="!mb-0 h-8 flex-1 rounded-lg !px-2 text-sm"
          />
          <NextButton
            :label="TXT.confirm"
            sm
            type="button"
            @click="chooseCustom"
          />
        </div>
      </div>
    </div>
  </OnClickOutside>
</template>
