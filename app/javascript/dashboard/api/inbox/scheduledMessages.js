/* global axios */
// Metasync: mensagens agendadas por conversa
import ApiClient from '../ApiClient';

class ScheduledMessagesApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  list(conversationId) {
    return axios.get(`${this.url}/${conversationId}/scheduled_messages`);
  }

  create(conversationId, { content, scheduledAt }) {
    return axios.post(`${this.url}/${conversationId}/scheduled_messages`, {
      content,
      scheduled_at: Math.floor(scheduledAt / 1000),
    });
  }

  update(conversationId, id, { content, scheduledAt }) {
    const payload = {};
    if (content !== undefined) payload.content = content;
    if (scheduledAt) payload.scheduled_at = Math.floor(scheduledAt / 1000);
    return axios.patch(
      `${this.url}/${conversationId}/scheduled_messages/${id}`,
      payload
    );
  }

  cancel(conversationId, id) {
    return axios.delete(
      `${this.url}/${conversationId}/scheduled_messages/${id}`
    );
  }

  sendNow(conversationId, id) {
    return axios.post(
      `${this.url}/${conversationId}/scheduled_messages/${id}/send_now`
    );
  }
}

export default new ScheduledMessagesApi();
