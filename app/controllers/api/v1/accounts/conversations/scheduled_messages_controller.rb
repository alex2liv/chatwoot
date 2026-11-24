# Metasync: agendar mensagens numa conversa (criar, listar, reagendar, cancelar, enviar agora).
class Api::V1::Accounts::Conversations::ScheduledMessagesController < Api::V1::Accounts::Conversations::BaseController
  before_action :scheduled_message, only: [:update, :destroy, :send_now]

  def index
    list = MetasyncScheduledMessage.where(conversation_id: @conversation.id)
                                   .where('status = ? OR updated_at > ?', MetasyncScheduledMessage.statuses[:pending], 1.day.ago)
                                   .where.not(status: :cancelled).order(:scheduled_at)
    render json: { payload: list.as_json }
  end

  def create
    record = MetasyncScheduledMessage.create!(
      account: Current.account, conversation: @conversation, user: Current.user,
      content: params[:content].to_s, scheduled_at: parsed_time
    )
    render json: record.as_json
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    return render json: { error: 'Mensagem ja enviada' }, status: :unprocessable_entity unless @scheduled_message.pending?

    attrs = {}
    attrs[:content] = params[:content].to_s if params[:content].present?
    attrs[:scheduled_at] = parsed_time if params[:scheduled_at].present?
    @scheduled_message.update!(attrs)
    render json: @scheduled_message.as_json
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def destroy
    @scheduled_message.update!(status: :cancelled) if @scheduled_message.pending?
    head :ok
  end

  def send_now
    @scheduled_message.deliver!
    render json: @scheduled_message.reload.as_json
  end

  private

  def scheduled_message
    @scheduled_message = MetasyncScheduledMessage.find_by!(id: params[:id], conversation_id: @conversation.id)
  end

  def parsed_time
    value = params[:scheduled_at]
    value.to_s =~ /\A\d+\z/ ? Time.zone.at(value.to_i) : Time.zone.parse(value.to_s)
  end
end
