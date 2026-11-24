# Metasync: mensagem preparada agora e enviada automaticamente no horario escolhido.
class MetasyncScheduledMessage < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :user, optional: true

  enum :status, { pending: 0, sent: 1, cancelled: 2, failed: 3 }

  validates :content, presence: true, length: { maximum: 150_000 }
  validates :scheduled_at, presence: true
  validate :scheduled_in_future, on: :create

  scope :due, -> { pending.where('scheduled_at <= ?', Time.current) }

  def as_json(*)
    {
      id: id, content: content, scheduled_at: scheduled_at.to_i, status: status,
      message_id: message_id, error_message: error_message,
      user: user && { id: user.id, name: user.available_name || user.name }
    }
  end

  # Envia como se o agente tivesse apertado "Enviar" no horario.
  def deliver!
    with_lock do
      return unless pending?

      message = Messages::MessageBuilder.new(user, conversation,
                                             { content: content, message_type: 'outgoing', private: false }).perform
      update!(status: :sent, message_id: message.id, error_message: nil)
    end
  rescue StandardError => e
    update_columns(status: self.class.statuses[:failed], error_message: e.message.to_s.first(500), updated_at: Time.current)
  end

  private

  def scheduled_in_future
    errors.add(:scheduled_at, 'precisa ser no futuro') if scheduled_at.present? && scheduled_at < 1.minute.ago
  end
end
