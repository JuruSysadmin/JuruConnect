# Configurar sincronização automática
# Execute: mix run configurar_sync.exs

defmodule ConfigurarSync do
  @moduledoc """
  Script para configuração de sincronização automática com API de supervisores.

  Este módulo configura um processo em background que coleta dados
  da API em intervalos regulares e os persiste no banco de dados.

  Funcionalidades:
  - Verificação de processos em execução
  - Configuração de intervalo personalizado
  - Teste inicial de conectividade
  - Gerenciamento do processo de sincronização
  - Exibição de comandos úteis

  Execute com: mix run configurar_sync.exs
  """

  alias JuruConnect.Api.SupervisorClient

  @api_url "http://10.1.1.108:8065/api/v1/dashboard/sale/12"
  @default_interval 1800

  def run do
    IO.puts("Configurando sincronização automática...")
    check_and_configure_sync()
    show_useful_commands()
    show_info_message()
  end

  defp check_and_configure_sync do
    case Process.whereis(SupervisorClient) do
      nil ->
        start_new_sync()
      pid ->
        display_already_running_info(pid)
    end
  end

  defp start_new_sync do
    IO.puts("Iniciando sincronização automática...")

    interval = @default_interval

    case SupervisorClient.start_periodic_sync(@api_url, interval) do
      :ok ->
        display_sync_success_info(interval)
        perform_initial_test()

      error ->
        IO.puts("Erro ao configurar: #{inspect(error)}")
    end
  end

  defp display_sync_success_info(interval) do
    IO.puts("Sincronização configurada com sucesso!")
    IO.puts("   URL: #{@api_url}")
    IO.puts("   Intervalo: #{interval} segundos (#{div(interval, 60)} minutos)")
    IO.puts("   PID: #{inspect(Process.whereis(SupervisorClient))}")
  end

  defp perform_initial_test do
    IO.puts("\nExecutando teste inicial...")

    case SupervisorClient.fetch_and_save(@api_url) do
      {:ok, data} ->
        IO.puts("Teste inicial bem-sucedido!")
        IO.puts("   Performance: #{data.percentual_sale}%")
        IO.puts("   Vendedores: #{length(data.sale_supervisor)}")

      {:error, reason} ->
        IO.puts("Erro no teste inicial: #{inspect(reason)}")
        IO.puts("   A sincronização continuará tentando...")
    end
  end

  defp display_already_running_info(pid) do
    IO.puts("Sincronização já está rodando!")
    IO.puts("   PID: #{inspect(pid)}")
    IO.puts("\nPara parar e reconfigurar:")
    IO.puts("   SupervisorClient.stop_periodic_sync()")
    IO.puts("   Depois execute este script novamente")
  end

  defp show_useful_commands do
    IO.puts("\nComandos úteis:")
    IO.puts("   Ver se está rodando:")
    IO.puts("   Process.whereis(JuruConnect.Api.SupervisorClient)")
    IO.puts("")
    IO.puts("   Parar sincronização:")
    IO.puts("   SupervisorClient.stop_periodic_sync()")
    IO.puts("")
    IO.puts("   Ver dados mais recentes:")
    IO.puts("   JuruConnect.Sales.get_latest_supervisor_data()")
    IO.puts("")
    IO.puts("   Monitorar logs:")
    IO.puts("   tail -f log/dev.log")
  end

  defp show_info_message do
    IO.puts("\nA sincronização roda em background e coleta dados automaticamente.")
    IO.puts("Os dados ficam salvos no PostgreSQL para consulta e análise.")
  end
end

ConfigurarSync.run()
