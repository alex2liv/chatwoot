# Metasync: figurinha salva para enviar pelo botao de figurinhas da caixa de resposta.
# user_id preenchido = figurinha pessoal do atendente; user_id nulo = pacote da empresa.
class MetasyncSticker < ApplicationRecord
  include Rails.application.routes.url_helpers

  LIMITE_USUARIO = 30
  LIMITE_EMPRESA = 30
  TAMANHO_MAXIMO = 1.megabyte
  LADO = 512

  belongs_to :account
  belongs_to :user, optional: true
  has_one_attached :file

  scope :da_empresa, -> { where(user_id: nil) }

  def as_json(*)
    { id: id, url: file.attached? ? url_for(file) : '', company: user_id.nil?, created_at: created_at.to_i }
  end

  # Cria a figurinha a partir de um anexo de mensagem (imagem). Converte para WebP 512px quando nao for WebP.
  def self.criar_de_anexo!(account:, user:, attachment:, empresa: false)
    raise ArgumentError, 'Só dá para salvar imagens como figurinha.' unless attachment.file.attached? && attachment.file.content_type.to_s.start_with?('image/')
    raise ArgumentError, 'Essa imagem é maior que 1 MB.' if attachment.file.byte_size.to_i > TAMANHO_MAXIMO

    dono = empresa ? nil : user
    total = account_scope(account, dono).count
    limite = empresa ? LIMITE_EMPRESA : LIMITE_USUARIO
    if total >= limite
      raise ArgumentError, empresa ? "A empresa atingiu o limite de #{limite} figurinhas. Remova alguma para salvar uma nova." : "Você atingiu o limite de #{limite} figurinhas. Remova alguma para salvar uma nova."
    end

    io, nome, tipo = preparar_arquivo(attachment)
    sticker = create!(account: account, user: dono)
    sticker.file.attach(io: io, filename: nome, content_type: tipo)
    sticker
  end

  def self.account_scope(account, dono)
    where(account_id: account.id, user_id: dono&.id)
  end

  def self.preparar_arquivo(attachment)
    dados = attachment.file.download
    base = File.basename(attachment.file.filename.to_s, '.*').presence || 'figurinha'
    return [StringIO.new(dados), "#{base}.webp", 'image/webp'] if attachment.file.content_type == 'image/webp'

    begin
      require 'image_processing/vips'
      Tempfile.create(['figurinha', File.extname(attachment.file.filename.to_s)], binmode: true) do |entrada|
        entrada.write(dados)
        entrada.flush
        saida = ImageProcessing::Vips.source(entrada.path).resize_to_fit(LADO, LADO).convert('webp').call
        return [StringIO.new(File.binread(saida.path)), "#{base}.webp", 'image/webp']
      end
    rescue StandardError => e
      Rails.logger.warn("[metasync_sticker] conversao para webp falhou: #{e.message}")
      [StringIO.new(dados), attachment.file.filename.to_s, attachment.file.content_type]
    end
  end
end
