#!/usr/bin/env bash

# ====================================================================================
#
# Script: setup_minio.sh
#
# Descrição: Configura um alias, um bucket e uma política de acesso para o MinIO.
#            O script é idempotente.
#
# Autor: Seu Nome / Sua Empresa
# Data: 01/10/2025
#
# Uso:
#   ./setup_minio.sh
#
# Variáveis de Ambiente (opcional):
#   MINIO_ENDPOINT        - Endereço do MinIO (padrão: http://localhost)
#   MINIO_PORT            - Porta do MinIO (padrão: 9000)
#   MINIO_CONSOLE_PORT    - Porta do Console Web (padrão: 9001)
#   MINIO_ACCESS_KEY      - Chave de acesso (padrão: minio)
#   MINIO_SECRET_KEY      - Chave secreta (padrão: minio123)
#   MINIO_ALIAS           - Alias para o mc (padrão: local)
#   MINIO_BUCKET          - Nome do bucket a ser criado (padrão: juruconnect)
#   MINIO_BUCKET_POLICY   - Política de acesso do bucket (padrão: public)
#
# ====================================================================================

set -Eeuo pipefail

readonly MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://localhost}"
readonly MINIO_PORT="${MINIO_PORT:-9000}"
readonly MINIO_CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"
readonly MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-minio}"
readonly MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-minio123}"
readonly MINIO_ALIAS="${MINIO_ALIAS:-local}"
readonly MINIO_BUCKET="${MINIO_BUCKET:-juruconnect}"
readonly MINIO_BUCKET_POLICY="${MINIO_BUCKET_POLICY:-public}"

readonly MINIO_URL="$MINIO_ENDPOINT:$MINIO_PORT"
readonly HEALTH_CHECK_URL="$MINIO_URL/minio/health/live"

readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_CYAN='\033[0;36m'

log_info() {
    echo -e "${C_CYAN}INFO:${C_RESET} $1"
}
log_success() {
    echo -e "${C_GREEN}SUCCESS:${C_RESET} $1"
}
log_warn() {
    echo -e "${C_YELLOW}WARN:${C_RESET} $1"
}
log_error() {
    echo -e "${C_RED}ERROR:${C_RESET} $1" >&2
    exit 1
}

check_dependencies() {
    log_info "Verificando dependências..."
    for cmd in curl; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Comando '$cmd' não encontrado. Por favor, instale-o."
        fi
    done
}

wait_for_minio() {
    local max_attempts=30
    local attempt=0
    log_info "Aguardando MinIO em $HEALTH_CHECK_URL..."
    until curl -sf "$HEALTH_CHECK_URL" > /dev/null; do
        if [ $attempt -ge $max_attempts ]; then
            log_error "Tempo limite excedido. MinIO não respondeu após $((max_attempts * 2)) segundos."
        fi
        attempt=$((attempt + 1))
        log_info "Tentativa $attempt/$max_attempts. Aguardando 2 segundos..."
        sleep 2
    done
    log_success "MinIO está respondendo."
}

install_mc_if_needed() {
    if command -v mc &> /dev/null; then
        log_info "MinIO Client (mc) já está instalado."
    else
        log_info "Instalando MinIO Client (mc)..."
        local mc_temp_file
        mc_temp_file=$(mktemp)
        curl -o "$mc_temp_file" https://dl.min.io/client/mc/release/linux-amd64/mc
        chmod +x "$mc_temp_file"
        if sudo mv "$mc_temp_file" /usr/local/bin/mc; then
            log_success "MinIO Client instalado."
        else
            log_error "Falha ao mover 'mc' para /usr/local/bin/. Verifique as permissões de sudo."
        fi
    fi
}

configure_minio_resources() {
    log_info "Configurando alias '$MINIO_ALIAS'..."
    mc alias set "$MINIO_ALIAS" "$MINIO_URL" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" --api "s3v4" &> /dev/null

    log_info "Criando bucket '$MINIO_BUCKET'..."
    mc mb "$MINIO_ALIAS/$MINIO_BUCKET" --ignore-existing

    log_info "Configurando política '$MINIO_BUCKET_POLICY' para o bucket '$MINIO_BUCKET'..."
    mc anonymous set "$MINIO_BUCKET_POLICY" "$MINIO_ALIAS/$MINIO_BUCKET"
}

verify_configuration() {
    log_info "Verificando política de acesso do bucket..."
    if mc anonymous get "$MINIO_ALIAS/$MINIO_BUCKET" | grep -q "$MINIO_BUCKET_POLICY"; then
        log_success "Política '$MINIO_BUCKET_POLICY' aplicada corretamente."
    else
        log_error "Falha ao verificar a política do bucket."
    fi
}

main() {
    log_info "Iniciando configuração do MinIO..."
    
    check_dependencies
    wait_for_minio
    install_mc_if_needed
    configure_minio_resources
    verify_configuration

    echo
    log_success "Configuração do MinIO finalizada."
    echo -e "--------------------------------------------------"
    echo -e "${C_YELLOW}Dashboard:${C_RESET} $MINIO_ENDPOINT:$MINIO_CONSOLE_PORT"
    echo -e "${C_YELLOW}Login:${C_RESET}     $MINIO_ACCESS_KEY / $MINIO_SECRET_KEY"
    echo -e "${C_YELLOW}Bucket:${C_RESET}    $MINIO_BUCKET ($MINIO_BUCKET_POLICY)"
    echo -e "--------------------------------------------------"
}

main "$@"