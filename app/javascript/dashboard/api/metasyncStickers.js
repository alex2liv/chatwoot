/* global axios */
// Metasync: figurinhas salvas (pessoais e da empresa)
import ApiClient from './ApiClient';

class MetasyncStickersApi extends ApiClient {
  constructor() {
    super('metasync_stickers', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  saveFromAttachment(attachmentId, scope = 'mine') {
    return axios.post(this.url, { attachment_id: attachmentId, scope });
  }

  remove(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  send(conversationId, stickerId) {
    const base = this.url.replace(/metasync_stickers$/, 'conversations');
    return axios.post(`${base}/${conversationId}/stickers`, {
      sticker_id: stickerId,
    });
  }
}

export default new MetasyncStickersApi();
