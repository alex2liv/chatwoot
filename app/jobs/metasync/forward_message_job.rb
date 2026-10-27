# Metasync: encaminhamento para uma empresa inteira. Cada contato vira um job
# agendado com alguns segundos de intervalo, pra nao disparar tudo de uma vez
# no WhatsApp (risco de bloqueio do numero).
class Metasync::ForwardMessageJob < ApplicationJob
  queue_as :medium

  def perform(message_id, contact_id, user_id)
    message = Message.find_by(id: message_id)
    return unless message

    contact = message.account.contacts.find_by(id: contact_id)
    return unless contact

    user = User.find_by(id: user_id)
    Metasync::ForwardMessageService.new(message: message, inbox: message.inbox, user: user).perform(contact)
  rescue StandardError => e
    Rails.logger.error("[Metasync::ForwardMessageJob] msg #{message_id} contato #{contact_id}: #{e.class} #{e.message}")
  end
end
