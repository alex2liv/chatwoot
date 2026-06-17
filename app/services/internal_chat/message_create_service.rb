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
    attach_files(message)
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
      skip_content_validation: @params[:attachments].present?,
      content_attributes: build_content_attributes
    )
  end

  def build_content_attributes
    attrs = {}
    attrs['also_send_in_channel'] = @params[:also_send_in_channel] if @params[:also_send_in_channel].present?
    attrs
  end

  def attach_files(message)
    return unless @params[:attachments].present?

    Array(@params[:attachments]).each do |attachment_params|
      next unless attachment_params[:file].present?

      attachment = message.attachments.build(
        account_id: @channel.account_id,
        file_type: attachment_params[:file_type] || detect_file_type(attachment_params[:file])
      )
      attachment.file.attach(attachment_params[:file])
      attachment.save!
    end
  end

  def detect_file_type(file)
    content_type = file.content_type.to_s
    if content_type.start_with?('image/')
      'image'
    elsif content_type.start_with?('video/')
      'video'
    elsif content_type.start_with?('audio/') || content_type.include?('webm') || content_type.include?('ogg') || content_type.include?('mp3') || content_type.include?('wav') || content_type.include?('m4a')
      'audio'
    else
      'file'
    end
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
