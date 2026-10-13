#!/bin/zsh
# Instalador do My Cloud (macOS): o app + as skills /ogab (vídeo) e /ojhon (tráfego pago).
# Dois cliques neste arquivo. Pode rodar de novo quando quiser: atualiza tudo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="My Cloud.app"
DEST="/Applications/$APP_NAME"

ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
info() { printf "\n\033[1m%s\033[0m\n" "$1"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "O My Cloud é só para macOS."
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

info "1/6 Claude Code"
if ! command -v claude >/dev/null 2>&1; then
  echo "  Instalando o Claude Code (instalador oficial da Anthropic)..."
  curl -fsSL https://claude.ai/install.sh | bash
  export PATH="$HOME/.local/bin:$PATH"
fi
command -v claude >/dev/null 2>&1 || fail "Não consegui instalar o Claude Code. Veja https://claude.com/claude-code"
ok "Claude Code $(claude --version 2>/dev/null | head -1)"
if claude -p "ok" --output-format json 2>/dev/null | grep -q '"is_error":true'; then
  warn "O Claude Code não está logado. Abrindo agora: digite /login, entre com a sua assinatura e depois /exit."
  claude < /dev/tty || true
fi

info "2/6 Skill /ogab (vídeo: DaVinci, legenda, motions, roteiro)"
curl -fsSL https://raw.githubusercontent.com/gabrielxreis/ogab/main/install.sh | bash
ok "/ogab pronta"

info "3/6 Skill /ojhon (tráfego pago: auditoria, plano, criativo, relatório)"
curl -fsSL https://raw.githubusercontent.com/gabrielxreis/ojhon/main/install.sh | bash
ok "/ojhon pronta"

info "4/6 RustDesk (acesso remoto ao Mac pelo celular ou outro computador)"
if [ -d "/Applications/RustDesk.app" ]; then ok "RustDesk já instalado"
else
  command -v brew >/dev/null 2>&1 && brew install --cask rustdesk >/dev/null && ok "RustDesk instalado" \
    || warn "não consegui instalar o RustDesk: brew install --cask rustdesk"
fi

info "5/6 App My Cloud"
command -v xcodebuild >/dev/null 2>&1 || fail "Precisa do Xcode instalado (App Store) para compilar o My Cloud."
command -v xcodegen >/dev/null 2>&1 || { echo "  Instalando o xcodegen..."; brew install xcodegen >/dev/null; }
# scripts/build-mycloud.sh compila, assina com identidade estável (o macOS guarda as permissões
# de microfone e fala entre versões), apaga a versão antiga e instala em Aplicativos.
MYCLOUD_NO_OPEN=1 "$ROOT/scripts/build-mycloud.sh"
[ -d "$DEST" ] || fail "A compilação não gerou o app."
ok "instalado em $DEST (versão antiga removida)"

info "6/6 Abrindo o My Cloud"
open "$DEST"
ok "pronto"

cat <<'FIM'

  Falta pouco, no próprio app (ícone na barra de menu → Ajustes):
   • Voz: aceite o microfone e o reconhecimento de fala quando o Mac pedir.
   • Agentes: "Instalar hooks" do Claude Code, para o Cloud ver suas sessões.
   • Voz → O que o Cloud pode fazer: escolha o modo (Lista de ações é o padrão).
   • RustDesk: entre com Google ou GitHub e libere Acessibilidade e Gravação de Tela
     nos Ajustes do Sistema, para acessar o Mac de longe.
  Depois é só dizer: "Ei Cloud, abre o Chrome e pesquisa…"

FIM
