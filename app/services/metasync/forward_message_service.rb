# Metasync: encaminha uma mensagem (texto e/ou anexos) para um contato.
# Cria uma mensagem de saida na conversa do contato (mesma inbox); o fluxo de
# saida do n8n entrega no WhatsApp como qualquer mensagem do agente.
# Mesma regra do fluxo de entrada do n8n: usa o contact_inbox e a conversa mais
# recente desse contato nessa inbox; reabre se estiver resolvida/pendente.
class Metasync::ForwardMessageService
  def initialize(message:, inbox:, user:)
    @message = message
    @inbox = inbox
    @user = user
  end

  def perform(contact)
    conversation = target_conversation(contact)
    build_forwarded_message(conversation)
  end

  private

  def target_conversation(contact)
    contact_inbox = ContactInbox.where(inbox_id: @inbox.id, contact_id: contact.id).order(:id).first
    contact_inbox ||= ContactInbox.create!(contact: contact, inbox: @inbox, source_id: source_id_for(contact))

    conversation = Conversation.where(account_id: @inbox.account_id, inbox_id: @inbox.id, contact_id: contact.id)
                               .order(id: :desc).first
    if conversation
      conversation.update!(status: :open) if conversation.resolved? || conversation.pending?
      return conversation
    end

    Conversation.create!(account_id: @inbox.account_id, inbox_id: @inbox.id, contact_id: contact.id,
                         contact_inbox_id: contact_inbox.id, status: :open)
  end

  def source_id_for(contact)
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
      sender: @user,
      content: @message.content,
      content_attributes: { 'whatsapp_forwarded_from' => @message.id }
    )
    @message.attachments.each do |att|
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
end
