# Script para atualizar URLs das imagens no banco de dados
# Execute com: mix run scripts/update_image_urls.exs

import Ecto.Query
alias App.Repo
alias App.Chat.MessageAttachment

# Buscar todos os anexos com URLs antigas
attachments = from(ma in MessageAttachment,
  where: like(ma.file_url, "%localhost:9000%")
) |> Repo.all()

# Atualizar cada anexo
Enum.each(attachments, fn attachment ->
  new_url = String.replace(attachment.file_url, "localhost:9000", "10.1.1.168:9000")

  attachment
  |> Ecto.Changeset.change(file_url: new_url)
  |> Repo.update()
end)
