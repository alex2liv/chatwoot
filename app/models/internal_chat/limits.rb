class InternalChat::Limits
  def self.unlimited?
    true
  end

  def self.polls_enabled?
    true
  end

  def self.max_private_channels
    nil
  end

  def self.search_history_days
    nil
  end
end
