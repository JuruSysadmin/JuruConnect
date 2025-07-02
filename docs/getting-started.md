# Começando com JuruConnect

Este guia irá ajudá-lo a configurar e executar o JuruConnect.

## Pré-requisitos

- **Elixir** >= 1.14
- **Node.js** >= 18
- **PostgreSQL** >= 13

## Instalação

```bash
# 1. Clone o repositório
git clone https://github.com/jurunense/juruconnect.git
cd juruconnect

# 2. Instale dependências
mix deps.get

# 3. Configure banco
mix ecto.setup

# 4. Inicie servidor
mix phx.server
```

Acesse: http://localhost:4000

## Primeiros Passos

### Criando usuário admin:

```bash
mix run -e "
  alias App.Accounts
  {:ok, user} = Accounts.create_user(%{
    username: \"admin\",
    password: \"admin123\",
    role: \"admin\"
  })
"
```

### Login:
- Usuário: `admin`
- Senha: `admin123`

## Comandos Úteis

```bash
mix test              # Executar testes
mix docs              # Gerar documentação
mix ecto.reset        # Resetar banco
```
