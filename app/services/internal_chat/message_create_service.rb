class InternalChat::MessageCreateService
  include Events::Types

  def initialize(channel:, sender:, params:)
    @channel = channel
    @sender = sender
    @params = params
  end

  def perform
    message = build_message
    message.save!
    update_channel_activity
    dispatch_message_event(message)
    message
  end

  private

  def build_message
    @channel.messages.build(
      content: @params[:content],
      content_type: @params[:content_type] || 'text',
      sender: @sender,
      account_id: @channel.account_id,
      parent_id: @params[:parent_id],
      echo_id: @params[:echo_id],
      content_attributes: build_content_attributes
    )
  end

  def build_content_attributes
    attrs = {}
    attrs['also_send_in_channel'] = @params[:also_send_in_channel] if @params[:also_send_in_channel].present?
    attrs
  end

  def update_channel_activity
    @channel.update_columns(last_activity_at: Time.current, messages_count: @channel.messages_count + 1)
  end

  def dispatch_message_event(message)
    Rails.configuration.dispatcher.dispatch(
      INTERNAL_CHAT_MESSAGE_CREATED,
      Time.zone.now,
      message: message
    )
  end
end
