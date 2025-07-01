defmodule App.Email do
  @moduledoc """
  Templates de e-mail para o sistema JuruConnect.

  Fornece templates padronizados e seguros para notificações
  de segurança, recuperação de senha e outras comunicações.
  """

  import Swoosh.Email

  @from_email "noreply@jurunense.com"
  @from_name "JuruConnect - Jurunense Home Center"

  def password_reset_email(user, to_email, reset_url, token) do
    new()
    |> to({user.name || user.username, to_email})
    |> from({@from_name, @from_email})
    |> subject(" Redefinição de Senha - JuruConnect")
    |> html_body(password_reset_html_template(user, reset_url, token))
    |> text_body(password_reset_text_template(user, reset_url, token))
  end

  def password_changed_email(user, to_email) do
    new()
    |> to({user.name || user.username, to_email})
    |> from({@from_name, @from_email})
    |> subject("SENHA ALTERADA COM SUCESSO - JuruConnect")
    |> html_body(password_changed_html_template(user))
    |> text_body(password_changed_text_template(user))
  end

  def security_alert_email(user, to_email, event_type, details) do
    new()
    |> to({user.name || user.username, to_email})
    |> from({@from_name, @from_email})
    |> subject("ALERTA DE SEGURANÇA - JuruConnect")
    |> html_body(security_alert_html_template(user, event_type, details))
    |> text_body(security_alert_text_template(user, event_type, details))
  end

  def welcome_email(user, to_email, temporary_password \\ nil) do
    new()
    |> to({user.name || user.username, to_email})
    |> from({@from_name, @from_email})
    |> subject("BEM-VINDO AO JuruConnect!")
    |> html_body(welcome_html_template(user, temporary_password))
    |> text_body(welcome_text_template(user, temporary_password))
  end

  # HTML Templates

  defp password_reset_html_template(user, reset_url, token) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Redefinição de Senha - JuruConnect</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
            .content { background: #f8f9fa; padding: 30px; border-radius: 0 0 8px 8px; }
            .button { display: inline-block; background: #007bff; color: white; padding: 12px 30px; text-decoration: none; border-radius: 6px; font-weight: bold; margin: 20px 0; }
            .warning { background: #fff3cd; border: 1px solid #ffeaa7; padding: 15px; border-radius: 6px; margin: 20px 0; }
            .footer { text-align: center; margin-top: 30px; color: #666; font-size: 14px; }
            .token-info { background: #e9ecef; padding: 15px; border-radius: 6px; font-family: monospace; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1> Redefinição de Senha</h1>
                <p>JuruConnect - Jurunense Home Center</p>
            </div>
            <div class="content">
                <h2>Olá, #{user.name || user.username}!</h2>

                <p>Recebemos uma solicitação para redefinir a senha da sua conta JuruConnect.</p>

                <p>Clique no botão abaixo para redefinir sua senha:</p>

                <p style="text-align: center;">
                    <a href="#{reset_url}" class="button">Redefinir Senha</a>
                </p>

                <div class="warning">
                    <strong>IMPORTANTE:</strong>
                    <ul>
                        <li>Este link é válido por apenas <strong>2 horas</strong></li>
                        <li>Use apenas se você solicitou a redefinição</li>
                        <li>Nunca compartilhe este link com outras pessoas</li>
                    </ul>
                </div>

                <p>Se o botão não funcionar, copie e cole o link abaixo no seu navegador:</p>
                <div class="token-info">
                    #{reset_url}
                </div>

                <p><strong>Token de Segurança:</strong> #{String.slice(token, 0, 8)}...</p>

                <hr style="margin: 30px 0; border: none; border-top: 1px solid #ddd;">

                <p><small>Se você não solicitou esta redefinição, ignore este e-mail. Sua senha permanecerá inalterada.</small></p>
            </div>
            <div class="footer">
                <p>© #{Date.utc_today().year} Jurunense Home Center - JuruConnect</p>
                <p>Este é um e-mail automático, não responda.</p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp password_changed_html_template(user) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Senha Alterada - JuruConnect</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: linear-gradient(135deg, #28a745 0%, #20c997 100%); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
            .content { background: #f8f9fa; padding: 30px; border-radius: 0 0 8px 8px; }
            .success { background: #d4edda; border: 1px solid #c3e6cb; padding: 15px; border-radius: 6px; margin: 20px 0; }
            .footer { text-align: center; margin-top: 30px; color: #666; font-size: 14px; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>SENHA ALTERADA COM SUCESSO</h1>
                <p>JuruConnect - Jurunense Home Center</p>
            </div>
            <div class="content">
                <h2>Olá, #{user.name || user.username}!</h2>

                <div class="success">
                    <strong>Sua senha foi alterada com sucesso!</strong>
                </div>

                <p>Sua senha do JuruConnect foi redefinida em: <strong>#{DateTime.utc_now() |> DateTime.to_date()}</strong></p>

                <p>Se você não fez esta alteração, entre em contato conosco imediatamente.</p>

                <p>Para sua segurança, certifique-se de:</p>
                <ul>
                    <li>Usar uma senha forte e única</li>
                    <li>Não compartilhar suas credenciais</li>
                    <li>Fazer logout de dispositivos não confiáveis</li>
                </ul>
            </div>
            <div class="footer">
                <p>© #{Date.utc_today().year} Jurunense Home Center - JuruConnect</p>
                <p>Este é um e-mail automático, não responda.</p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp security_alert_html_template(user, event_type, details) do
    event_description = format_security_event(event_type, details)

    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Alerta de Segurança - JuruConnect</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: linear-gradient(135deg, #dc3545 0%, #fd7e14 100%); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
            .content { background: #f8f9fa; padding: 30px; border-radius: 0 0 8px 8px; }
            .alert { background: #f8d7da; border: 1px solid #f5c6cb; padding: 15px; border-radius: 6px; margin: 20px 0; }
            .footer { text-align: center; margin-top: 30px; color: #666; font-size: 14px; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>ALERTA DE SEGURANÇA</h1>
                <p>JuruConnect - Jurunense Home Center</p>
            </div>
            <div class="content">
                <h2>Olá, #{user.name || user.username}!</h2>

                <div class="alert">
                    <strong>ATIVIDADE SUSPEITA DETECTADA</strong>
                </div>

                <p>#{event_description}</p>

                <p><strong>Detalhes do Evento:</strong></p>
                <ul>
                    <li><strong>Data/Hora:</strong> #{DateTime.utc_now()}</li>
                    <li><strong>IP:</strong> #{Map.get(details, :ip_address, "Não informado")}</li>
                    <li><strong>Tipo:</strong> #{event_type}</li>
                </ul>

                <p><strong>O que fazer:</strong></p>
                <ul>
                    <li>Se foi você, pode ignorar este alerta</li>
                    <li>Se não foi você, altere sua senha imediatamente</li>
                    <li>Entre em contato conosco se precisar de ajuda</li>
                </ul>
            </div>
            <div class="footer">
                <p>© #{Date.utc_today().year} Jurunense Home Center - JuruConnect</p>
                <p>Este é um e-mail automático, não responda.</p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp welcome_html_template(user, temporary_password) do
    password_info = if temporary_password do
      """
      <div class="warning">
          <strong>🔑 Senha Temporária:</strong> #{temporary_password}
          <br><small>Por favor, altere sua senha no primeiro login.</small>
      </div>
      """
    else
      ""
    end

    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Bem-vindo ao JuruConnect!</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: linear-gradient(135deg, #6f42c1 0%, #007bff 100%); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
            .content { background: #f8f9fa; padding: 30px; border-radius: 0 0 8px 8px; }
            .warning { background: #fff3cd; border: 1px solid #ffeaa7; padding: 15px; border-radius: 6px; margin: 20px 0; }
            .footer { text-align: center; margin-top: 30px; color: #666; font-size: 14px; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>BEM-VINDO AO JuruConnect!</h1>
                <p>Jurunense Home Center</p>
            </div>
            <div class="content">
                <h2>Olá, #{user.name || user.username}!</h2>

                <p>Seja bem-vindo ao <strong>JuruConnect</strong>, nossa plataforma de gestão e comunicação interna.</p>

                #{password_info}

                <p><strong>Suas credenciais de acesso:</strong></p>
                <ul>
                    <li><strong>Usuário:</strong> #{user.username}</li>
                    <li><strong>E-mail:</strong> #{user.email || "#{user.username}@jurunense.com"}</li>
                </ul>

                <p><strong>O que você pode fazer no JuruConnect:</strong></p>
                <ul>
                    <li>Acompanhar dashboard de vendas em tempo real</li>
                    <li>Participar do chat integrado por pedidos</li>
                    <li>Ver metas e celebrações da equipe</li>
                    <li>Visualizar relatórios de performance</li>
                </ul>
            </div>
            <div class="footer">
                <p>© #{Date.utc_today().year} Jurunense Home Center - JuruConnect</p>
                <p>Este é um e-mail automático, não responda.</p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  # Text Templates

  defp password_reset_text_template(user, reset_url, token) do
    """
     REDEFINIÇÃO DE SENHA - JURUCONNECT

    Olá, #{user.name || user.username}!

    Recebemos uma solicitação para redefinir a senha da sua conta JuruConnect.

    Acesse o link abaixo para redefinir sua senha:
    #{reset_url}

    Token de Segurança: #{String.slice(token, 0, 8)}...

    IMPORTANTE:
    - Este link é válido por apenas 2 horas
    - Use apenas se você solicitou a redefinição
    - Nunca compartilhe este link com outras pessoas

    Se você não solicitou esta redefinição, ignore este e-mail.

    ---
    © #{Date.utc_today().year} Jurunense Home Center - JuruConnect
    Este é um e-mail automático, não responda.
    """
  end

  defp password_changed_text_template(user) do
    """
    SENHA ALTERADA COM SUCESSO - JURUCONNECT

    Olá, #{user.name || user.username}!

    Sua senha do JuruConnect foi redefinida com sucesso em #{DateTime.utc_now() |> DateTime.to_date()}.

    Se você não fez esta alteração, entre em contato conosco imediatamente.

    Para sua segurança:
    - Use uma senha forte e única
    - Não compartilhe suas credenciais
    - Faça logout de dispositivos não confiáveis

    ---
    © #{Date.utc_today().year} Jurunense Home Center - JuruConnect
    Este é um e-mail automático, não responda.
    """
  end

  defp security_alert_text_template(user, event_type, details) do
    event_description = format_security_event(event_type, details)

    """
    ALERTA DE SEGURANÇA - JURUCONNECT

    Olá, #{user.name || user.username}!

    Atividade suspeita detectada: #{event_description}

    DETALHES:
    - Data/Hora: #{DateTime.utc_now()}
    - IP: #{Map.get(details, :ip_address, "Não informado")}
    - Tipo: #{event_type}

    O QUE FAZER:
    - Se foi você, pode ignorar este alerta
    - Se não foi você, altere sua senha imediatamente
    - Entre em contato conosco se precisar de ajuda

    ---
    © #{Date.utc_today().year} Jurunense Home Center - JuruConnect
    Este é um e-mail automático, não responda.
    """
  end

  defp welcome_text_template(user, temporary_password) do
    password_info = if temporary_password do
      "\n🔑 SENHA TEMPORÁRIA: #{temporary_password}\n(Por favor, altere sua senha no primeiro login)\n"
    else
      ""
    end

    """
    BEM-VINDO AO JURUCONNECT!

    Olá, #{user.name || user.username}!

    Seja bem-vindo ao JuruConnect, nossa plataforma de gestão e comunicação interna.
    #{password_info}
    SUAS CREDENCIAIS:
    - Usuário: #{user.username}
    - E-mail: #{user.email || "#{user.username}@jurunense.com"}

    O QUE VOCÊ PODE FAZER:
    - Acompanhar dashboard de vendas em tempo real
- Participar do chat integrado por pedidos
- Ver metas e celebrações da equipe
- Visualizar relatórios de performance

    ---
    © #{Date.utc_today().year} Jurunense Home Center - JuruConnect
    Este é um e-mail automático, não responda.
    """
  end

  defp format_security_event(:login_from_new_ip, details) do
    "Login realizado de um novo endereço IP: #{Map.get(details, :ip_address)}"
  end

  defp format_security_event(:brute_force_detected, details) do
    "Múltiplas tentativas de login falharam do IP: #{Map.get(details, :ip_address)}"
  end

  defp format_security_event(:password_change_failed, details) do
    "Tentativa de alteração de senha falhou do IP: #{Map.get(details, :ip_address)}"
  end

  defp format_security_event(event_type, _details) do
    "Evento de segurança: #{event_type}"
  end
end
