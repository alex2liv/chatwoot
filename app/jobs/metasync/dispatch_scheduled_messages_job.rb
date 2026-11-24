# Metasync: roda a cada minuto e envia as mensagens agendadas que ja chegaram no horario.
class Metasync::DispatchScheduledMessagesJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    MetasyncScheduledMessage.due.order(:scheduled_at).limit(200).each(&:deliver!)
  end
end
