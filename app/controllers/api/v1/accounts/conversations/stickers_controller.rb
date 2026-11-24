# Metasync: envia uma figurinha salva na conversa (como figurinha de WhatsApp).
class Api::V1::Accounts::Conversations::StickersController < Api::V1::Accounts::Conversations::BaseController
  def create
    sticker = MetasyncSticker.where(account_id: Current.account.id)
                             .where('user_id IS NULL OR user_id = ?', Current.user.id)
                             .find(params[:sticker_id])
    # Copia o arquivo: se a mensagem for apagada depois, a figurinha salva continua existindo.
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(sticker.file.download),
      filename: sticker.file.filename.to_s,
      content_type: sticker.file.content_type
    )
    message = Messages::MessageBuilder.new(
      Current.user, @conversation,
      { message_type: 'outgoing', private: false, content_attributes: { is_sticker: true }, attachments: [blob.signed_id] }
    ).perform
    render json: { id: message.id }
  end
end
