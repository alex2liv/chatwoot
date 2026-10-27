<script>
import { useAlert } from 'dashboard/composables';
import { mapGetters } from 'vuex';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import AddCannedModal from 'dashboard/routes/dashboard/settings/canned/AddCanned.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import { conversationUrl, frontendURL } from '../../../helper/URLHelper';
import {
  ACCOUNT_EVENTS,
  CONVERSATION_EVENTS,
} from '../../../helper/AnalyticsHelper/events';
import MenuItem from '../../../components/widgets/conversation/contextMenu/menuItem.vue';
import { useTrack } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ReportCaptainMessageDialog from './ReportCaptainMessageDialog.vue';
import ContactAPI from 'dashboard/api/contacts';
import MessageApi from 'dashboard/api/inbox/message';

export default {
  components: {
    AddCannedModal,
    MenuItem,
    ContextMenu,
    NextButton,
    ReportCaptainMessageDialog,
  },
  props: {
    message: {
      type: Object,
      required: true,
    },
    isOpen: {
      type: Boolean,
      default: false,
    },
    enabledOptions: {
      type: Object,
      default: () => ({}),
    },
    contextMenuPosition: {
      type: Object,
      default: () => ({}),
    },
    hideButton: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['open', 'close', 'replyTo', 'forwardEmail'],
  setup() {
    const { getPlainText } = useMessageFormatter();

    return {
      getPlainText,
    };
  },
  data() {
    return {
      isCannedResponseModalOpen: false,
      showDeleteModal: false,
      showEditModal: false,
      editText: '',
      isSavingEdit: false,
      showForwardModal: false,
      forwardQuery: '',
      forwardResults: [],
      forwardSelected: [],
      isSearchingForward: false,
      isSendingForward: false,
      forwardSearchTimer: null,
      forwardSearchSeq: 0,
      forwardMode: 'contacts',
      forwardCompanies: [],
      forwardCompany: null,
    };
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      currentAccountId: 'getCurrentAccountId',
      getUISettings: 'getUISettings',
    }),
    plainTextContent() {
      return this.getPlainText(this.messageContent);
    },
    conversationId() {
      return this.message.conversation_id ?? this.message.conversationId;
    },
    messageId() {
      return this.message.id;
    },
    messageContent() {
      return this.message.content;
    },
    contentAttributes() {
      return useSnakeCase(
        this.message.content_attributes ?? this.message.contentAttributes
      );
    },
  },
  methods: {
    async copyLinkToMessage() {
      const fullConversationURL =
        window.chatwootConfig.hostURL +
        frontendURL(
          conversationUrl({
            id: this.conversationId,
            accountId: this.currentAccountId,
          })
        );
      await copyTextToClipboard(
        `${fullConversationURL}?messageId=${this.messageId}`
      );
      useAlert(this.$t('CONVERSATION.CONTEXT_MENU.LINK_COPIED'));
      this.handleClose();
    },
    async handleCopy() {
      await copyTextToClipboard(this.plainTextContent);
      useAlert(this.$t('CONTACT_PANEL.COPY_SUCCESSFUL'));
      this.handleClose();
    },
    showCannedResponseModal() {
      useTrack(ACCOUNT_EVENTS.ADDED_TO_CANNED_RESPONSE);
      this.isCannedResponseModalOpen = true;
    },
    hideCannedResponseModal() {
      this.isCannedResponseModalOpen = false;
      this.handleClose();
    },
    handleOpen(e) {
      this.$emit('open', e);
    },
    handleClose(e) {
      this.$emit('close', e);
    },
    async handleTranslate() {
      const { locale: accountLocale } = this.getAccount(this.currentAccountId);
      const agentLocale = this.getUISettings?.locale;
      const targetLanguage = agentLocale || accountLocale || 'en';
      try {
        await this.$store.dispatch('translateMessage', {
          conversationId: this.conversationId,
          messageId: this.messageId,
          targetLanguage,
        });
        useTrack(CONVERSATION_EVENTS.TRANSLATE_A_MESSAGE);
      } catch (error) {
        useAlert(parseAPIErrorResponse(error));
      }
      this.handleClose();
    },
    handleReplyTo() {
      this.$emit('replyTo', this.message);
      this.handleClose();
    },
    handleForwardEmail() {
      this.$emit('forwardEmail');
      this.handleClose();
    },
    openEditModal() {
      this.handleClose();
      this.editText = this.message.original_content ?? this.messageContent ?? '';
      this.showEditModal = true;
    },
    closeEditModal() {
      this.showEditModal = false;
      this.isSavingEdit = false;
    },
    async saveEdit() {
      const content = (this.editText || '').trim();
      if (!content || this.isSavingEdit) return;
      this.isSavingEdit = true;
      try {
        await this.$store.dispatch('editMessageContent', {
          conversationId: this.conversationId,
          messageId: this.messageId,
          content,
        });
        useAlert(this.$t('CONVERSATION.CONTEXT_MENU.EDIT_MESSAGE.SUCCESS'));
        this.closeEditModal();
      } catch (error) {
        useAlert(
          error?.response?.data?.error ||
            this.$t('CONVERSATION.CONTEXT_MENU.EDIT_MESSAGE.ERROR')
        );
        this.isSavingEdit = false;
      }
    },
    onEditKeydown(e) {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        this.saveEdit();
      }
    },
    openForwardModal() {
      this.handleClose();
      this.forwardQuery = '';
      this.forwardResults = [];
      this.forwardSelected = [];
      this.isSendingForward = false;
      this.forwardMode = 'contacts';
      this.forwardCompanies = [];
      this.forwardCompany = null;
      this.showForwardModal = true;
    },
    setForwardMode(mode) {
      if (this.forwardMode === mode) return;
      this.forwardMode = mode;
      this.forwardQuery = '';
      this.forwardResults = [];
      this.forwardCompanies = [];
      this.forwardCompany = null;
      this.forwardSearchSeq += 1;
      this.isSearchingForward = false;
      if (mode === 'company') this.searchCompanies('');
    },
    async searchCompanies(query) {
      this.forwardSearchSeq += 1;
      const seq = this.forwardSearchSeq;
      this.isSearchingForward = true;
      try {
        const { data } = await MessageApi.forwardCompanies(
          this.conversationId,
          this.messageId,
          query
        );
        if (seq !== this.forwardSearchSeq) return;
        this.forwardCompanies = (data && data.payload) || [];
      } catch (error) {
        if (seq === this.forwardSearchSeq) this.forwardCompanies = [];
      } finally {
        if (seq === this.forwardSearchSeq) this.isSearchingForward = false;
      }
    },
    selectForwardCompany(company) {
      this.forwardCompany =
        this.forwardCompany && this.forwardCompany.name === company.name
          ? null
          : company;
    },
    async sendForwardCompany() {
      if (!this.forwardCompany || this.isSendingForward) return;
      this.isSendingForward = true;
      try {
        const { data } = await MessageApi.forwardToCompany(
          this.conversationId,
          this.messageId,
          this.forwardCompany.name
        );
        const payload = (data && data.payload) || {};
        useAlert(
          this.$t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.COMPANY_SUCCESS', {
            count: payload.queued || 0,
            company: payload.company || this.forwardCompany.name,
          })
        );
        this.closeForwardModal();
      } catch (error) {
        useAlert(
          (error && error.response && error.response.data && error.response.data.error) ||
            this.$t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.ERROR')
        );
      } finally {
        this.isSendingForward = false;
      }
    },
    closeForwardModal() {
      this.showForwardModal = false;
      clearTimeout(this.forwardSearchTimer);
    },
    onForwardQueryInput() {
      clearTimeout(this.forwardSearchTimer);
      const query = (this.forwardQuery || '').trim();
      if (this.forwardMode === 'company') {
        this.forwardSearchTimer = setTimeout(
          () => this.searchCompanies(query),
          300
        );
        return;
      }
      if (query.length < 2) {
        this.forwardResults = [];
        return;
      }
      this.forwardSearchTimer = setTimeout(() => this.searchForward(query), 300);
    },
    async searchForward(query) {
      this.forwardSearchSeq += 1;
      const seq = this.forwardSearchSeq;
      this.isSearchingForward = true;
      try {
        const { data } = await ContactAPI.search(query);
        if (seq !== this.forwardSearchSeq) return;
        this.forwardResults = ((data && data.payload) || []).slice(0, 15);
      } catch (error) {
        if (seq === this.forwardSearchSeq) this.forwardResults = [];
      } finally {
        if (seq === this.forwardSearchSeq) this.isSearchingForward = false;
      }
    },
    isForwardSelected(contact) {
      return this.forwardSelected.some(c => c.id === contact.id);
    },
    toggleForwardContact(contact) {
      if (this.isForwardSelected(contact)) {
        this.forwardSelected = this.forwardSelected.filter(
          c => c.id !== contact.id
        );
        return;
      }
      if (this.forwardSelected.length >= 5) {
        useAlert(this.$t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.MAX'));
        return;
      }
      this.forwardSelected = this.forwardSelected.concat([contact]);
    },
    forwardContactLine(contact) {
      return contact.phone_number || contact.identifier || contact.email || '';
    },
    async sendForward() {
      if (!this.forwardSelected.length || this.isSendingForward) return;
      this.isSendingForward = true;
      try {
        const { data } = await MessageApi.forwardWhatsapp(
          this.conversationId,
          this.messageId,
          this.forwardSelected.map(c => c.id)
        );
        const results = (data && data.payload) || [];
        const failed = results.filter(r => !r.ok);
        if (failed.length) {
          useAlert(failed.map(r => r.error).join(' | '));
        } else {
          useAlert(this.$t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.SUCCESS'));
        }
        this.closeForwardModal();
      } catch (error) {
        useAlert(
          (error && error.response && error.response.data && error.response.data.error) ||
            this.$t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.ERROR')
        );
      } finally {
        this.isSendingForward = false;
      }
    },
    openDeleteModal() {
      this.handleClose();
      this.showDeleteModal = true;
    },
    async confirmDeletion() {
      try {
        await this.$store.dispatch('deleteMessage', {
          conversationId: this.conversationId,
          messageId: this.messageId,
        });
        useAlert(this.$t('CONVERSATION.SUCCESS_DELETE_MESSAGE'));
        this.handleClose();
      } catch (error) {
        useAlert(this.$t('CONVERSATION.FAIL_DELETE_MESSSAGE'));
      }
    },
    closeDeleteModal() {
      this.showDeleteModal = false;
    },
    openReportDialog() {
      this.handleClose();
      this.$refs.reportDialog?.open();
    },
  },
};
</script>

<template>
  <div class="context-menu">
    <!-- Add To Canned Responses -->
    <woot-modal
      v-if="isCannedResponseModalOpen && enabledOptions['cannedResponse']"
      v-model:show="isCannedResponseModalOpen"
      :on-close="hideCannedResponseModal"
    >
      <AddCannedModal
        :response-content="plainTextContent"
        :on-close="hideCannedResponseModal"
      />
    </woot-modal>
    <!-- Metasync: Editar mensagem -->
    <woot-modal
      v-if="showEditModal && enabledOptions['edit']"
      v-model:show="showEditModal"
      :on-close="closeEditModal"
    >
      <div class="flex flex-col gap-4 p-6">
        <h2 class="text-base font-medium text-n-slate-12">
          {{ $t('CONVERSATION.CONTEXT_MENU.EDIT_MESSAGE.TITLE') }}
        </h2>
        <textarea
          v-model="editText"
          rows="5"
          class="w-full p-3 text-sm rounded-lg resize-y bg-n-alpha-black2 text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
          @keydown="onEditKeydown"
        />
        <p class="text-xs text-n-slate-11">
          {{ $t('CONVERSATION.CONTEXT_MENU.EDIT_MESSAGE.HINT') }}
        </p>
        <div class="flex justify-end gap-2">
          <NextButton
            faded
            slate
            sm
            :label="$t('CONVERSATION.CONTEXT_MENU.EDIT_MESSAGE.CANCEL')"
            @click="closeEditModal"
          />
          <NextButton
            sm
            :is-loading="isSavingEdit"
            :disabled="!editText || !editText.trim()"
            :label="$t('CONVERSATION.CONTEXT_MENU.EDIT_MESSAGE.SAVE')"
            @click="saveEdit"
          />
        </div>
      </div>
    </woot-modal>
    <!-- Metasync: Encaminhar mensagem -->
    <woot-modal
      v-if="showForwardModal && enabledOptions['forwardWhatsapp']"
      v-model:show="showForwardModal"
      :on-close="closeForwardModal"
    >
      <div class="flex flex-col gap-3 p-6">
        <h2 class="text-base font-medium text-n-slate-12">
          {{ $t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.TITLE') }}
        </h2>
        <div class="flex gap-1 p-1 rounded-lg bg-n-alpha-black2 w-fit">
          <button
            type="button"
            class="px-3 py-1 text-sm rounded-md"
            :class="
              forwardMode === 'contacts'
                ? 'bg-n-solid-3 text-n-slate-12'
                : 'text-n-slate-11'
            "
            @click="setForwardMode('contacts')"
          >
            {{ $t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.TAB_CONTACTS') }}
          </button>
          <button
            type="button"
            class="px-3 py-1 text-sm rounded-md"
            :class="
              forwardMode === 'company'
                ? 'bg-n-solid-3 text-n-slate-12'
                : 'text-n-slate-11'
            "
            @click="setForwardMode('company')"
          >
            {{ $t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.TAB_COMPANY') }}
          </button>
        </div>
        <input
          v-model="forwardQuery"
          type="text"
          class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-black2 text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
          :placeholder="
            forwardMode === 'company'
              ? $t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.SEARCH_COMPANY')
              : $t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.SEARCH')
          "
          @input="onForwardQueryInput"
        />
        <!-- Aba Empresa -->
        <div
          v-if="forwardMode === 'company'"
          class="flex flex-col overflow-y-auto rounded-lg max-h-64 outline outline-1 outline-n-weak"
        >
          <p v-if="isSearchingForward" class="p-3 text-sm text-n-slate-11">
            {{ $t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.SEARCHING') }}
          </p>
          <p
            v-else-if="!forwardCompanies.length"
            class="p-3 text-sm text-n-slate-11"
          >
            {{ $t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.NO_COMPANY') }}
          </p>
          <template v-else>
            <button
              v-for="company in forwardCompanies"
              :key="'co-' + company.name"
              type="button"
              class="flex items-center justify-between gap-3 px-3 py-2 text-left hover:bg-n-alpha-2"
              :class="{
                'bg-n-alpha-2':
                  forwardCompany && forwardCompany.name === company.name,
              }"
              @click="selectForwardCompany(company)"
            >
              <span class="flex flex-col min-w-0">
                <span class="text-sm truncate text-n-slate-12">
                  {{ company.name }}
                </span>
                <span class="text-xs text-n-slate-11">
                  {{
                    $t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.COMPANY_COUNT', {
                      count: company.contacts_count,
                    })
                  }}
                </span>
              </span>
              <span
                v-if="forwardCompany && forwardCompany.name === company.name"
                class="text-n-brand"
              >
                ✓
              </span>
            </button>
          </template>
        </div>
        <p
          v-if="forwardMode === 'company' && forwardCompany"
          class="text-xs text-n-slate-11"
        >
          {{
            $t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.COMPANY_HINT', {
              count: forwardCompany.contacts_count,
            })
          }}
        </p>
        <!-- Aba Contatos -->
        <div
          v-if="forwardMode === 'contacts' && forwardSelected.length"
          class="flex flex-wrap gap-2"
        >
          <button
            v-for="contact in forwardSelected"
            :key="'sel-' + contact.id"
            type="button"
            class="px-2 py-1 text-xs rounded-full bg-n-brand text-white"
            @click="toggleForwardContact(contact)"
          >
            {{ contact.name }} ✕
          </button>
        </div>
        <div
          v-if="forwardMode === 'contacts'"
          class="flex flex-col overflow-y-auto rounded-lg max-h-64 outline outline-1 outline-n-weak"
        >
          <p
            v-if="isSearchingForward"
            class="p-3 text-sm text-n-slate-11"
          >
            {{ $t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.SEARCHING') }}
          </p>
          <p
            v-else-if="!forwardResults.length"
            class="p-3 text-sm text-n-slate-11"
          >
            {{ $t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.HINT') }}
          </p>
          <template v-else>
          <button
            v-for="contact in forwardResults"
            :key="contact.id"
            type="button"
            class="flex items-center justify-between gap-3 px-3 py-2 text-left hover:bg-n-alpha-2"
            :class="{ 'bg-n-alpha-2': isForwardSelected(contact) }"
            @click="toggleForwardContact(contact)"
          >
            <span class="flex flex-col min-w-0">
              <span class="text-sm truncate text-n-slate-12">
                {{ contact.name }}
              </span>
              <span class="text-xs truncate text-n-slate-11">
                {{ forwardContactLine(contact) }}
              </span>
            </span>
            <span v-if="isForwardSelected(contact)" class="text-n-brand">
              ✓
            </span>
          </button>
          </template>
        </div>
        <div class="flex justify-end gap-2">
          <NextButton
            faded
            slate
            sm
            :label="$t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.CANCEL')"
            @click="closeForwardModal"
          />
          <NextButton
            v-if="forwardMode === 'contacts'"
            sm
            :is-loading="isSendingForward"
            :disabled="!forwardSelected.length"
            :label="
              $t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.SEND', {
                count: forwardSelected.length,
              })
            "
            @click="sendForward"
          />
          <NextButton
            v-else
            sm
            :is-loading="isSendingForward"
            :disabled="!forwardCompany"
            :label="
              $t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.SEND_COMPANY', {
                count: forwardCompany ? forwardCompany.contacts_count : 0,
              })
            "
            @click="sendForwardCompany"
          />
        </div>
      </div>
    </woot-modal>
    <!-- Confirm Deletion -->
    <woot-delete-modal
      v-if="showDeleteModal && enabledOptions['delete']"
      v-model:show="showDeleteModal"
      class="context-menu--delete-modal"
      :on-close="closeDeleteModal"
      :on-confirm="confirmDeletion"
      :title="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.TITLE')"
      :message="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.MESSAGE')"
      :confirm-text="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.DELETE')"
      :reject-text="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.CANCEL')"
    />
    <NextButton
      v-if="!hideButton"
      ghost
      slate
      sm
      icon="i-lucide-ellipsis-vertical"
      class="invisible group-hover/context-menu:visible"
      @click="handleOpen"
    />
    <ContextMenu
      v-if="isOpen && !isCannedResponseModalOpen"
      :x="contextMenuPosition.x"
      :y="contextMenuPosition.y"
      @close="handleClose"
    >
      <div class="menu-container">
        <MenuItem
          v-if="enabledOptions['forwardEmail']"
          :option="{
            icon: 'arrow-forward',
            label: $t('CONVERSATION.CONTEXT_MENU.FORWARD_EMAIL'),
          }"
          variant="icon"
          @click.stop="handleForwardEmail"
        />
        <MenuItem
          v-if="enabledOptions['edit']"
          :option="{
            icon: 'edit',
            label: $t('CONVERSATION.CONTEXT_MENU.EDIT_MESSAGE.LABEL'),
          }"
          variant="icon"
          @click.stop="openEditModal"
        />
        <MenuItem
          v-if="enabledOptions['forwardWhatsapp']"
          :option="{
            icon: 'arrow-forward',
            label: $t('CONVERSATION.CONTEXT_MENU.FORWARD_WHATSAPP.LABEL'),
          }"
          variant="icon"
          @click.stop="openForwardModal"
        />
        <MenuItem
          v-if="enabledOptions['replyTo']"
          :option="{
            icon: 'arrow-reply',
            label: $t('CONVERSATION.CONTEXT_MENU.REPLY_TO'),
          }"
          variant="icon"
          @click.stop="handleReplyTo"
        />
        <MenuItem
          v-if="enabledOptions['copy']"
          :option="{
            icon: 'clipboard',
            label: $t('CONVERSATION.CONTEXT_MENU.COPY'),
          }"
          variant="icon"
          @click.stop="handleCopy"
        />
        <MenuItem
          v-if="enabledOptions['translate']"
          :option="{
            icon: 'translate',
            label: $t('CONVERSATION.CONTEXT_MENU.TRANSLATE'),
          }"
          variant="icon"
          @click.stop="handleTranslate"
        />
        <hr />
        <MenuItem
          v-if="enabledOptions['copyLink']"
          :option="{
            icon: 'link',
            label: $t('CONVERSATION.CONTEXT_MENU.COPY_PERMALINK'),
          }"
          variant="icon"
          @click.stop="copyLinkToMessage"
        />
        <MenuItem
          v-if="enabledOptions['cannedResponse']"
          :option="{
            icon: 'comment-add',
            label: $t('CONVERSATION.CONTEXT_MENU.CREATE_A_CANNED_RESPONSE'),
          }"
          variant="icon"
          @click.stop="showCannedResponseModal"
        />
        <hr v-if="enabledOptions['report']" />
        <MenuItem
          v-if="enabledOptions['report']"
          :option="{
            icon: 'warning',
            label: $t('CONVERSATION.CONTEXT_MENU.REPORT_MESSAGE.LABEL'),
          }"
          variant="icon"
          @click.stop="openReportDialog"
        />
        <hr v-if="enabledOptions['delete']" />
        <MenuItem
          v-if="enabledOptions['delete']"
          :option="{
            icon: 'delete',
            label: $t('CONVERSATION.CONTEXT_MENU.DELETE'),
          }"
          variant="icon"
          @click.stop="openDeleteModal"
        />
      </div>
    </ContextMenu>
    <ReportCaptainMessageDialog
      v-if="enabledOptions['report']"
      ref="reportDialog"
      :message-id="messageId"
    />
  </div>
</template>

<style lang="scss" scoped>
.menu-container {
  @apply p-1 bg-n-background shadow-xl rounded-md;

  hr:first-child {
    @apply hidden;
  }

  hr {
    @apply m-1 border-b border-solid border-n-strong;
  }
}

.context-menu--delete-modal {
  :deep(.modal-container) {
    @apply max-w-[30rem];

    h2 {
      @apply font-medium text-base;
    }
  }
}
</style>
