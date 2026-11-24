# Metasync: figurinhas salvas (listar, salvar a partir de um anexo, remover).
class Api::V1::Accounts::MetasyncStickersController < Api::V1::Accounts::BaseController
  def index
    mine = MetasyncSticker.where(account_id: Current.account.id, user_id: Current.user.id).order(:created_at)
    company = MetasyncSticker.where(account_id: Current.account.id).da_empresa.order(:created_at)
    render json: {
      mine: mine.map(&:as_json), company: company.map(&:as_json),
      limits: { mine: MetasyncSticker::LIMITE_USUARIO, company: MetasyncSticker::LIMITE_EMPRESA },
      can_manage_company: admin?
    }
  end

  def create
    empresa = params[:scope].to_s == 'company'
    return render json: { error: 'Só administradores salvam figurinhas da empresa.' }, status: :forbidden if empresa && !admin?

    attachment = Attachment.find_by!(id: params[:attachment_id], account_id: Current.account.id)
    sticker = MetasyncSticker.criar_de_anexo!(account: Current.account, user: Current.user, attachment: attachment, empresa: empresa)
    render json: sticker.as_json
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    sticker = MetasyncSticker.find_by!(id: params[:id], account_id: Current.account.id)
    permitido = sticker.user_id == Current.user.id || (sticker.user_id.nil? && admin?)
    return render json: { error: 'Você não pode remover essa figurinha.' }, status: :forbidden unless permitido

    sticker.file.purge_later
    sticker.destroy!
    head :ok
  end

  private

  def admin?
    Current.account_user&.administrator?
  end
end
