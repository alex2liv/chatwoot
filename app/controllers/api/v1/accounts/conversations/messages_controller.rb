class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_api_inbox, only: :update

  def index
    @messages = message_finder.perform
  end

  def create
    user = Current.user || @resource
    mb = Messages::MessageBuilder.new(user, @conversation, params)
    @message = mb.perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def update
    Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    @message = message
  end

  def destroy
    ActiveRecord::Base.transaction do
      # keeps the forward marker so replies to a deleted forward stay out of this conversation
      message.update!(content: I18n.t('conversations.messages.deleted'), content_type: :text,
                      content_attributes: message.content_attributes.slice('forwarded_message_id').merge(deleted: true))
      message.attachments.destroy_all
    end
  end

  # Metasync: edita o texto de uma mensagem enviada pelo agente.
  # Marca content_attributes.whatsapp_edit_pending para o n8n repassar a edicao ao WhatsApp
  # (Evolution GO /message/edit). O WhatsApp so aceita edicao ate 15 minutos apos o envio.
  WHATSAPP_EDIT_WINDOW = 15.minutes

  def edit_content
    new_content = params[:content].to_s.strip
    error = edit_content_error(new_content)
    return render json: { error: error }, status: :unprocessable_entity if error

    attrs = (message.content_attributes || {}).to_h.stringify_keys
    attrs['edited'] = true
    attrs['edited_at'] = Time.current.to_i
    attrs['previous_content'] = message.content
    attrs['whatsapp_edit_pending'] = true
    message.update!(content: new_content, content_attributes: attrs)
    render json: message.push_event_data
  end

  # Metasync: encaminha a mensagem (texto e/ou anexos) para ate 5 contatos.
  # Cria uma mensagem de saida na conversa de cada contato (mesma inbox); o fluxo
  # de saida do n8n entrega no WhatsApp como qualquer mensagem do agente.
  MAX_FORWARD_CONTACTS = 5

  def forward_whatsapp
    error = forward_error
    return render json: { error: error }, status: :unprocessable_entity if error

    results = forward_contact_ids.map { |contact_id| forward_to_contact(contact_id) }
    ok = results.select { |r| r[:ok] }
    return render json: { error: results.map { |r| r[:error] }.compact.join(' | '), payload: results }, status: :unprocessable_entity if ok.empty?

    render json: { payload: results }
  end

  def retry
    return if message.blank?

    ::SendReplyJob.perform_later(message.id) if claim_message_retry
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def translate
    return head :ok if already_translated_content_available?

    translated_content = translate_message

    if translated_content.present?
      translations = {}
      translations[permitted_params[:target_language]] = translated_content
      translations = message.translations.merge!(translations) if message.translations.present?
      message.update!(translations: translations, translation_provider: translation_provider)
    end

    render json: { content: translated_content }
  rescue Google::Cloud::Error => e
    # `details` carries the clean human message; `message` includes gRPC debug noise
    render_could_not_create_error(e.details.presence || e.message)
  end

  private

  def translation_provider
    'google_translate'
  end

  def translate_message
    hook = Current.account.hooks.find_by(app_id: 'google_translate')
    Integrations::GoogleTranslate::ProcessorService.new(hook: hook).translate_message(message, permitted_params[:target_language]) if hook
  end

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def claim_message_retry
    message.with_lock do
      next false unless message.failed?

      Messages::StatusUpdateService.new(message, 'sent').perform
      clear_source_id unless @conversation.inbox.api? || @conversation.inbox.web_widget?
      true
    end
  end

  def forward_contact_ids
    Array(params[:contact_ids]).map(&:to_i).select(&:positive?).uniq.first(MAX_FORWARD_CONTACTS)
  end

  def forward_error
    return 'Escolha pelo menos um contato' if forward_contact_ids.empty?
    return 'Só é possível encaminhar em canais WhatsApp (API)' unless @conversation.inbox.api?
    return 'Mensagem privada não pode ser encaminhada' if message.private?
    return 'Mensagem apagada não pode ser encaminhada' if message.content_attributes[:deleted]
    return 'Mensagem vazia' if message.content.blank? && message.attachments.empty?

    nil
  end

  def forward_to_contact(contact_id)
    contact = Current.account.contacts.find_by(id: contact_id)
    return { contact_id: contact_id, ok: false, error: "Contato #{contact_id} não encontrado" } unless contact

    conversation = forward_target_conversation(contact, @conversation.inbox)
    forwarded = build_forwarded_message(conversation)
    { contact_id: contact.id, ok: true, conversation_id: conversation.display_id, message_id: forwarded.id }
  rescue StandardError => e
    Rails.logger.error("[forward_whatsapp] contato #{contact_id}: #{e.class} #{e.message}")
    { contact_id: contact_id, ok: false, error: "#{contact&.name || contact_id}: #{e.message}" }
  end

  # Mesma regra do fluxo de entrada do n8n: usa o contact_inbox e a conversa mais
  # recente desse contato nessa inbox; reabre se estiver resolvida/pendente.
  def forward_target_conversation(contact, inbox)
    contact_inbox = ContactInbox.where(inbox_id: inbox.id, contact_id: contact.id).order(:id).first
    contact_inbox ||= ContactInbox.create!(contact: contact, inbox: inbox, source_id: forward_source_id(contact))

    conversation = Conversation.where(account_id: inbox.account_id, inbox_id: inbox.id, contact_id: contact.id)
                               .order(id: :desc).first
    if conversation
      conversation.update!(status: :open) if conversation.resolved? || conversation.pending?
      return conversation
    end

    Conversation.create!(account_id: inbox.account_id, inbox_id: inbox.id, contact_id: contact.id,
                         contact_inbox_id: contact_inbox.id, status: :open)
  end

  def forward_source_id(contact)
    return contact.identifier if contact.identifier.present?

    digits = contact.phone_number.to_s.gsub(/\D/, '')
    raise StandardError, 'contato sem telefone' if digits.blank?

    "#{digits}@s.whatsapp.net"
  end

  def build_forwarded_message(conversation)
    forwarded = conversation.messages.new(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      sender: Current.user,
      content: message.content,
      content_attributes: { 'whatsapp_forwarded_from' => message.id }
    )
    message.attachments.each do |att|
      copy = forwarded.attachments.new(
        account_id: conversation.account_id, file_type: att.file_type, external_url: att.external_url,
        fallback_title: att.fallback_title, coordinates_lat: att.coordinates_lat,
        coordinates_long: att.coordinates_long, meta: att.meta
      )
      copy.file = att.file.blob if att.file.attached?
    end
    forwarded.save!
    forwarded
  end

  def edit_content_error(new_content)
    return 'Mensagem vazia' if new_content.blank?
    return 'Texto igual ao atual' if new_content == message.content
    return 'Só é possível editar mensagens enviadas por você' unless message.outgoing? && !message.private?
    return 'Só é possível editar em canais WhatsApp (API)' unless @conversation.inbox.api?
    return 'Não é possível editar mensagens com anexo' if message.attachments.any?
    return 'O WhatsApp ainda não confirmou essa mensagem. Aguarde alguns segundos e tente de novo' if message.source_id.blank?
    return 'O WhatsApp só permite editar até 15 minutos após o envio' if message.created_at < WHATSAPP_EDIT_WINDOW.ago

    nil
  end

  def clear_source_id
    Rails.logger.info "Cleared older source ID #{message.source_id} for message #{message.id}" if message.source_id.present?
    message.update!(source_id: nil)
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error, :content)
  end

  def already_translated_content_available?
    message.translations.present? && message.translations[permitted_params[:target_language]].present?
  end

  # API inbox check
  def ensure_api_inbox
    # Only API inboxes can update messages
    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden unless @conversation.inbox.api?
  end
end

Api::V1::Accounts::Conversations::MessagesController.prepend_mod_with('Api::V1::Accounts::Conversations::MessagesController')
