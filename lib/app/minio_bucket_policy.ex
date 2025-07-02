defmodule App.MinioBucketPolicy do
  @moduledoc """
  Gerenciamento de políticas de acesso para buckets do MinIO.
  """

  require Logger

  @bucket "chat-uploads"

  @doc """
  Configura o bucket para permitir acesso público de leitura.
  """
  def set_public_read_policy do
    Logger.info("Configurando política pública de leitura para o bucket: #{@bucket}")

    policy = build_public_read_policy()

    case ExAws.S3.put_bucket_policy(@bucket, policy) |> ExAws.request() do
      {:ok, _} ->
        Logger.info("Política pública configurada com sucesso")
        {:ok, :configured}

      {:error, reason} ->
        Logger.error("Falha ao configurar política: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Constrói a política JSON para acesso público de leitura.
  """
  def build_public_read_policy do
    %{
      "Version" => "2012-10-17",
      "Statement" => [
        %{
          "Effect" => "Allow",
          "Principal" => "*",
          "Action" => "s3:GetObject",
          "Resource" => "arn:aws:s3:::#{@bucket}/*"
        }
      ]
    }
    |> Jason.encode!()
  end

  @doc """
  Remove todas as políticas do bucket.
  """
  def remove_bucket_policy do
    Logger.info("Removendo políticas do bucket: #{@bucket}")

    case ExAws.S3.delete_bucket_policy(@bucket) |> ExAws.request() do
      {:ok, _} ->
        Logger.info("Políticas removidas com sucesso")
        {:ok, :removed}

      {:error, reason} ->
        Logger.error("Falha ao remover políticas: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Verifica as políticas atuais do bucket.
  """
  def get_bucket_policy do
    Logger.info("Verificando políticas do bucket: #{@bucket}")

    case ExAws.S3.get_bucket_policy(@bucket) |> ExAws.request() do
      {:ok, %{body: policy}} ->
        Logger.info("Política encontrada")
        {:ok, policy}

      {:error, reason} ->
        Logger.warning("Nenhuma política encontrada: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
