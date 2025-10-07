defmodule AppWeb.AdminDashboardLive do
  use AppWeb, :live_view

  alias App.Treaties
  alias App.Accounts

  @impl true
  def mount(_params, session, socket) do
    # Verificar se o usuário é administrador
    case get_user_from_session(session) do
      nil ->
        {:ok,
          socket
          |> put_flash(:error, "Você precisa estar logado para acessar o dashboard.")
          |> redirect(to: ~p"/")}

      user ->
        if Accounts.admin?(user) do
          {:ok,
            socket
            |> assign(:user, user)
            |> assign(:loading, true)
            |> load_dashboard_data()}
        else
          {:ok,
            socket
            |> put_flash(:error, "Acesso negado. Apenas administradores podem acessar o dashboard.")
            |> redirect(to: ~p"/")}
        end
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  @impl true
  def handle_info(:refresh_data, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  # Funções auxiliares

  defp get_user_from_session(session) do
    case session["user_token"] do
      nil -> nil
      token ->
        case AppWeb.Auth.Guardian.resource_from_token(token) do
          {:ok, user, _claims} -> user
          {:error, _reason} -> nil
        end
    end
  end

  defp load_dashboard_data(socket) do
    stats = Treaties.get_admin_dashboard_stats()

    socket
    |> assign(:loading, false)
    |> assign(:stats, stats)
  end

  defp format_reason("resolved"), do: "Resolvido"
  defp format_reason("cancelled"), do: "Cancelado"
  defp format_reason("duplicate"), do: "Duplicado"
  defp format_reason("invalid"), do: "Inválido"
  defp format_reason("other"), do: "Outro"
  defp format_reason(reason), do: reason

  defp format_status("active"), do: "Ativo"
  defp format_status("closed"), do: "Encerrado"
  defp format_status("cancelled"), do: "Cancelado"
  defp format_status("completed"), do: "Concluído"
  defp format_status("inactive"), do: "Inativo"
  defp format_status(status), do: status

  defp format_activity_type("created"), do: "Criada"
  defp format_activity_type("closed"), do: "Encerrada"
  defp format_activity_type("reopened"), do: "Reaberta"
  defp format_activity_type("rated"), do: "Avaliada"
  defp format_activity_type("message_sent"), do: "Mensagem enviada"
  defp format_activity_type(type), do: type
end
