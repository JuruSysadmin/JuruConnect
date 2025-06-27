#!/bin/bash

# Script para gerar ícones PWA
# Uso: ./scripts/generate_pwa_icons.sh [caminho_para_logo]

set -e

# Diretórios
ASSETS_DIR="priv/static/assets"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Criar diretório de assets se não existir
mkdir -p "$ROOT_DIR/$ASSETS_DIR"

# Logo base (pode ser fornecido como parâmetro)
LOGO_PATH=${1:-"assets/logo.png"}

echo " Gerando ícones PWA..."

# Verificar se ImageMagick está instalado
if ! command -v convert &> /dev/null; then
    echo "⚠️  ImageMagick não encontrado. Instalando..."
    
    # Tentar instalar ImageMagick
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y imagemagick
    elif command -v yum &> /dev/null; then
        sudo yum install -y ImageMagick
    elif command -v brew &> /dev/null; then
        brew install imagemagick
    else
        echo "❌ Não foi possível instalar ImageMagick automaticamente."
        echo "   Por favor, instale manualmente e execute novamente."
        exit 1
    fi
fi

# Se não tiver logo, criar um logo simples
if [ ! -f "$ROOT_DIR/$LOGO_PATH" ]; then
    echo "📝 Logo não encontrado. Criando logo básico..."
    
    # Criar logo simples com ImageMagick
    convert -size 512x512 xc:'#3b82f6' \
            -fill white \
            -font helvetica \
            -pointsize 80 \
            -gravity center \
            -annotate +0+0 'JC' \
            "$ROOT_DIR/$ASSETS_DIR/logo-base.png"
    
    LOGO_PATH="$ASSETS_DIR/logo-base.png"
    echo "✅ Logo básico criado em $LOGO_PATH"
fi

echo "📱 Gerando ícones em diferentes tamanhos..."

# Tamanhos necessários para PWA
declare -a sizes=("16" "32" "48" "72" "96" "128" "144" "152" "180" "192" "384" "512")

for size in "${sizes[@]}"; do
    output_file="$ROOT_DIR/$ASSETS_DIR/icon-${size}x${size}.png"
    
    convert "$ROOT_DIR/$LOGO_PATH" \
            -resize ${size}x${size} \
            -background none \
            -gravity center \
            -extent ${size}x${size} \
            "$output_file"
    
    echo "✅ Ícone ${size}x${size} criado"
done

# Gerar favicon.ico
echo "🌐 Gerando favicon..."
convert "$ROOT_DIR/$LOGO_PATH" \
        -resize 32x32 \
        "$ROOT_DIR/priv/static/favicon.ico"

# Gerar browserconfig.xml para Windows
echo "🖥️  Gerando browserconfig.xml..."
cat > "$ROOT_DIR/priv/static/browserconfig.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<browserconfig>
    <msapplication>
        <tile>
            <square150x150logo src="/assets/icon-144x144.png"/>
            <TileColor>#3b82f6</TileColor>
        </tile>
    </msapplication>
</browserconfig>
EOF

# Gerar robots.txt básico
echo "🤖 Gerando robots.txt..."
cat > "$ROOT_DIR/priv/static/robots.txt" << EOF
User-agent: *
Allow: /

Sitemap: $(echo ${2:-"https://localhost:4000"})/sitemap.xml
EOF

echo ""
echo "✅ Ícones PWA gerados com sucesso!"
echo ""
echo "📋 Arquivos criados:"
echo "   • Ícones: priv/static/assets/icon-*x*.png"
echo "   • Favicon: priv/static/favicon.ico"
echo "   • Browserconfig: priv/static/browserconfig.xml"
echo "   • Robots: priv/static/robots.txt"
echo ""
echo "🔧 Próximos passos:"
echo "   1. Execute: mix phx.server"
echo "   2. Acesse: http://localhost:4000"
echo "   3. Teste PWA no Chrome: DevTools > Application > Manifest"
echo "   4. Para instalar: Chrome menu > Install app"
echo ""
echo "📱 Para testar no celular:"
echo "   1. Acesse pelo navegador móvel"
echo "   2. Menu > Add to Home Screen"
echo "" 