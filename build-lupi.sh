#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR"
MODE_FILE="$BUILD_DIR/.lupi-mode"
DEMOS_DIR="$BUILD_DIR/jogos-demo"
EMSDK_PATH_FILE="$BUILD_DIR/.emsdk-path"
EMSDK_DIR="${EMSDK_DIR:-}"

# Repositórios externos (todos no topo, sem .git aninhado)
LUPINHO_DIR="$BUILD_DIR/lupinho"
FURNACE_DIR="$BUILD_DIR/furnace"
SDK_DIR="$BUILD_DIR/lupinho-sdk"
SDK_SRC="$SDK_DIR/src"
CODEC_DIR="$BUILD_DIR/lupi-codec"
WAV2VGM_DIR="$BUILD_DIR/wav2vgm"
VGM2FUR_DIR="$BUILD_DIR/vgm2fur"

RELEASE_DIR="$CODEC_DIR/jogo-release"
RELEASES_DIR="$RELEASE_DIR/releases"
JOGO="$CODEC_DIR/jogo"
LUPI="$RELEASES_DIR/jogo.lupi"
LUPINHO_SITE="$LUPINHO_DIR/site"

MODE=""
GAME_NAME="${GAME_NAME:-}"

# --- Helpers de log ---
step() {
    echo ""
    echo "================================================="
    echo "$@"
    echo "================================================="
}

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

# --- Emscripten ---
persist_emsdk_to_rc() {
    local emsdk_path=$1
    local block_start="# >>> emsdk (build-lupi.sh) >>>"
    local block_end="# <<< emsdk (build-lupi.sh) <<<"
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ ! -f "$rc" ] && continue
        if grep -qF "$block_start" "$rc" 2>/dev/null; then
            echo "  $rc: bloco emsdk já presente."
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
    command -v emcc &>/dev/null || { echo "Erro: emcc indisponível. Rode: source $EMSDK_DIR/emsdk_env.sh"; exit 1; }
    echo "Emscripten instalado: $(emcc --version | head -n1)"

    step " Configurando ~/.bashrc e ~/.zshrc"
    persist_emsdk_to_rc "$EMSDK_DIR"
    echo "Local: $EMSDK_DIR"
    echo "Para usar em outros terminais: source ~/.zshrc (ou ~/.bashrc)"
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

# --- Hash de commit de um repo ---
get_repo_hash() {
    local dir=$1
    if [ -d "$dir/.git" ]; then
        git -C "$dir" rev-parse HEAD 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# --- git sync robusto ---
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

    if [ -z "$remote_hash" ]; then
        cd "$old_pwd"
        return 0
    fi

    if [ "$local_hash" = "$remote_hash" ]; then
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

# --- Furnace ---
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

# --- Demos em jogos-demo/ (cache) ---
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

    # Verifica se o working tree tem arquivos (além do .git)
    local file_count
    file_count=$(find . -mindepth 1 -maxdepth 1 -not -name ".git" | wc -l)

    if [ "$local_hash" = "$remote_hash" ] && [ "$file_count" -gt 0 ]; then
        echo "  $demo_name: já sincronizado (${local_hash:0:8})."
        cd - >/dev/null
        return
    fi

    if [ "$local_hash" = "$remote_hash" ] && [ "$file_count" -eq 0 ]; then
        echo "  $demo_name: working tree vazio, restaurando arquivos..."
        git reset --hard HEAD --quiet 2>/dev/null || true
        git checkout . --quiet 2>/dev/null || true
        file_count=$(find . -mindepth 1 -maxdepth 1 -not -name ".git" | wc -l)
        if [ "$file_count" -gt 0 ]; then
            echo "  $demo_name: restaurado com $file_count item(ns)."
        else
            echo "  Aviso: $demo_name continua vazio após restauração."
        fi
        cd - >/dev/null
        return
    fi

    # Hash difere → pull normal
    local status_line
    status_line=$(git status -sb 2>/dev/null | head -1)

    echo "  $demo_name: desatualizado. Status: $status_line"
    echo "  Fazendo pull de origin/$current_branch..."

    if ! git pull origin "$current_branch" --quiet 2>&1; then
        echo "  Aviso: pull falhou. Tentando stash + reset --hard..."
        git stash --include-untracked --quiet 2>/dev/null || true
        if git reset --hard "origin/$current_branch" --quiet 2>/dev/null; then
            echo "  $demo_name resetado para $(git rev-parse --short HEAD)."
        else
            echo "  Aviso: reset --hard também falhou em $demo_name."
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

backup_src() {
    local demo_name=$1
    local src_has_content=0
    if [ -d "$SDK_SRC" ]; then
        # Conta arquivos que não são marcadores (.xx-installed)
        local real_count
        real_count=$(find "$SDK_SRC" -mindepth 1 -maxdepth 1 -not -name ".*-installed" -not -name ".git" 2>/dev/null | wc -l)
        [ "$real_count" -gt 0 ] && src_has_content=1
    fi
    [ "$src_has_content" -eq 0 ] && return 0

    local game_label="$demo_name"
    if [ -f "$SDK_SRC/lupi.yaml" ]; then
        local from_yaml
        from_yaml=$(grep -E '^name:' "$SDK_SRC/lupi.yaml" 2>/dev/null | head -n1 | sed -E 's/^name:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
        [ -n "$from_yaml" ] && game_label="$from_yaml"
    fi

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup="$BUILD_DIR/${game_label}-backup-${timestamp}.zip"

    echo "  Fazendo backup do src/ atual em: $backup"
    cd "$SDK_SRC"
    if zip -qr "$backup" . -x '*.git/*' '*.git' '.*-installed' 2>/dev/null; then
        local size=$(stat -c%s "$backup" 2>/dev/null || stat -f%z "$backup" 2>/dev/null || echo "?")
        echo "  Backup criado (${size} bytes)."
    else
        echo "  Aviso: falha ao criar backup."
    fi
    cd "$SCRIPT_DIR"
}

install_demo_from_cache() {
    local demo_name=$1
    local demo_src="$DEMOS_DIR/$demo_name"
    local marker="$SDK_SRC/.${demo_name}-installed"

    [ ! -d "$demo_src" ] && { echo "  Aviso: cache de $demo_name ausente."; return 1; }

    local cache_hash
    cache_hash=$(get_repo_hash "$demo_src")

    if [ -f "$marker" ]; then
        local stored_hash
        stored_hash=$(cat "$marker" 2>/dev/null | tr -d '[:space:]' || echo "")
        if [ -n "$cache_hash" ] && [ "$stored_hash" = "$cache_hash" ]; then
            echo "  $demo_name já instalado em src/ (commit ${cache_hash:0:8})."
            return 0
        fi
        if [ -z "$cache_hash" ] && [ -z "$stored_hash" ]; then
            echo "  $demo_name já instalado em src/."
            return 0
        fi
        echo "  $demo_name: cache mudou (${stored_hash:0:8} -> ${cache_hash:0:8})."
    fi

    local other_marker=""
    if [ "$demo_name" = "caio-pernocas" ]; then
        other_marker="$SDK_SRC/.lupinho-debug-lab-installed"
    else
        other_marker="$SDK_SRC/.caio-pernocas-installed"
    fi
    if [ -f "$other_marker" ]; then
        echo "  Aviso: outro demo está instalado em src/. Preservando."
        return 0
    fi

    # Jogo do usuário? Verifica se o cache mudou para perguntar
    local user_game=0
    if [ -f "$SDK_SRC/main.lua" ] || [ -f "$SDK_SRC/game.lua" ] || [ -f "$SDK_SRC/lupi.yaml" ]; then
        user_game=1
    fi

    if [ "$user_game" -eq 1 ]; then
        if [ -f "$marker" ] && [ -n "$cache_hash" ]; then
            local stored_hash
            stored_hash=$(cat "$marker" 2>/dev/null | tr -d '[:space:]' || echo "")
            if [ -n "$stored_hash" ] && [ "$stored_hash" != "$cache_hash" ]; then
                step " Conflito: $demo_name atualizado no cache, mas src/ tem jogo do usuário"
                echo "  Cache:  ${stored_hash:0:8} -> ${cache_hash:0:8}"
                echo "  src/:   jogo do usuário detectado"
                echo ""
                echo "O que deseja fazer?"
                echo "  1) Preservar jogo do usuário (o .lupi gerado usa o jogo atual)"
                echo "  2) Backup do jogo + reinstalar $demo_name atualizado"
                echo "  3) Cancelar execução"
                read -p "Escolha [1/2/3]: " ans
                case "$ans" in
                    2)
                        backup_src "user-game"
                        echo "  Limpando src/ para reinstalar $demo_name..."
                        find "$SDK_SRC" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
                        rm -f "$marker"
                        ;;
                    3)
                        echo "Abortando."
                        exit 1
                        ;;
                    *)
                        echo "  Preservando jogo do usuário."
                        return 0
                        ;;
                esac
            else
                echo "  Jogo do usuário detectado em $SDK_SRC. Preservando."
                return 0
            fi
        else
            echo "  Jogo do usuário detectado em $SDK_SRC. Preservando."
            return 0
        fi
    fi

    # Só agora: backup + limpeza + cópia
    backup_src "$demo_name"

    if [ -f "$marker" ] || [ "$user_game" -eq 0 ]; then
        if [ -n "$(ls -A "$SDK_SRC" 2>/dev/null)" ] && [ -f "$marker" ]; then
            echo "  Limpando src/ antes de reinstalar..."
            find "$SDK_SRC" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
        fi
    fi

        # Verifica que o cache realmente tem conteúdo
    local cache_file_count
    cache_file_count=$(find "$demo_src" -mindepth 1 -maxdepth 1 -not -name ".git" 2>/dev/null | wc -l)
    if [ "$cache_file_count" -eq 0 ]; then
        echo "  Erro: cache de $demo_name está vazio (só .git). Pulando cópia."
        echo "  Tente: rm -rf $demo_src && ./build-lupi.sh"
        return 1
    fi

    echo "  Copiando $demo_name de $demo_src para $SDK_SRC..."
    find "$demo_src" -mindepth 1 -maxdepth 1 -not -name ".git" -exec cp -a {} "$SDK_SRC/" \;

    find "$SDK_SRC" -name ".git" -mindepth 1 -maxdepth 3 -exec rm -rf {} + 2>/dev/null || true

    if [ -n "$cache_hash" ]; then
        echo "$cache_hash" > "$marker"
    else
        touch "$marker"
    fi
    echo "  Arquivos de $demo_name copiados (commit ${cache_hash:0:8})."
}

# --- Análise de artefatos do Furnace ---
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

check_lupinho_build() {
    [ ! -d "$LUPINHO_DIR" ] && { echo "Erro: pasta 'lupinho' não encontrada."; exit 1; }

    local dist="$LUPINHO_SITE/dist"
    local fur_obj="$LUPINHO_DIR/src/libs/web/furnace-web/fur_player-web.o"
    local libfile="$LUPINHO_DIR/src/libs/web/furnace-web/libfurengine.a"

    local need=0 missing=""
    if [ ! -d "$dist" ]; then
        need=1; missing="(site/dist inexistente)"
    else
        [ ! -f "$dist/game.wasm" ] && missing="$missing game.wasm"
        [ ! -f "$dist/game.html" ] && missing="$missing game.html"
        [ ! -f "$dist/game.js" ]   && missing="$missing game.js"
        [ -n "$missing" ] && { need=1; echo "Arquivos ausentes em site/dist:$missing"; }
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
            echo "  Esse arquivo deveria estar commitado em lupinho/src/libs/web/furnace-web/."
            echo "  Sem ele, 'make web' falha no link."
            echo "  Solução: rode uma vez em DEV mode (gera o .o), ou"
            echo "  commite o .o de volta no repo Hirikko/lupinho:dev."
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
        echo "Lupinho compilado com sucesso."
    else
        echo "Lupinho já compilado."
    fi
}

# --- Verificação e download ---
check_dependencies() {
    local MISSING=0
    [ ! -d "$LUPINHO_DIR" ] && MISSING=1
    [ ! -d "$SDK_DIR" ] && MISSING=1
    [ ! -d "$CODEC_DIR" ] && MISSING=1

    if [ "$MISSING" -eq 1 ]; then
        step " Dependências faltando"
        echo "Deseja baixar a versão DEV (completa) ou GAME (somente essencial)?"
        read -p "[dev/game]: " vc
        case "$vc" in
            dev)
                echo "Baixando dependências (versão DEV)..."
                MODE="dev"; printf "%s" "$MODE" > "$MODE_FILE"
                git_sync_dir "$LUPINHO_DIR" "https://github.com/Hirikko/lupinho.git" "dev"
                git_sync_dir "$SDK_DIR" "https://github.com/lupi-org-br/lupinho-sdk.git"
                git_sync_dir "$CODEC_DIR" "https://github.com/Hirikko/lupi-codec.git" "upgrades"
                sync_demo_caches
                install_furnace
                install_wav2vgm
                install_vgm2fur
                install_demo_from_cache "lupinho-debug-lab"
                ;;
            game)
                echo "Baixando dependências (versão GAME)..."
                MODE="game"; printf "%s" "$MODE" > "$MODE_FILE"
                git_sync_dir "$LUPINHO_DIR" "https://github.com/Hirikko/lupinho.git" "dev"
                git_sync_dir "$SDK_DIR" "https://github.com/lupi-org-br/lupinho-sdk.git"
                git_sync_dir "$CODEC_DIR" "https://github.com/Hirikko/lupi-codec.git" "upgrades"
                sync_demo_caches
                install_demo_from_cache "caio-pernocas"
                echo "Nota: GAME não inclui ferramentas DEV (furnace, wav2vgm, vgm2fur)."
                ;;
            *) echo "Opção inválida."; exit 1 ;;
        esac
    else
        if [ -f "$MODE_FILE" ]; then MODE=$(cat "$MODE_FILE")
        elif [ -f "$SDK_SRC/.caio-pernocas-installed" ]; then MODE="game"
        elif [ -f "$SDK_SRC/.lupinho-debug-lab-installed" ]; then MODE="dev"
        elif [ -f "$SDK_SRC/main.lua" ] || [ -f "$SDK_SRC/game.lua" ] || [ -f "$SDK_SRC/lupi.yaml" ]; then MODE="user"
        fi

        echo "Verificando atualizações (modo: ${MODE:-desconhecido})..."
        git_sync_dir "$LUPINHO_DIR" "https://github.com/Hirikko/lupinho.git" "dev"
        git_sync_dir "$SDK_DIR" "https://github.com/lupi-org-br/lupinho-sdk.git"
        git_sync_dir "$CODEC_DIR" "https://github.com/Hirikko/lupi-codec.git" "upgrades"
        sync_demo_caches

        if [ "$MODE" = "dev" ]; then
            install_furnace
            install_wav2vgm
            install_vgm2fur
            install_demo_from_cache "lupinho-debug-lab"
        elif [ "$MODE" = "game" ]; then
            install_demo_from_cache "caio-pernocas"
        else
            echo "Modo 'user': demos não serão instalados em src/."
        fi
    fi
}

# ===========================================
# Fluxo principal
# ===========================================
check_system_dependencies

step "[1/8] Verificando e atualizando repositórios..."
check_dependencies

check_furnace_setup

# Nome do jogo
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
