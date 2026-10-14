#!/bin/zsh
# Instalador do My Cloud (macOS): instala só o app (e confere o Claude Code, que ele usa).
# Dois cliques neste arquivo. Pode rodar de novo quando quiser: atualiza o app.
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

info "1/4 Claude Code"
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

info "2/4 App My Cloud"
# The ready-made app from the latest release (no Xcode). Without a release, a Mac with Xcode
# builds it from this folder.
pkill -f "My Cloud.app/Contents/MacOS" 2>/dev/null || true
ZIP_URL=$(curl -fsSL https://api.github.com/repos/gabrielxreis/myclaude/releases/latest 2>/dev/null \
  | python3 -c 'import json,sys; a=[x["browser_download_url"] for x in json.load(sys.stdin).get("assets",[]) if x["name"]=="MyCloud.zip"]; print(a[0] if a else "")' 2>/dev/null || true)
if [ -n "$ZIP_URL" ]; then
  T=$(mktemp -d)
  curl -fsSL "$ZIP_URL" -o "$T/MyCloud.zip" && ditto -x -k "$T/MyCloud.zip" "$T"
  [ -d "$T/My Cloud.app" ] || fail "Não consegui baixar o app."
  rm -rf "$DEST"                          # a versão antiga sai sempre
  ditto "$T/My Cloud.app" "$DEST"
  xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
  rm -rf "$T"
  ok "instalado em $DEST (app pronto, versão antiga removida)"
elif command -v xcodebuild >/dev/null 2>&1 && [ -d /Applications/Xcode.app ]; then
  command -v xcodegen >/dev/null 2>&1 || brew install xcodegen >/dev/null
  MYCLOUD_NO_OPEN=1 "$ROOT/scripts/build-mycloud.sh"
  [ -d "$DEST" ] || fail "A compilação não gerou o app."
  ok "instalado em $DEST (compilado aqui, versão antiga removida)"
else
  fail "Ainda não há app pronto para baixar e este Mac não tem o Xcode para compilar."
fi

info "3/4 Usar qualquer app (Peekaboo)"
# Lets Cloud see the screen and click in any app (github.com/openclaw/Peekaboo, MIT). Needs Node 22+.
if command -v npx >/dev/null 2>&1 && [ "$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)" -ge 22 ]; then
  if ! claude mcp get peekaboo >/dev/null 2>&1; then
    cp "$HOME/.claude.json" "$HOME/.claude.json.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    claude mcp add --scope user peekaboo -- npx -y @steipete/peekaboo mcp >/dev/null 2>&1 && ok "Peekaboo adicionado ao Claude Code" \
      || warn "não consegui adicionar o Peekaboo (dá para ligar depois em Ajustes → Assistente)"
  else ok "Peekaboo já estava no Claude Code"; fi
  defaults write com.gabrielreis.mycloud cloudComputerUse -bool true
else
  warn "sem Node 22+: o \"usar qualquer app\" fica para depois (brew install node e ligue em Ajustes → Assistente)"
fi

info "4/4 Abrindo o My Cloud"
open "$DEST"
ok "pronto"

cat <<'FIM'

  Na primeira abertura, o My Cloud pede as permissões uma depois da outra (microfone, fala,
  contatos, calendário, controlar o Chrome/Safari/Terminal) e no fim mostra o que só você liga:
   • Acessibilidade e Gravação de tela para o My Cloud (Ajustes do Sistema).
   • Chrome: Visualização → Desenvolvedor → Permitir o JavaScript do Eventos da Apple.
  Tudo fica em Ajustes → Permissões, com o botão "Configurar tudo agora".
  Depois é só dizer: "Ei Cloud, abre o Chrome, entra no YouTube e pesquisa…"

FIM
