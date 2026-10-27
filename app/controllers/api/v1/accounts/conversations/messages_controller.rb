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

  # Metasync: encaminha a mensagem (texto e/ou anexos) para ate 5 contatos
  # (na hora) ou para todos os contatos de uma empresa (em fila, com intervalo).
  MAX_FORWARD_CONTACTS = 5
  MAX_FORWARD_COMPANY_CONTACTS = 30
  FORWARD_COMPANY_INTERVAL = 4.seconds
  COMPANY_NAME_SQL = "btrim(contacts.additional_attributes->>'company_name')".freeze

  def forward_whatsapp
    return forward_to_company if params[:company_name].present?

    error = forward_error || ('Escolha pelo menos um contato' if forward_contact_ids.empty?)
    return render json: { error: error }, status: :unprocessable_entity if error

    results = forward_contact_ids.map { |contact_id| forward_to_contact(contact_id) }
    ok = results.select { |r| r[:ok] }
    return render json: { error: results.map { |r| r[:error] }.compact.join(' | '), payload: results }, status: :unprocessable_entity if ok.empty?

    render json: { payload: results }
  end

  def forward_companies
    scope = forward_reachable_contacts.where("COALESCE(#{COMPANY_NAME_SQL}, '') <> ''")
    query = params[:q].to_s.strip
    if query.present?
      scope = scope.where("#{COMPANY_NAME_SQL} ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
    end
    rows = scope.group(Arel.sql("lower(#{COMPANY_NAME_SQL})"))
                .order(Arel.sql('count(*) DESC'))
                .limit(20)
                .pluck(Arel.sql("min(#{COMPANY_NAME_SQL})"), Arel.sql('count(*)'))
    render json: { payload: rows.map { |name, count| { name: name, contacts_count: count } } }
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
    return 'Só é possível encaminhar em canais WhatsApp (API)' unless @conversation.inbox.api?
    return 'Mensagem privada não pode ser encaminhada' if message.private?
    return 'Mensagem apagada não pode ser encaminhada' if message.content_attributes[:deleted]
    return 'Mensagem vazia' if message.content.blank? && message.attachments.empty?

    nil
  end

  def forward_reachable_contacts
    Current.account.contacts.where("COALESCE(contacts.phone_number, '') <> '' OR COALESCE(contacts.identifier, '') <> ''")
  end

  def forward_to_company
    error = forward_error
    return render json: { error: error }, status: :unprocessable_entity if error

    name = params[:company_name].to_s.strip
    contact_ids = forward_reachable_contacts
                  .where("lower(#{COMPANY_NAME_SQL}) = lower(?)", name)
                  .order(:id).limit(MAX_FORWARD_COMPANY_CONTACTS + 1).pluck(:id)
    return render json: { error: "Nenhum contato com telefone na empresa #{name}" }, status: :unprocessable_entity if contact_ids.empty?
    if contact_ids.size > MAX_FORWARD_COMPANY_CONTACTS
      return render json: { error: "A empresa #{name} tem mais de #{MAX_FORWARD_COMPANY_CONTACTS} contatos. Use o Campaign Manager." },
                    status: :unprocessable_entity
    end

    contact_ids.each_with_index do |contact_id, index|
      Metasync::ForwardMessageJob.set(wait: index * FORWARD_COMPANY_INTERVAL)
                                 .perform_later(message.id, contact_id, Current.user&.id)
    end
    render json: { payload: { company: name, queued: contact_ids.size } }
  end

  def forward_to_contact(contact_id)
    contact = Current.account.contacts.find_by(id: contact_id)
    return { contact_id: contact_id, ok: false, error: "Contato #{contact_id} não encontrado" } unless contact

    forwarded = Metasync::ForwardMessageService.new(message: message, inbox: @conversation.inbox, user: Current.user)
                                               .perform(contact)
    { contact_id: contact.id, ok: true, conversation_id: forwarded.conversation.display_id, message_id: forwarded.id }
  rescue StandardError => e
    Rails.logger.error("[forward_whatsapp] contato #{contact_id}: #{e.class} #{e.message}")
    { contact_id: contact_id, ok: false, error: "#{contact&.name || contact_id}: #{e.message}" }
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
    params.permit(:id, :target_language, :status, :external_error, :content, :company_name, :q)
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
