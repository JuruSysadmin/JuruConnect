defmodule App.Repo.Migrations.AddAudioFieldsToMessages do
  @moduledoc """
  Adiciona campos para suporte a áudio nas mensagens do chat
  """

  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :audio_url, :text
      add :audio_duration, :integer
      add :audio_mime_type, :string
    end

    create index(:messages, [:tipo])
    create index(:messages, [:audio_url])
  end
end
