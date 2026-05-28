class InternalChat::TypingStatusManager
  TYPING_TIMEOUT = 30.seconds

  def initialize(channel:, user:, params:)
    @channel = channel
    @user = user
    @params = params
  end

  def perform
    if @params[:typing_status] == 'on'
      set_typing
    else
      remove_typing
    end
  end

  private

  def redis_key
    "internal_chat:typing:#{@channel.id}"
  end

  def set_typing
    Redis::Alfred.setex(redis_key, TYPING_TIMEOUT.to_i, @user.id)
  end

  def remove_typing
    Redis::Alfred.delete(redis_key)
  end
end
