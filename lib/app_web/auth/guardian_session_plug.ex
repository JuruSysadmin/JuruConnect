defmodule AppWeb.Auth.GuardianSessionPlug do
  @moduledoc """
  Plug personalizado para limpar tokens malformados da sessão antes que o Guardian os processe.

  Este plug previne o erro `Plug.Conn.NotSentError` que ocorre quando o Guardian
  tenta processar tokens malformados ou inválidos armazenados na sessão.
  """

  import Plug.Conn
  require Logger

  def init(opts), do: opts

      def call(conn, _opts) do
    case get_session(conn, "guardian_default_token") do
      nil ->
        conn
      token when is_binary(token) ->
        if valid_jwt_format?(token) do
          # Token tem formato válido, deixar o Guardian processar
          # O GuardianErrorHandler cuidará de tokens inválidos
          conn
        else
          Logger.debug("Clearing malformed token from session: #{String.slice(token, 0, 20)}...")
          conn
          |> delete_session("guardian_default_token")
          |> assign(:current_user, nil)
        end
      _ ->
        # Token não é uma string - limpar
        conn
        |> delete_session("guardian_default_token")
        |> assign(:current_user, nil)
    end
  end

  defp valid_jwt_format?(token) when is_binary(token) do
    # Verificação básica de formato JWT (deve ter 3 partes separadas por '.')
    parts = String.split(token, ".")

    with true <- length(parts) == 3,
         true <- Enum.all?(parts, &(byte_size(&1) > 0)),
         true <- valid_base64_parts?(parts) do
      true
    else
      _ -> false
    end
  end

  defp valid_base64_parts?([header, payload, _signature]) do
    # Verificar se header e payload são base64 válidos (não verificamos assinatura aqui)
    valid_base64_url?(header) and valid_base64_url?(payload)
  end

  defp valid_base64_url?(string) do
    # Verificar se é uma string base64url válida (caracteres válidos para JWT)
    # Deve ter pelo menos 4 caracteres e ser válido base64url
    with true <- String.length(string) >= 4,
         true <- Regex.match?(~r/^[A-Za-z0-9_-]+$/, string),
         true <- valid_base64_content?(string) do
      true
    else
      _ -> false
    end
  end

  defp valid_base64_content?(string) do
    # Tenta decodificar o base64url para verificar se é válido
    try do
      # Adiciona padding se necessário para base64 padrão
      padded = string |> String.replace("-", "+") |> String.replace("_", "/")
      padding_needed = rem(4 - rem(String.length(padded), 4), 4)
      padded_string = padded <> String.duplicate("=", padding_needed)

      case Base.decode64(padded_string) do
        {:ok, _} -> true
        _ -> false
      end
    rescue
      _ -> false
    end
  end

  defp valid_jwt_format?(_), do: false
end
