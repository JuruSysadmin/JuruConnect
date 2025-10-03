#!/bin/bash
# deploy-zero-downtime.sh

set -e  # Parar em caso de erro

# Verificar se está no diretório correto
if [ ! -f "mix.exs" ]; then
    echo "ERRO: Execute este script do diretório raiz do projeto!"
    exit 1
fi

# Definir versões
OLD_VERSION="0.1.0"
NEW_VERSION="0.1.1"

echo "Iniciando deploy zero-downtime..."
echo "Versão antiga: $OLD_VERSION"
echo "Versão nova: $NEW_VERSION"

# 1. Gerar nova release
echo "Gerando release..."
MIX_ENV=prod mix release

# 2. Backup da versão anterior
if [ -d "releases/$OLD_VERSION" ]; then
    echo "Fazendo backup da versão anterior..."
    cp -r "releases/$OLD_VERSION" "releases/backup-$OLD_VERSION"
else
    echo "AVISO: Versão anterior não encontrada, prosseguindo..."
fi

# 3. Deploy assets
echo "Preparando assets..."
MIX_ENV=prod mix assets.deploy

# 4. Migrações do banco
echo "Executando migrações..."
MIX_ENV=prod mix ecto.migrate

# 5. Upgrade quente
echo "Executando upgrade quente..."
if command -v _build/prod/rel/app/bin/app >/dev/null 2>&1; then
    echo "SUCCESSO: Release gerada com sucesso!"
    echo "Para executar o upgrade, execute manualmente:"
    echo "   _build/prod/rel/app/bin/app upgrade $NEW_VERSION"
else
    echo "ERRO: Release não encontrada!"
    exit 1
fi

echo "Deploy concluído!"
echo "Para monitorar: _build/prod/rel/app/bin/app eval \":observer.start\""