#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR"
SELECT_FILE="$BUILD_DIR/.lupi-select"
MODE_FILE="$BUILD_DIR/.lupi-mode"
SRC_HASH_FILE="$BUILD_DIR/.last-src-hash"
DEMOS_DIR="$BUILD_DIR/jogos-demo"
BACKUP_DIR="$BUILD_DIR/bkp_jogos"
EMSDK_PATH_FILE="$BUILD_DIR/.emsdk-path"
EMSDK_DIR="${EMSDK_DIR:-}"

# Repositórios externos
LUPINHO_DIR="$BUILD_DIR/lupinho"
FURNACE_DIR="$BUILD_DIR/furnace"
SDK_DIR="$BUILD_DIR/lupinho-sdk"
SDK_SRC="$SDK_DIR/src"
CODEC_DIR="$BUILD_DIR/lupi-codec"
WAV2VGM_DIR="$BUILD_DIR/wav2vgm"
VGM2FUR_DIR="$BUILD_DIR/vgm2fur"
BUILD_LUPI_DIR="$BUILD_DIR/build-lupi"
BUILD_LUPI_URL="https://github.com/Hirikko/build-lupi.git"

RELEASE_DIR="$CODEC_DIR/jogo-release"
RELEASES_DIR="$RELEASE_DIR/releases"
JOGO="$CODEC_DIR/jogo"
LUPI="$RELEASES_DIR/jogo.lupi"
LUPINHO_SITE="$LUPINHO_DIR/site"

MODE=""
GAME_NAME="${GAME_NAME:-}"
GAME_SELECTION=""
CLI_GAME=""
FORCE_SELECT=0
CFG_OP=""
CFG_ONLY=0

step() {
    echo ""
    echo "================================================="
    echo "$@"
    echo "================================================="
}

# --- Parse args ---
while [ $# -gt 0 ]; do
    case "$1" in
        --select|-s) FORCE_SELECT=1; shift ;;
        --help|-h)
            cat <<EOF
Uso: $0 [<nome-do-jogo>] [--select] [--cfg <chave>=<valor>] [--cfg-only <chave>=<valor>]

Argumentos posicionais:
  <nome-do-jogo>   Seleção rápida (ignorado se seletor=desliga).

Flags:
  --select, -s         Força o seletor interativo (mesmo com seletor=desliga)
  --cfg <op>           Altera configuração e CONTINUA o build.
  --cfg-only <op>      Altera configuração e SAI (sem build).
                       Opções: seletor=liga|desliga, modo=dev|game|user, update=ask|silent
  --help, -h           Mostra esta ajuda
EOF
            exit 0
            ;;
        --cfg)
            shift
            if [ $# -eq 0 ]; then
                echo "Erro: --cfg precisa de argumento (ex: --cfg seletor=liga)"
                exit 1
            fi
            CFG_OP="$1"
            shift
            ;;
        --cfg-only)
            shift
            if [ $# -eq 0 ]; then
                echo "Erro: --cfg-only precisa de argumento (ex: --cfg-only seletor=liga)"
                exit 1
            fi
            CFG_OP="$1"
            CFG_ONLY=1
            shift
            ;;
        -*)
            echo "Opção desconhecida: $1"
            exit 1
            ;;
        *)
            CLI_GAME="$1"
            shift
            ;;
    esac
done

# --- SO ---
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        if command -v apt &>/dev/null; then PKG_MANAGER="apt"
        elif command -v dnf &>/dev/null; then PKG_MANAGER="dnf"
        elif command -v pacman &>/dev/null; then PKG_MANAGER="pacman"
        else echo "Erro: gerenciador não suportado."; exit 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        command -v brew &>/dev/null || { echo "Erro: instale Homebrew."; exit 1; }
        PKG_MANAGER="brew"
    else
        echo "Erro: SO não suportado ($OSTYPE)."; exit 1
    fi
}

install_packages() {
    local packages=("$@")
    [ ${#packages[@]} -eq 0 ] && return 0
    echo "Instalando pacotes: ${packages[*]}"
    case "$PKG_MANAGER" in
        apt)    sudo apt update && sudo apt install -y "${packages[@]}" ;;
        brew)   brew install "${packages[@]}" ;;
        dnf)    sudo dnf install -y "${packages[@]}" ;;
        pacman) sudo pacman -S --noconfirm "${packages[@]}" ;;
    esac
}

# --- .lupi-select helpers ---
select_migrate() {
    [ ! -f "$SELECT_FILE" ] && return 0
    if grep -qE '^update=' "$SELECT_FILE" 2>/dev/null; then
        return 0
    fi
    if grep -qE '^jogo=' "$SELECT_FILE" 2>/dev/null; then
        local jogo modo sel
        jogo=$(select_get_jogo)
        modo=$(select_get_modo)
        sel=$(select_get_seletor)
        printf "jogo=%s\nmodo=%s\nseletor=%s\nupdate=ask\n" "$jogo" "$modo" "$sel" > "$SELECT_FILE"
        echo "  Migração .lupi-select: adicionado update=ask"
        return 0
    fi
    local old
    old=$(head -n1 "$SELECT_FILE" 2>/dev/null | tr -d '[:space:]')
    [ -z "$old" ] && return 0
    local sel="liga"
    local modo="user"
    [ "$old" = "caio-pernocas" ] && modo="game"
    [ "$old" = "lupinho-debug-lab" ] && modo="dev"

    if [ -f "$SDK_SRC/.${old}-installed" ] && grep -qE '^making_game=1$' "$SDK_SRC/.${old}-installed" 2>/dev/null; then
        sel="desliga"
        sed -i '/^making_game=1$/d' "$SDK_SRC/.${old}-installed" 2>/dev/null || true
    fi
    printf "jogo=%s\nmodo=%s\nseletor=%s\nupdate=ask\n" "$old" "$modo" "$sel" > "$SELECT_FILE"
    echo "  Migração .lupi-select: jogo=$old, modo=$modo, seletor=$sel, update=ask"
}

select_get_jogo() {
    if [ -f "$SELECT_FILE" ] && grep -qE '^jogo=' "$SELECT_FILE" 2>/dev/null; then
        grep -E '^jogo=' "$SELECT_FILE" | head -n1 | cut -d= -f2- | tr -d '[:space:]'
    elif [ -f "$SELECT_FILE" ]; then
        head -n1 "$SELECT_FILE" 2>/dev/null | tr -d '[:space:]'
    else
        echo ""
    fi
}

select_get_modo() {
    if [ -f "$SELECT_FILE" ]; then
        local v
        v=$(grep -E '^modo=' "$SELECT_FILE" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '[:space:]')
        [ -n "$v" ] && { echo "$v"; return; }
    fi
    local j
    j=$(select_get_jogo)
    [ "$j" = "caio-pernocas" ] && echo "game" && return
    [ "$j" = "lupinho-debug-lab" ] && echo "dev" && return
    echo "user"
}

select_get_seletor() {
    if [ -f "$SELECT_FILE" ]; then
        local v
        v=$(grep -E '^seletor=' "$SELECT_FILE" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '[:space:]')
        [ -n "$v" ] && { echo "$v"; return; }
    fi
    echo "liga"
}

select_get_update() {
    if [ -f "$SELECT_FILE" ]; then
        local v
        v=$(grep -E '^update=' "$SELECT_FILE" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '[:space:]')
        [ -n "$v" ] && { echo "$v"; return; }
    fi
    echo "ask"
}

select_set_jogo() {
    local jogo="$1"
    local sel=$(select_get_seletor)
    local modo=$(select_get_modo)
    local upd=$(select_get_update)
    printf "jogo=%s\nmodo=%s\nseletor=%s\nupdate=%s\n" "$jogo" "$modo" "$sel" "$upd" > "$SELECT_FILE"
}

select_set_modo() {
    local modo="$1"
    local jogo=$(select_get_jogo)
    local sel=$(select_get_seletor)
    local upd=$(select_get_update)
    printf "jogo=%s\nmodo=%s\nseletor=%s\nupdate=%s\n" "$jogo" "$modo" "$sel" "$upd" > "$SELECT_FILE"
}

select_set_seletor() {
    local sel="$1"
    local jogo=$(select_get_jogo)
    local modo=$(select_get_modo)
    local upd=$(select_get_update)
    printf "jogo=%s\nmodo=%s\nseletor=%s\nupdate=%s\n" "$jogo" "$modo" "$sel" "$upd" > "$SELECT_FILE"
}

select_set_update() {
    local upd="$1"
    local jogo=$(select_get_jogo)
    local modo=$(select_get_modo)
    local sel=$(select_get_seletor)
    printf "jogo=%s\nmodo=%s\nseletor=%s\nupdate=%s\n" "$jogo" "$modo" "$sel" "$upd" > "$SELECT_FILE"
}

# --- Processa --cfg ---
process_cfg_op() {
    local op="$1"
    local only="${2:-0}"

    select_migrate
    if [ ! -f "$SELECT_FILE" ]; then
        echo "Erro: .lupi-select não existe. Rode ./build-lupi.sh uma vez primeiro."
        exit 1
    fi
    case "$op" in
        seletor=*)
            local val="${op#seletor=}"
            case "$val" in
                liga|on|true|1)      val="liga" ;;
                desliga|off|false|0) val="desliga" ;;
                *) echo "Valor inválido: '$val' (use liga ou desliga)"; exit 1 ;;
            esac
            select_set_seletor "$val"
            echo "  Configurado: seletor=$val"
            ;;
        modo=*)
            local val="${op#modo=}"
            case "$val" in
                dev|game|user) ;;
                *) echo "Valor inválido: '$val' (use dev, game ou user)"; exit 1 ;;
            esac
            select_set_modo "$val"
            echo "  Configurado: modo=$val"
            ;;
        update=*)
            local val="${op#update=}"
            case "$val" in
                ask|sim|perguntar)        val="ask" ;;
                silent|nunca|silenciar)   val="silent" ;;
                *) echo "Valor inválido: '$val' (use ask ou silent)"; exit 1 ;;
            esac
            select_set_update "$val"
            echo "  Configurado: update=$val"
            ;;
        *)
            echo "Opção --cfg desconhecida: $op"
            echo "Opções: seletor=liga, seletor=desliga, modo=dev, modo=game, update=ask, update=silent"
            exit 1
            ;;
    esac
    if [ "$only" -eq 1 ]; then
        echo "  (--cfg-only: build não executado)"
        exit 0
    fi
    echo "  Continuando com o build..."
    echo ""
}

if [ -n "$CFG_OP" ]; then
    process_cfg_op "$CFG_OP" "$CFG_ONLY"
fi

# --- Emscripten ---
persist_emsdk_to_rc() {
    local emsdk_path=$1
    local block_start="# >>> emsdk (build-lupi.sh) >>>"
    local block_end="# <<< emsdk (build-lupi.sh) <<<"
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ ! -f "$rc" ] && continue
        if grep -qF "$block_start" "$rc" 2>/dev/null; then
            continue
        fi
        {
            echo ""
            echo "$block_start"
            echo "export EMSDK_QUIET=1"
            echo "source \"$emsdk_path/emsdk_env.sh\""
            echo "$block_end"
        } >> "$rc"
        echo "  $rc: bloco emsdk adicionado."
    done
}

check_emscripten() {
    local candidates=()
    [ -n "${EMSDK_DIR:-}" ] && candidates+=("$EMSDK_DIR")
    if [ -f "$EMSDK_PATH_FILE" ]; then
        local saved=$(cat "$EMSDK_PATH_FILE" 2>/dev/null || echo "")
        [ -n "$saved" ] && candidates+=("$saved")
    fi
    candidates+=("$BUILD_DIR/emsdk" "$HOME/emsdk")

    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate/emsdk_env.sh" ]; then
            EMSDK_DIR="$candidate"
            export EMSDK_QUIET=1
            set +e
            source "$EMSDK_DIR/emsdk_env.sh" > /dev/null 2>&1
            set -e
            if command -v emcc &>/dev/null; then
                echo "Emscripten (emsdk) carregado: $(emcc --version | head -n1)"
                echo "  Local: $EMSDK_DIR"
                [ ! -f "$EMSDK_PATH_FILE" ] && printf "%s" "$EMSDK_DIR" > "$EMSDK_PATH_FILE"
                return 0
            fi
        fi
    done
    command -v emcc &>/dev/null && { echo "Emscripten do sistema detectado."; return 0; }
    install_emscripten
}

install_emscripten() {
    step " Emscripten (emcc) não encontrado"
    echo "Onde deseja instalá-lo?"
    echo "  1) Na pasta do projeto:  $BUILD_DIR/emsdk"
    echo "  2) Na home do usuário:   $HOME/emsdk"
    echo "  3) Caminho personalizado"
    read -p "Escolha [1/2/3]: " emsdk_choice
    case "$emsdk_choice" in
        1) EMSDK_DIR="$BUILD_DIR/emsdk" ;;
        2) EMSDK_DIR="$HOME/emsdk" ;;
        3) read -p "Digite o caminho completo: " p; EMSDK_DIR="${p/#\~/$HOME}" ;;
        *) echo "Opção inválida."; exit 1 ;;
    esac
    if [ -d "$EMSDK_DIR" ] && [ -f "$EMSDK_DIR/emsdk" ]; then
        echo "emsdk já existe em $EMSDK_DIR. Reutilizando."
    else
        echo "Clonando emsdk em $EMSDK_DIR..."
        mkdir -p "$(dirname "$EMSDK_DIR")"
        git clone https://github.com/emscripten-core/emsdk.git "$EMSDK_DIR"
    fi
    printf "%s" "$EMSDK_DIR" > "$EMSDK_PATH_FILE"
    cd "$EMSDK_DIR"
    git pull --quiet
    echo "Instalando Emscripten (latest)..."
    ./emsdk install latest
    ./emsdk activate latest
    export EMSDK_QUIET=1
    set +e
    source ./emsdk_env.sh > /dev/null 2>&1
    set -e
    cd "$SCRIPT_DIR"
    command -v emcc &>/dev/null || { echo "Erro: emcc indisponível."; exit 1; }
    echo "Emscripten instalado: $(emcc --version | head -n1)"
    step " Configurando ~/.bashrc e ~/.zshrc"
    persist_emsdk_to_rc "$EMSDK_DIR"
}

check_system_dependencies() {
    step "[0/8] Verificando dependências do sistema..."
    detect_os
    local missing=()
    local check_cmds=("git" "make" "cmake" "ninja" "zip" "curl" "python3" "magick")
    declare -A pkg_linux=(
        [git]="git" [make]="build-essential" [cmake]="cmake" [ninja]="ninja-build"
        [zip]="zip" [curl]="curl" [python3]="python3" [magick]="imagemagick"
    )
    declare -A pkg_macos=(
        [git]="git" [make]="make" [cmake]="cmake" [ninja]="ninja"
        [zip]="zip" [curl]="curl" [python3]="python3" [magick]="imagemagick"
    )
    for cmd in "${check_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            if [ "$OS" = "linux" ]; then missing+=("${pkg_linux[$cmd]}")
            else missing+=("${pkg_macos[$cmd]}")
            fi
        fi
    done
    command -v lua &>/dev/null || {
        if [ "$OS" = "linux" ]; then missing+=("lua5.3" "liblua5.3-dev")
        else missing+=("lua")
        fi
    }
    check_emscripten
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Pacotes faltando: ${missing[*]}"
        read -p "Deseja instalar os pacotes faltantes? (s/n): " ans
        [[ "$ans" =~ ^[Ss]$ ]] || { echo "Abortando."; exit 1; }
        install_packages "${missing[@]}"
    else
        echo "Todas as dependências do sistema estão presentes."
    fi
}

# --- Helpers git ---
get_repo_hash() {
    local dir=$1
    if [ -d "$dir/.git" ]; then
        git -C "$dir" rev-parse HEAD 2>/dev/null || echo ""
    else
        echo ""
    fi
}

get_src_content_hash() {
    if [ ! -d "$SDK_SRC" ]; then
        echo ""
        return
    fi
    (
        cd "$SDK_SRC"
        find . -mindepth 1 -type f \
            -not -path "./.git/*" -not -name ".git" \
            -not -name ".*-installed" \
            -print0 2>/dev/null \
        | sort -z \
        | xargs -0 -r sha256sum 2>/dev/null \
        | sha256sum 2>/dev/null \
        | cut -d' ' -f1
    )
}

src_content_changed_since_backup() {
    local current_hash
    current_hash=$(get_src_content_hash)
    [ -z "$current_hash" ] && return 1

    if [ ! -f "$SRC_HASH_FILE" ]; then
        return 0
    fi

    local stored_hash
    stored_hash=$(cat "$SRC_HASH_FILE" 2>/dev/null | tr -d '[:space:]')
    [ "$current_hash" != "$stored_hash" ]
}

git_sync_dir() {
    local dir=$1 url=$2 branch=${3:-""}

    if [ -d "$dir" ] && [ ! -d "$dir/.git" ]; then
        if [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
            echo "  $(basename "$dir") já existe (sem .git). Pulando clone."
            return 0
        fi
        rm -rf "$dir"
    fi

    if [ ! -d "$dir/.git" ]; then
        echo "Clonando $(basename "$dir")..."
        if [ -n "$branch" ]; then git clone -b "$branch" "$url" "$dir"
        else git clone "$url" "$dir"
        fi
        return 0
    fi

    local old_pwd="$PWD"
    cd "$dir" || { echo "  Erro: não foi possível entrar em $dir"; return 1; }

    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "")
    if [ -z "$current_branch" ]; then
        echo "  Aviso: $(basename "$dir") em detached HEAD. Pular update."
        cd "$old_pwd"
        return 0
    fi

    if [ -n "$branch" ] && [ "$current_branch" != "$branch" ]; then
        echo "  $(basename "$dir"): trocando de '$current_branch' para '$branch'..."
        if ! git checkout "$branch" --quiet 2>/dev/null; then
            echo "  Aviso: falha ao trocar branch em $(basename "$dir")."
            cd "$old_pwd"
            return 0
        fi
        current_branch="$branch"
    fi

    if ! git fetch origin "$current_branch" --quiet 2>/dev/null; then
        echo "  Aviso: git fetch falhou em $(basename "$dir")."
        cd "$old_pwd"
        return 0
    fi

    local local_hash remote_hash
    local_hash=$(git rev-parse HEAD)
    remote_hash=$(git rev-parse "origin/$current_branch" 2>/dev/null || echo "")

    if [ -z "$remote_hash" ] || [ "$local_hash" = "$remote_hash" ]; then
        cd "$old_pwd"
        return 0
    fi

    echo "Atualizando $(basename "$dir")..."
    if ! git merge --ff-only "origin/$current_branch" --quiet 2>/dev/null; then
        if ! git pull --no-rebase origin "$current_branch" --quiet 2>/dev/null; then
            echo "  Aviso: conflitos em $(basename "$dir"). Resolva manualmente."
        fi
    fi

    cd "$old_pwd"
    return 0
}

setup_furnace_symlink() {
    local target="$LUPINHO_DIR/src/furnace"
    [ ! -d "$LUPINHO_DIR" ] && return 0
    if [ -L "$target" ]; then
        rm -f "$target"
    elif [ -d "$target" ]; then
        echo "  Aviso: $target existe como diretório real. Removendo para criar symlink."
        rm -rf "$target"
    fi
    ln -s "$FURNACE_DIR" "$target"
    echo "  Symlink: $target -> $FURNACE_DIR"
    local exclude="$LUPINHO_DIR/.git/info/exclude"
    if [ -f "$exclude" ]; then
        grep -qxF "src/furnace" "$exclude" || echo "src/furnace" >> "$exclude"
    fi
}

install_furnace() {
    git_sync_dir "$FURNACE_DIR" "https://github.com/Hirikko/furnace.git" "cli"
    if [ -d "$FURNACE_DIR/.git" ] && [ ! -f "$FURNACE_DIR/extern/fmt/include/fmt/printf.h" ]; then
        echo "  Inicializando submódulos do Furnace..."
        cd "$FURNACE_DIR"
        git submodule update --init --recursive
        cd "$SCRIPT_DIR"
    fi
    setup_furnace_symlink
}

install_wav2vgm() { git_sync_dir "$WAV2VGM_DIR" "https://github.com/Hirikko/WAV2VGM.git" "cli"; }
install_vgm2fur() { git_sync_dir "$VGM2FUR_DIR" "https://github.com/Hirikko/vgm2fur.git" "cli"; }

# --- Sincronização e Auto-Update do build-lupi ---
install_build_lupi() {
    local script_real
    script_real=$(cd "$SCRIPT_DIR" && pwd -P)
    local target_real
    if [ -d "$BUILD_LUPI_DIR" ]; then
        target_real=$(cd "$BUILD_LUPI_DIR" && pwd -P)
    else
        target_real=""
    fi

    if [ "$script_real" = "$target_real" ]; then
        echo "  build-lupi: rodando de dentro da pasta, pulando sincronização."
        return 0
    fi

    if [ ! -d "$BUILD_LUPI_DIR/.git" ]; then
        git_sync_dir "$BUILD_LUPI_DIR" "$BUILD_LUPI_URL" "main"
        return 0
    fi

    cd "$BUILD_LUPI_DIR" || return 0

    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "main")
    [ -z "$current_branch" ] && current_branch="main"

    if ! git fetch origin "$current_branch" --quiet 2>/dev/null; then
        echo "  Aviso: git fetch falhou em build-lupi."
        cd "$SCRIPT_DIR"
        return 0
    fi

    local local_hash remote_hash
    local_hash=$(git rev-parse HEAD 2>/dev/null || echo "")
    remote_hash=$(git rev-parse "origin/$current_branch" 2>/dev/null || echo "")

    if [ -z "$remote_hash" ] || [ "$local_hash" = "$remote_hash" ]; then
        cd "$SCRIPT_DIR"
        return 0
    fi

    local behind
    behind=$(git rev-list --count "HEAD..origin/$current_branch" 2>/dev/null || echo "0")
    if [ "$behind" -eq 0 ]; then
        cd "$SCRIPT_DIR"
        return 0
    fi

    echo ""
    echo "  build-lupi: $behind commit(s) novo(s) no remote (local ${local_hash:0:8} -> remote ${remote_hash:0:8})."

    local upd_mode
    upd_mode=$(select_get_update)
    if [ "$upd_mode" = "silent" ]; then
        echo "  update=silent: atualização ignorada (próximas execuções não perguntarão)."
        cd "$SCRIPT_DIR"
        return 0
    fi

    echo ""
    echo "  O que deseja fazer?"
    echo "    1) Atualizar o script agora"
    echo "    2) Não atualizar agora (me lembrar na próxima execução)"
    echo "    3) Não atualizar nunca (não me lembrar mais)"
    echo ""
    read -p "  Escolha [1/2/3]: " _upd_choice

    case "$_upd_choice" in
        1)
            echo "  Atualizando..."
            ;;
        2)
            echo "  Aviso: atualização adiada. Vou perguntar de novo na próxima execução."
            cd "$SCRIPT_DIR"
            return 0
            ;;
        3)
            select_set_update "silent"
            echo "  Aviso: atualizações silenciadas. Use '--cfg update=ask' para reativar."
            cd "$SCRIPT_DIR"
            return 0
            ;;
        *)
            echo "  Opção inválida. Seguindo sem atualizar."
            cd "$SCRIPT_DIR"
            return 0
            ;;
    esac

    local root_script="$SCRIPT_DIR/build-lupi.sh"
    local repo_script="$BUILD_LUPI_DIR/build-lupi.sh"
    local bkps_dir="$BUILD_LUPI_DIR/bkps"

    if [ -f "$root_script" ]; then
        mkdir -p "$bkps_dir"
        local ts
        ts=$(date +%Y%m%d-%H%M%S)
        cp -f "$root_script" "$bkps_dir/build-lupi-$ts.sh" 2>/dev/null && \
            echo "  Backup do script anterior: build-lupi/bkps/build-lupi-$ts.sh"
    fi

    if ! git merge --ff-only "origin/$current_branch" --quiet 2>/dev/null; then
        echo "  Aviso: fast-forward falhou, tentando pull..."
        if ! git pull --no-rebase origin "$current_branch" --quiet 2>/dev/null; then
            echo "  Aviso: conflitos em build-lupi. Resolva manualmente e rode de novo."
            cd "$SCRIPT_DIR"
            return 0
        fi
    fi

    echo "  build-lupi atualizado para $(git rev-parse --short HEAD)."

    if [ -f "$repo_script" ]; then
        cp -f "$repo_script" "$root_script"
        chmod +x "$root_script" 2>/dev/null || true
        echo "  Script da raiz substituído pela versão nova."
        echo "  (A versão nova entra em vigor na PRÓXIMA execução; esta continua com a atual.)"
    fi

    cd "$SCRIPT_DIR"
}

force_sync_demo() {
    local demo_name=$1
    local url=$2
    local dir="$DEMOS_DIR/$demo_name"

    if [ ! -d "$dir/.git" ]; then
        echo "  Clonando $demo_name..."
        rm -rf "$dir"
        git clone "$url" "$dir" --quiet || { echo "  Erro: clone falhou"; return; }
    fi

    cd "$dir"

    if ! git fetch origin --quiet 2>/dev/null; then
        echo "  Aviso: git fetch falhou em $demo_name."
        cd - >/dev/null
        return
    fi

    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "main")
    [ -z "$current_branch" ] && current_branch="main"

    local local_hash remote_hash
    local_hash=$(git rev-parse HEAD 2>/dev/null || echo "")
    remote_hash=$(git rev-parse "origin/$current_branch" 2>/dev/null || echo "")

    if [ -z "$remote_hash" ]; then
        echo "  Aviso: origin/$current_branch não existe em $demo_name."
        cd - >/dev/null
        return
    fi

    local file_count
    file_count=$(find . -mindepth 1 -maxdepth 1 -not -name ".git" | wc -l)

    if [ "$local_hash" = "$remote_hash" ] && [ "$file_count" -gt 0 ]; then
        echo "  $demo_name: já sincronizado (${local_hash:0:8})."
        cd - >/dev/null
        return
    fi

    if [ "$local_hash" = "$remote_hash" ] && [ "$file_count" -eq 0 ]; then
        echo "  $demo_name: working tree vazio, restaurando..."
        git reset --hard HEAD --quiet 2>/dev/null || true
        git checkout . --quiet 2>/dev/null || true
        cd - >/dev/null
        return
    fi

    local status_line
    status_line=$(git status -sb 2>/dev/null | head -1)
    echo "  $demo_name: desatualizado. Status: $status_line"

    if ! git pull origin "$current_branch" --quiet 2>&1; then
        git stash --include-untracked --quiet 2>/dev/null || true
        if git reset --hard "origin/$current_branch" --quiet 2>/dev/null; then
            echo "  $demo_name resetado para $(git rev-parse --short HEAD)."
        fi
    else
        echo "  $demo_name atualizado para $(git rev-parse --short HEAD)."
    fi

    cd - >/dev/null
}

sync_demo_caches() {
    force_sync_demo "caio-pernocas"     "https://github.com/Hirikko/caio-pernocas.git"
    force_sync_demo "lupinho-debug-lab" "https://github.com/Hirikko/Lupinho-Debug-Lab.git"
}

# --- Backups (por jogo, cada um com até MAX_BACKUPS) ---
MAX_BACKUPS=9

migrate_flat_backups() {
    [ ! -d "$BACKUP_DIR" ] && return 0
    local flat_count
    flat_count=$(find "$BACKUP_DIR" -maxdepth 1 -name "*.zip" -type f 2>/dev/null | wc -l)
    [ "$flat_count" -eq 0 ] && return 0

    echo "  Migrando $flat_count backup(s) antigos para subpastas por jogo..."
    for zip in "$BACKUP_DIR"/*.zip; do
        [ -f "$zip" ] || continue
        local fname game
        fname=$(basename "$zip")
        game=$(echo "$fname" | sed -E 's/-backup-[0-9]{8}-[0-9]{6}\.zip$//')
        if [ -n "$game" ] && [ "$game" != "$fname" ]; then
            mkdir -p "$BACKUP_DIR/$game"
            mv -f "$zip" "$BACKUP_DIR/$game/"
            echo "    $fname → bkp_jogos/$game/"
        fi
    done
}

cleanup_old_backups() {
    local game_label="$1"
    local game_dir="$BACKUP_DIR/$game_label"
    [ ! -d "$game_dir" ] && return 0
    local count
    count=$(find "$game_dir" -maxdepth 1 -name "*.zip" -type f 2>/dev/null | wc -l)
    while [ "$count" -ge "$MAX_BACKUPS" ]; do
        local oldest
        oldest=$(find "$game_dir" -maxdepth 1 -name "*.zip" -type f -printf "%T@ %p\n" 2>/dev/null | sort -n | head -n1 | cut -d' ' -f2-)
        [ -z "$oldest" ] && break
        echo "  Removendo backup antigo: $(basename "$oldest")"
        rm -f "$oldest"
        count=$((count - 1))
    done
}

backup_src() {
    local demo_name=$1

    local real_count=0
    if [ -d "$SDK_SRC" ]; then
        real_count=$(find "$SDK_SRC" -mindepth 1 -maxdepth 1 -not -name ".*-installed" -not -name ".git" 2>/dev/null | wc -l)
    fi
    [ "$real_count" -eq 0 ] && return 0

    local game_label="$demo_name"
    if [ -f "$SDK_SRC/lupi.yaml" ]; then
        local from_yaml
        from_yaml=$(grep -E '^name:' "$SDK_SRC/lupi.yaml" 2>/dev/null | head -n1 | sed -E 's/^name:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
        [ -n "$from_yaml" ] && game_label="$from_yaml"
    fi

    local game_dir="$BACKUP_DIR/$game_label"
    mkdir -p "$game_dir"
    cleanup_old_backups "$game_label"

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup="$game_dir/${game_label}-backup-${timestamp}.zip"

    echo "  Fazendo backup do src/ em: $backup"
    cd "$SDK_SRC"
    if zip -qr "$backup" . -x '*.git/*' '*.git' '.*-installed' 2>/dev/null; then
        local size=$(stat -c%s "$backup" 2>/dev/null || stat -f%z "$backup" 2>/dev/null || echo "?")
        echo "  Backup criado (${size} bytes)."
    else
        echo "  Aviso: falha ao criar backup."
    fi
    cd "$SCRIPT_DIR"

    get_src_content_hash > "$SRC_HASH_FILE"
}

check_src_changes_on_every_run() {
    local real_count=0
    if [ -d "$SDK_SRC" ]; then
        real_count=$(find "$SDK_SRC" -mindepth 1 -maxdepth 1 -not -name ".*-installed" -not -name ".git" 2>/dev/null | wc -l)
    fi
    [ "$real_count" -eq 0 ] && return 0

    if ! src_content_changed_since_backup; then
        return 0
    fi

    echo ""
    echo "  Mudanças detectadas em lupinho-sdk/src/ desde o último backup."
    backup_src "${GAME_SELECTION:-unknown}"
}

write_demo_marker() {
    local marker=$1
    local hash=$2
    echo "$hash" > "$marker"
}

current_game_in_src() {
    for m in "$SDK_SRC"/.*-installed; do
        [ -f "$m" ] || continue
        basename "$m" | sed -E 's/^\.(.+)-installed$/\1/'
        return
    done
    if [ -f "$SDK_SRC/main.lua" ] || [ -f "$SDK_SRC/game.lua" ] || [ -f "$SDK_SRC/lupi.yaml" ]; then
        echo "user-game"
    fi
}

# --- Seletor ---
list_demos() {
    local demos=()
    for d in "$DEMOS_DIR"/*/; do
        [ ! -d "$d" ] && continue
        local name
        name=$(basename "$d")
        [ "$name" = "caio-pernocas" ] && continue
        [ "$name" = "lupinho-debug-lab" ] && continue
        demos+=("$name")
    done
    printf "%s\n" "${demos[@]}"
}

choose_game_selection() {
    local current="(nenhum)"
    if [ -f "$SDK_SRC/.caio-pernocas-installed" ]; then
        current="Caio-Pernocas"
    elif [ -f "$SDK_SRC/.lupinho-debug-lab-installed" ]; then
        current="Lupinho Debug Lab"
    elif [ -f "$SDK_SRC/main.lua" ] || [ -f "$SDK_SRC/game.lua" ] || [ -f "$SDK_SRC/lupi.yaml" ]; then
        current="Jogo do usuário ($(basename "$SCRIPT_DIR"))"
    fi

    step " Seletor de jogo"
    echo "Jogo atual em src/: $current"
    echo "Modo de compilação atual: $(select_get_modo)"
    echo ""
    echo "Qual jogo deseja compilar?"
    echo "  1) Caio-Pernocas"
    echo "  2) Lupinho Debug Lab"
    echo "  3) Outro (pasta em: jogos-demo/)"
    echo ""

    local extras
    extras=$(list_demos)
    if [ -n "$extras" ]; then
        echo "Pastas adicionais em jogos-demo/:"
        echo "$extras" | while read -r d; do
            [ -n "$d" ] && echo "    - $d"
        done
        echo ""
    fi

    read -p "Escolha [1/2/3] ou nome da pasta em jogos-demo/: " _choice
    local chosen=""
    case "$_choice" in
        1) chosen="caio-pernocas" ;;
        2) chosen="lupinho-debug-lab" ;;
        3)
            read -p "Nome da pasta em jogos-demo/: " _custom
            _custom=$(echo "$_custom" | tr -d '[:space:]')
            if [ -z "$_custom" ] || [ ! -d "$DEMOS_DIR/$_custom" ]; then
                echo "Erro: pasta '$DEMOS_DIR/$_custom' não existe."
                exit 1
            fi
            chosen="$_custom"
            ;;
        *)
            local _custom
            _custom=$(echo "$_choice" | tr -d '[:space:]')
            if [ -n "$_custom" ] && [ -d "$DEMOS_DIR/$_custom" ]; then
                chosen="$_custom"
            else
                echo "Opção inválida: '$_choice' não corresponde a 1/2/3 nem a uma pasta em jogos-demo/."
                exit 1
            fi
            ;;
    esac
    select_set_jogo "$chosen"
    echo "  Seleção salva: $chosen (modo: $(select_get_modo))"
}

swap_src_to_demo() {
    local demo_name=$1
    local demo_src="$DEMOS_DIR/$demo_name"
    local marker="$SDK_SRC/.${demo_name}-installed"

    [ ! -d "$demo_src" ] && { echo "  Erro: cache de $demo_name ausente."; return 1; }

    local cache_hash
    cache_hash=$(get_repo_hash "$demo_src")

    if [ -f "$marker" ]; then
        local stored_hash
        stored_hash=$(head -n1 "$marker" 2>/dev/null | tr -d '[:space:]')
        if [ "$stored_hash" = "$cache_hash" ]; then
            local src_count
            src_count=$(find "$SDK_SRC" -mindepth 1 -maxdepth 1 -not -name ".*-installed" -not -name ".git" 2>/dev/null | wc -l)
            if [ "$src_count" -gt 0 ]; then
                return 1
            fi
        fi
    fi

    local current
    current=$(current_game_in_src)
    if [ -n "$current" ] && [ "$current" != "user-game" ]; then
        backup_src "$current"
    elif [ -n "$current" ] && [ "$current" = "user-game" ]; then
        read -p "  Jogo do usuário em src/. Fazer backup antes de substituir? (s/n): " _ans
        if [[ "$_ans" =~ ^[Ss]$ ]]; then
            backup_src "user-game"
        else
            echo "  Aviso: backup ignorado. O jogo atual será perdido."
        fi
    fi

    echo "  Instalando '$demo_name' em src/..."
    find "$SDK_SRC" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true

    find "$demo_src" -mindepth 1 -maxdepth 1 -not -name ".git" -exec cp -a {} "$SDK_SRC/" \;
    find "$SDK_SRC" -name ".git" -mindepth 1 -maxdepth 3 -exec rm -rf {} + 2>/dev/null || true

    rm -f "$SDK_SRC"/.*-installed
    write_demo_marker "$marker" "$cache_hash"
    echo "  '$demo_name' instalado (commit ${cache_hash:0:8})."

    get_src_content_hash > "$SRC_HASH_FILE"
    return 0
}

# --- Furnace ---
furnace_cache_is_stale() {
    local cache_file="$LUPINHO_DIR/src/music/furnace-build-web/CMakeCache.txt"
    [ ! -f "$cache_file" ] && return 1
    local cached_cc=$(grep -E '^CMAKE_C_COMPILER:FILEPATH=' "$cache_file" 2>/dev/null | cut -d= -f2-)
    [ -z "$cached_cc" ] && return 1
    local current_cc=$(command -v emcc 2>/dev/null || echo "")
    [ -z "$current_cc" ] && return 1
    [ "$cached_cc" != "$current_cc" ] && return 0
    return 1
}

check_furnace_artifacts() {
    local libfile="$LUPINHO_DIR/src/libs/web/furnace-web/libfurengine.a"
    local fur_obj="$LUPINHO_DIR/src/libs/web/furnace-web/fur_player-web.o"
    local fur_src="$LUPINHO_DIR/src/music/fur_player.cpp"
    local fmt_hdr="$FURNACE_DIR/extern/fmt/include/fmt/printf.h"

    ARTIFACTS_MISSING=0; ARTIFACTS_STALE=0
    MISSING_LIST=""; STALE_LIST=""

    [ ! -d "$FURNACE_DIR" ] && return 0
    [ ! -f "$fmt_hdr" ] && return 0

    if [ ! -f "$libfile" ]; then
        ARTIFACTS_MISSING=1; MISSING_LIST="$MISSING_LIST libfurengine.a"
    fi
    if [ ! -f "$fur_obj" ]; then
        ARTIFACTS_MISSING=1; MISSING_LIST="$MISSING_LIST fur_player-web.o"
    elif [ -f "$fur_src" ] && [ "$fur_src" -nt "$fur_obj" ]; then
        ARTIFACTS_STALE=1; STALE_LIST="$STALE_LIST fur_player-web.o"
    fi
}

compile_fur_player_obj() {
    local fur_obj="$LUPINHO_DIR/src/libs/web/furnace-web/fur_player-web.o"
    local fmt_hdr="$FURNACE_DIR/extern/fmt/include/fmt/printf.h"

    if [ ! -f "$fmt_hdr" ]; then
        echo "  Submódulos do Furnace ausentes. Inicializando..."
        cd "$FURNACE_DIR"
        git submodule update --init --recursive
        cd "$SCRIPT_DIR"
        [ ! -f "$fmt_hdr" ] && { echo "  Erro: falha ao inicializar submódulos."; return 1; }
    fi

    echo "  Compilando fur_player-web.o..."
    cd "$LUPINHO_DIR/src"
    if ! em++ -std=c++14 -DHAVE_SNDFILE \
        -I"$FURNACE_DIR/src" \
        -I"$FURNACE_DIR/src/engine" \
        -I"$FURNACE_DIR/extern/fmt/include" \
        -I"$FURNACE_DIR/extern/blip_buf" \
        -I"$FURNACE_DIR/extern/libsndfile-modified/include" \
        -I"$LUPINHO_DIR/src/libs/web/raylib-web" \
        -Wall -O2 \
        -c music/fur_player.cpp \
        -o "$fur_obj"; then
        cd "$SCRIPT_DIR"
        echo "  Erro: falha ao compilar fur_player-web.o"
        return 1
    fi
    touch "$fur_obj"
    cd "$SCRIPT_DIR"
    echo "  fur_player-web.o compilado com sucesso."
    return 0
}

check_furnace_setup() {
    if [ "$MODE" != "dev" ]; then return 0; fi

    local libfile="$LUPINHO_DIR/src/libs/web/furnace-web/libfurengine.a"
    local fur_obj="$LUPINHO_DIR/src/libs/web/furnace-web/fur_player-web.o"
    local build_cache="$LUPINHO_DIR/src/music/furnace-build-web"

    local cache_stale=0
    furnace_cache_is_stale && cache_stale=1
    check_furnace_artifacts

    if [ -d "$FURNACE_DIR" ] && [ "$ARTIFACTS_MISSING" -eq 0 ] && [ "$ARTIFACTS_STALE" -eq 0 ] && [ "$cache_stale" -eq 0 ]; then
        setup_furnace_symlink
        echo "Furnace já clonado e compilado."
        return 0
    fi

    step " Furnace: verificação de artefatos"
    [ "$cache_stale" -eq 1 ] && echo "Aviso: cache do CMake aponta para outro emcc."
    [ "$ARTIFACTS_MISSING" -eq 1 ] && {
        echo "Artefatos ausentes:"
        for f in $MISSING_LIST; do echo "  - $f"; done
    }
    [ "$ARTIFACTS_STALE" -eq 1 ] && {
        echo "Artefatos desatualizados:"
        for f in $STALE_LIST; do echo "  - $f"; done
    }

    echo "O que deseja fazer?"
    echo "  1) Clonar Furnace (sem compilar)"
    echo "  2) Clonar e compilar Furnace"
    echo "  3) Nada"
    read -p "Escolha [1/2/3]: " choice

    case "$choice" in
        1)
            install_furnace
            echo "Aviso: na próxima execução o script vai perguntar de novo."
            ;;
        2)
            install_furnace
            if [ -d "$build_cache" ]; then rm -rf "$build_cache"; fi
            [ -f "$libfile" ] && rm -f "$libfile"
            [ -f "$fur_obj" ] && rm -f "$fur_obj"

            echo "Compilando Furnace..."
            cd "$LUPINHO_DIR/src/music"
            chmod +x build_furnace.sh
            ./build_furnace.sh
            cd "$SCRIPT_DIR"

            if [ -f "$libfile" ]; then
                echo "Furnace compilado."
                compile_fur_player_obj || exit 1
            else
                echo "Aviso: libfurengine.a não gerada."
            fi
            ;;
        3|*)
            echo "Seguindo sem compilar."
            ;;
    esac
}

detect_old_build_mode() {
    if [ -f "$LUPINHO_DIR/src/main.debug.web.o" ]; then
        echo "dev"
    elif [ -f "$LUPINHO_DIR/src/main.web.o" ]; then
        echo "game"
    else
        echo ""
    fi
}

lupinho_build_usable_for_mode() {
    local dist="$LUPINHO_SITE/dist"
    [ -f "$dist/game.wasm" ] && [ -f "$dist/game.html" ] && [ -f "$dist/game.js" ] || return 1

    local built_mode=""
    [ -f "$dist/.build-mode" ] && built_mode=$(cat "$dist/.build-mode" 2>/dev/null)

    if [ "$built_mode" = "$MODE" ]; then
        return 0
    fi

    if [ -z "$built_mode" ]; then
        return 1
    fi

    if [ "$MODE" = "dev" ] && [ "$built_mode" = "game" ]; then
        return 1
    fi

    return 0
}

check_lupinho_build() {
    [ ! -d "$LUPINHO_DIR" ] && { echo "Erro: pasta 'lupinho' não encontrada."; exit 1; }

    local dist="$LUPINHO_SITE/dist"
    local fur_obj="$LUPINHO_DIR/src/libs/web/furnace-web/fur_player-web.o"
    local libfile="$LUPINHO_DIR/src/libs/web/furnace-web/libfurengine.a"

    if [ -d "$dist" ] && [ -f "$dist/game.wasm" ] && [ ! -f "$dist/.build-mode" ]; then
        local detected
        detected=$(detect_old_build_mode)
        if [ -n "$detected" ]; then
            echo "  Build antigo detectado: modo '$detected'."
            echo "$detected" > "$dist/.build-mode"
        else
            echo "  Build antigo: modo indeterminado, assumindo '$MODE'."
            echo "$MODE" > "$dist/.build-mode"
        fi
    fi

    local built_mode=""
    [ -f "$dist/.build-mode" ] && built_mode=$(cat "$dist/.build-mode" 2>/dev/null)
    [ -n "$built_mode" ] && echo "  Build atual em site/dist: $built_mode"

    local need=0 missing=""
    if [ ! -d "$dist" ]; then
        need=1; missing="(site/dist inexistente)"
    else
        [ ! -f "$dist/game.wasm" ] && missing="$missing game.wasm"
        [ ! -f "$dist/game.html" ] && missing="$missing game.html"
        [ ! -f "$dist/game.js" ]   && missing="$missing game.js"
        [ -n "$missing" ] && { need=1; echo "Arquivos ausentes em site/dist:$missing"; }
    fi

    if [ "$need" -eq 0 ] && ! lupinho_build_usable_for_mode; then
        echo "Aviso: build em '$built_mode' mas modo atual exige '$MODE'. Recompilando."
        need=1
    fi

    local obj_stale=0
    if [ "$MODE" = "dev" ]; then
        local fur_src="$LUPINHO_DIR/src/music/fur_player.cpp"
        if [ -f "$fur_obj" ] && [ -f "$fur_src" ] && [ "$fur_src" -nt "$fur_obj" ]; then
            obj_stale=1
        fi
        if [ ! -f "$libfile" ] || [ ! -f "$fur_obj" ] || [ "$obj_stale" -eq 1 ]; then
            [ "$need" -eq 0 ] && echo "Artefatos do Furnace inconsistentes. Recompilando."
            need=1
        fi
    fi

    if [ "$need" -eq 1 ]; then
        step " Lupinho: compilação necessária"
        echo "Lupinho não está compilado corretamente."

        if [ "$MODE" != "dev" ] && [ ! -f "$fur_obj" ]; then
            echo ""
            echo "ATENÇÃO: fur_player-web.o ausente em GAME mode."
            echo "  Solução: rode uma vez em DEV mode (gera o .o)."
            echo ""
        fi

        local cmd="make web"
        [ "$MODE" = "dev" ] && cmd="make debug"

        read -p "Deseja compilar o Lupinho com '$cmd'? (s/n): " ans
        [[ "$ans" =~ ^[Ss]$ ]] || { echo "Abortando."; exit 1; }

        cd "$LUPINHO_DIR"
        local make_dir=""
        [ -f "Makefile" ] && make_dir="."
        [ -z "$make_dir" ] && [ -f "src/Makefile" ] && make_dir="src"

        if [ -n "$make_dir" ]; then
            cd "$make_dir"
            if [ "$MODE" = "dev" ]; then
                if [ ! -f "$libfile" ]; then
                    echo ""
                    echo "ERRO: libfurengine.a não encontrada, mas o modo é DEV."
                    echo "O 'make debug' falharia porque a biblioteca do Furnace está ausente."
                    echo ""
                    echo "Para regenerar a biblioteca do Furnace manualmente, execute:"
                    echo "  cd $LUPINHO_DIR/src/music"
                    echo "  chmod +x build_furnace.sh"
                    echo "  ./build_furnace.sh web ../furnace ../libs/web/furnace-web"
                    echo ""
                    echo "Ou rode './build-lupi.sh' novamente e escolha a opção 2 no menu do Furnace."
                    echo ""
                    exit 1
                fi
                [ ! -f "$fur_obj" ] && { compile_fur_player_obj || exit 1; cd "$LUPINHO_DIR/$make_dir"; }
                make debug
            else
                grep -q "^web:" Makefile 2>/dev/null && make web || make
            fi
            cd "$LUPINHO_DIR"
        elif [ -f "build.sh" ]; then
            chmod +x build.sh && ./build.sh
        else
            echo "Erro: método de compilação não encontrado."; exit 1
        fi
        cd "$SCRIPT_DIR"

        if [ ! -f "$dist/game.wasm" ] || [ ! -f "$dist/game.html" ] || [ ! -f "$dist/game.js" ]; then
            echo "Erro: compilação do Lupinho falhou."; exit 1
        fi
        echo "$MODE" > "$dist/.build-mode"
        echo "Lupinho compilado com sucesso (modo: $MODE)."
    else
        echo "Lupinho já compilado (modo: $MODE, reuso do build existente)."
    fi
}

migrate_mode_to_select() {
    if [ -f "$SELECT_FILE" ] && grep -qE '^update=' "$SELECT_FILE" 2>/dev/null; then
        return 0
    fi
    if [ ! -f "$SELECT_FILE" ] && [ -f "$MODE_FILE" ]; then
        local _old
        _old=$(cat "$MODE_FILE" 2>/dev/null | tr -d '[:space:]')
        case "$_old" in
            dev)  printf "jogo=lupinho-debug-lab\nmodo=dev\nseletor=liga\nupdate=ask\n" > "$SELECT_FILE" ;;
            game) printf "jogo=caio-pernocas\nmodo=game\nseletor=liga\nupdate=ask\n" > "$SELECT_FILE" ;;
            user) printf "jogo=user\nmodo=user\nseletor=liga\nupdate=ask\n" > "$SELECT_FILE" ;;
        esac
        if [ -f "$SELECT_FILE" ]; then
            echo "  Migração: .lupi-mode ($_old) → .lupi-select (jogo=$(select_get_jogo), modo=$_old, seletor=liga, update=ask)"
            rm -f "$MODE_FILE"
        fi
    fi
}

check_dependencies() {
    local MISSING=0
    [ ! -d "$LUPINHO_DIR" ] && MISSING=1
    [ ! -d "$SDK_DIR" ] && MISSING=1
    [ ! -d "$CODEC_DIR" ] && MISSING=1

    migrate_mode_to_select
    select_migrate
    migrate_flat_backups

    local is_first_run=0

    if [ ! -f "$SELECT_FILE" ]; then
        is_first_run=1
        step " Primeira execução detectada"
        echo "Deseja baixar a versão DEV (completa) ou GAME (somente essencial)?"
        read -p "[dev/game]: " first_choice

        echo "Clonando repositórios base..."
        git_sync_dir "$LUPINHO_DIR" "https://github.com/Hirikko/lupinho.git" "dev"
        git_sync_dir "$SDK_DIR" "https://github.com/lupi-org-br/lupinho-sdk.git"
        git_sync_dir "$CODEC_DIR" "https://github.com/Hirikko/lupi-codec.git" "upgrades"
        install_build_lupi

        case "$first_choice" in
            dev)
                printf "jogo=lupinho-debug-lab\nmodo=dev\nseletor=liga\nupdate=ask\n" > "$SELECT_FILE"
                echo "  Configurado para DEV (Lupinho Debug Lab)"
                ;;
            game)
                printf "jogo=caio-pernocas\nmodo=game\nseletor=liga\nupdate=ask\n" > "$SELECT_FILE"
                echo "  Configurado para GAME (Caio-Pernocas)"
                ;;
            *)
                echo "Opção inválida. Usando 'game' como padrão."
                printf "jogo=caio-pernocas\nmodo=game\nseletor=liga\nupdate=ask\n" > "$SELECT_FILE"
                ;;
        esac
    elif [ "$MISSING" -eq 1 ]; then
        echo "Algumas dependências estão faltando (pastas deletadas)."
        echo "Clonando repositórios base..."
        git_sync_dir "$LUPINHO_DIR" "https://github.com/Hirikko/lupinho.git" "dev"
        git_sync_dir "$SDK_DIR" "https://github.com/lupi-org-br/lupinho-sdk.git"
        git_sync_dir "$CODEC_DIR" "https://github.com/Hirikko/lupi-codec.git" "upgrades"
        install_build_lupi
    fi

    local cur_seletor cur_jogo cur_modo
    cur_seletor=$(select_get_seletor)
    cur_jogo=$(select_get_jogo)
    cur_modo=$(select_get_modo)

    if [ "$is_first_run" -eq 1 ]; then
        GAME_SELECTION="$cur_jogo"
        echo "Jogo inicial selecionado: $GAME_SELECTION"
    elif [ "$FORCE_SELECT" -eq 1 ]; then
        choose_game_selection
        GAME_SELECTION=$(select_get_jogo)
        cur_modo=$(select_get_modo)
    elif [ "$cur_seletor" = "desliga" ]; then
        GAME_SELECTION="$cur_jogo"
        echo "  seletor=desliga: usando '$GAME_SELECTION' (src/ preservado)"
    elif [ -n "$CLI_GAME" ]; then
        GAME_SELECTION="$CLI_GAME"
        select_set_jogo "$GAME_SELECTION"
        cur_modo=$(select_get_modo)
        echo "  Seleção via CLI: $GAME_SELECTION"
    else
        choose_game_selection
        GAME_SELECTION=$(select_get_jogo)
        cur_modo=$(select_get_modo)
    fi

    [ -z "$GAME_SELECTION" ] && { echo "Erro: nenhum jogo selecionado."; exit 1; }

    MODE="$cur_modo"
    GAME_NAME="$GAME_SELECTION"

    if [ "$MODE" = "user" ] && [ ! -d "$DEMOS_DIR/$GAME_SELECTION" ] && [ "$GAME_SELECTION" != "caio-pernocas" ] && [ "$GAME_SELECTION" != "lupinho-debug-lab" ]; then
        echo "Seleção '$GAME_SELECTION' inválida (pasta não existe em jogos-demo/)."
        exit 1
    fi

    echo "Jogo selecionado: $GAME_SELECTION (modo: $MODE)"

    if [ "$FORCE_SELECT" -eq 1 ] && [ "$cur_seletor" = "desliga" ]; then
        echo "  Aviso: --select não altera a flag. Para trocar permanentemente, use --cfg seletor=liga."
    fi

    echo "Verificando atualizações..."

    git_sync_dir "$LUPINHO_DIR" "https://github.com/Hirikko/lupinho.git" "dev"
    git_sync_dir "$SDK_DIR" "https://github.com/lupi-org-br/lupinho-sdk.git"
    git_sync_dir "$CODEC_DIR" "https://github.com/Hirikko/lupi-codec.git" "upgrades"
    install_build_lupi
    sync_demo_caches

    if [ "$MODE" = "dev" ]; then
        install_furnace
        install_wav2vgm
        install_vgm2fur
    fi

    if [ "$cur_seletor" = "desliga" ] && [ "$FORCE_SELECT" -eq 0 ]; then
        check_src_changes_on_every_run
        echo "  src/ preservado (seletor=desliga)."
        return 0
    fi

    local current_in_src
    current_in_src=$(current_game_in_src)

    if [ "$current_in_src" = "$GAME_SELECTION" ]; then
        echo "  $GAME_SELECTION já instalado."
        check_src_changes_on_every_run
        return 0
    fi

    # Informa a troca (o backup é feito dentro de swap_src_to_demo)
    if [ -n "$current_in_src" ]; then
        echo "  Jogo atual em src/: $current_in_src → trocando para $GAME_SELECTION"
    fi

    swap_src_to_demo "$GAME_SELECTION" || true
}

# ===========================================
# Fluxo principal
# ===========================================
check_system_dependencies

step "[1/8] Verificando e atualizando repositórios..."
check_dependencies

check_furnace_setup

if [ -z "$GAME_NAME" ] && [ -f "$SDK_SRC/lupi.yaml" ]; then
    GAME_NAME=$(grep -E '^name:' "$SDK_SRC/lupi.yaml" 2>/dev/null | head -n1 | sed -E 's/^name:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
fi
if [ -z "$GAME_NAME" ]; then
    if [ -f "$SDK_SRC/.caio-pernocas-installed" ]; then GAME_NAME="caio-pernocas"
    elif [ -f "$SDK_SRC/.lupinho-debug-lab-installed" ]; then GAME_NAME="lupinho-debug-lab"
    else GAME_NAME=$(basename "$SCRIPT_DIR")
    fi
fi
echo "Nome do jogo: $GAME_NAME"

check_lupinho_build

step "[2/8] Limpando jogo..."
mkdir -p "$JOGO"
find "$JOGO" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +

step "[3/8] Copiando arquivos do SDK..."
cp -a "$SDK_SRC"/. "$JOGO"/

step "[4/8] Gerando release..."
mkdir -p "$RELEASE_DIR"
cd "$CODEC_DIR"
rm -rf "$RELEASE_DIR"
lua run.lua "$JOGO" "$RELEASE_DIR"

step "[5/8] Localizando o release gerado..."
LATEST_RELEASE=$(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %p\n" | sort -nr | head -n 1 | cut -d' ' -f2-)
[ -z "$LATEST_RELEASE" ] || [ ! -d "$LATEST_RELEASE" ] && { echo "Erro: nenhum release."; exit 1; }
echo "Release: $LATEST_RELEASE"

step "[6/8] Compactando..."
cd "$LATEST_RELEASE"
rm -f "$LUPI"
zip -qr "$LUPI" .
[ ! -f "$LUPI" ] && { echo "Erro: jogo.lupi não criado."; exit 1; }

step "[7/8] Copiando $GAME_NAME.lupi..."
rm -rf "$SCRIPT_DIR/$GAME_NAME.lupi"
mv -f "$LUPI" "$SCRIPT_DIR/$GAME_NAME.lupi"
echo "Arquivo final: $SCRIPT_DIR/$GAME_NAME.lupi"

step "[8/8] Iniciando servidor em http://localhost:8080 ..."
cd "$LUPINHO_SITE"
python3 -m http.server 8080
