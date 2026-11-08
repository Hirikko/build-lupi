#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR"
MODE_FILE="$BUILD_DIR/.lupi-mode"
DEMOS_DIR="$BUILD_DIR/jogos-demo"

MODE=""
GAME_NAME="${GAME_NAME:-}"

JOGO="$BUILD_DIR/lupi-codec/jogo"
SDK_SRC="$BUILD_DIR/lupinho-sdk/src"
CODEC_DIR="$BUILD_DIR/lupi-codec"
RELEASE_DIR="$CODEC_DIR/jogo-release"
RELEASES_DIR="$RELEASE_DIR/releases"
LUPI="$RELEASES_DIR/jogo.lupi"
LUPINHO_SITE="$BUILD_DIR/lupinho/site"

# --- Sincronização git (comportamento robusto para cache sem .git) ---
git_sync_dir() {
    local dir=$1
    local url=$2
    local branch=${3:-""}

    # Pasta existe mas sem .git: considera como cache válido, não clona
    if [ -d "$dir" ] && [ ! -d "$dir/.git" ]; then
        if [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
            echo "  $(basename "$dir") já existe (sem .git). Pulando clone."
            echo "  Para atualizar, remova a pasta e rode novamente."
            return 0
        fi
        rm -rf "$dir"
    fi

    if [ ! -d "$dir/.git" ]; then
        echo "Clonando $(basename "$dir")..."
        if [ -n "$branch" ]; then
            git clone -b "$branch" "$url" "$dir"
        else
            git clone "$url" "$dir"
        fi
        return 0
    fi

    cd "$dir"
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    git fetch origin --quiet
    local LOCAL=$(git rev-parse HEAD)
    local REMOTE=$(git rev-parse "origin/$current_branch")
    if [ "$LOCAL" != "$REMOTE" ]; then
        echo "Atualizando $(basename "$dir")..."
        git pull origin "$current_branch" --quiet || echo "Aviso: Conflitos em $(basename "$dir")."
    fi
    cd - > /dev/null
}

# --- Instalação de demo: só copia se src/ estiver livre ---
install_demo_from_cache() {
    local demo_name=$1
    local demo_src="$DEMOS_DIR/$demo_name"
    local marker="$SDK_SRC/.${demo_name}-installed"

    if [ ! -d "$demo_src" ]; then
        echo "Aviso: cache de $demo_name não encontrado em $demo_src."
        return 1
    fi

    # Já temos este demo instalado?
    if [ -f "$marker" ]; then
        echo "  $demo_name já instalado em src/."
        return 0
    fi

    # Outro demo já está em src/?
    if [ -f "$SDK_SRC/.caio-pernocas-installed" ] || [ -f "$SDK_SRC/.lupinho-debug-lab-installed" ]; then
        echo "  Outro demo já está em $SDK_SRC. Preservando."
        return 0
    fi

    # Jogo do usuário em src/? (main.lua, game.lua ou lupi.yaml)
    if [ -f "$SDK_SRC/main.lua" ] || [ -f "$SDK_SRC/game.lua" ] || [ -f "$SDK_SRC/lupi.yaml" ]; then
        echo "  Jogo do usuário detectado em $SDK_SRC (main.lua/game.lua/lupi.yaml). Preservando."
        echo "  Para instalar $demo_name, limpe os arquivos de jogo em $SDK_SRC e rode novamente."
        return 0
    fi

    echo "  Copiando $demo_name de $demo_src para $SDK_SRC..."
    for item in "$demo_src"/*; do
        [ "$(basename "$item")" = ".git" ] && continue
        cp -a "$item" "$SDK_SRC/"
    done
    touch "$marker"
    echo "  Arquivos de $demo_name copiados."
}

install_caio_pernocas() {
    echo "Sincronizando Caio-Pernocas em jogos-demo/..."
    git_sync_dir "$DEMOS_DIR/caio-pernocas" "https://github.com/Hirikko/caio-pernocas.git"
    install_demo_from_cache "caio-pernocas"
}

install_debug_lab() {
    echo "Sincronizando Lupinho Debug Lab em jogos-demo/..."
    git_sync_dir "$DEMOS_DIR/lupinho-debug-lab" "https://github.com/Hirikko/Lupinho-Debug-Lab.git"
    install_demo_from_cache "lupinho-debug-lab"
}

# Garante que o Furnace esteja clonado/compilado quando em modo DEV
check_furnace_setup() {
    if [ "$MODE" != "dev" ]; then
        return 0
    fi

    local furnace_dir="$BUILD_DIR/lupinho/src/furnace"
    local libfile="$BUILD_DIR/lupinho/src/libs/web/furnace-web/libfurengine.a"

    # Caso ideal: clonado E compilado
    if [ -d "$furnace_dir" ] && [ -f "$libfile" ]; then
        echo "Furnace já clonado e compilado (libfurengine.a presente)."
        return 0
    fi

    echo ""
    if [ -d "$furnace_dir" ] && [ ! -f "$libfile" ]; then
        echo "Furnace está clonado em lupinho/src/furnace, MAS não foi compilado."
        echo "  (libfurengine.a ausente em lupinho/src/libs/web/furnace-web/)"
    elif [ ! -d "$furnace_dir" ] && [ -f "$libfile" ]; then
        echo "Furnace não está clonado em lupinho/src/furnace, mas libfurengine.a existe."
    else
        echo "MODO DEV detectado, mas o Furnace não está clonado em lupinho/src/furnace."
    fi

    echo "O que deseja fazer?"
    echo "  1) Clonar Furnace (sem compilar)"
    echo "  2) Clonar e compilar Furnace"
    echo "  3) Nada (seguir com o que já está compilado)"
    read -p "Escolha [1/2/3]: " furnace_choice

    case "$furnace_choice" in
        1)
            if [ ! -d "$furnace_dir" ]; then
                echo "Clonando Furnace (sem compilar)..."
                git_sync_dir "$furnace_dir" "https://github.com/Hirikko/furnace.git" "cli"
            else
                echo "Furnace já clonado. Não vou compilar."
            fi
            echo "Aviso: na próxima execução, o script vai perguntar novamente (Furnace sem libfurengine.a)."
            ;;
        2)
            if [ ! -d "$furnace_dir" ]; then
                echo "Clonando Furnace..."
                git_sync_dir "$furnace_dir" "https://github.com/Hirikko/furnace.git" "cli"
            else
                echo "Furnace já clonado. Recompilando..."
            fi
            echo "Inicializando submódulos..."
            cd "$furnace_dir"
            git submodule update --init --recursive
            cd "$SCRIPT_DIR"
            echo "Compilando Furnace (build_furnace.sh)..."
            cd "$BUILD_DIR/lupinho/src/music"
            chmod +x build_furnace.sh
            ./build_furnace.sh
            cd "$SCRIPT_DIR"
            if [ -f "$libfile" ]; then
                echo "Furnace compilado com sucesso ($libfile presente)."
            else
                echo "Aviso: libfurengine.a ainda não encontrado. A compilação pode ter falhado."
                echo "Verifique os logs acima e tente novamente com a opção 2."
            fi
            ;;
        3|*)
            echo "Seguindo sem compilar Furnace."
            if [ ! -f "$libfile" ]; then
                echo "Aviso: libfurengine.a ausente — se precisar recompilar o Lupinho, o 'make debug' pode falhar no link."
            fi
            ;;
    esac
}

check_lupinho_build() {
    if [ ! -d "$BUILD_DIR/lupinho" ]; then
        echo "Erro: pasta 'lupinho' não encontrada."
        exit 1
    fi

    local dist_dir="$LUPINHO_SITE/dist"
    local need_compile=0
    local missing_files=""

    if [ ! -d "$dist_dir" ]; then
        need_compile=1
        missing_files="(pasta site/dist inexistente)"
    else
        [ ! -f "$dist_dir/game.wasm" ] && missing_files="$missing_files game.wasm"
        [ ! -f "$dist_dir/game.html" ] && missing_files="$missing_files game.html"
        [ ! -f "$dist_dir/game.js" ]   && missing_files="$missing_files game.js"
        if [ -n "$missing_files" ]; then
            need_compile=1
            echo "Arquivos ausentes em site/dist:$missing_files"
        fi
    fi

    if [ "$need_compile" -eq 1 ]; then
        echo "Lupinho não está compilado corretamente."

        local compile_cmd="make web"
        [ "$MODE" = "dev" ] && compile_cmd="make debug"

        read -p "Deseja compilar o Lupinho agora com '$compile_cmd'? (s/n): " compile_choice
        if [[ ! "$compile_choice" =~ ^[Ss]$ ]]; then
            echo "Compilação abortada. O servidor não funcionará sem o Lupinho compilado."
            exit 1
        fi

        cd "$BUILD_DIR/lupinho"
        local make_dir=""
        if [ -f "Makefile" ]; then
            make_dir="."
        elif [ -f "src/Makefile" ]; then
            make_dir="src"
        fi

        if [ -n "$make_dir" ]; then
            cd "$make_dir"
            if [ "$MODE" = "dev" ]; then
                make debug
            else
                if grep -q "^web:" Makefile 2>/dev/null; then
                    make web
                else
                    make
                fi
            fi
            cd "$BUILD_DIR/lupinho"
        elif [ -f "build.sh" ]; then
            chmod +x build.sh && ./build.sh
        elif [ -f "src/build.sh" ]; then
            cd src && chmod +x build.sh && ./build.sh && cd ..
        else
            echo "Erro: Não foi possível encontrar um método de compilação."
            exit 1
        fi
        cd "$SCRIPT_DIR"

        if [ ! -f "$dist_dir/game.wasm" ] || [ ! -f "$dist_dir/game.html" ] || [ ! -f "$dist_dir/game.js" ]; then
            echo "Erro: A compilação do Lupinho falhou."
            exit 1
        fi
        echo "Lupinho compilado com sucesso."
    else
        echo "Lupinho já compilado (game.wasm, game.html e game.js encontrados)."
    fi
}

check_dependencies() {
    local MISSING=0
    [ ! -d "$BUILD_DIR/lupinho" ] && MISSING=1
    [ ! -d "$BUILD_DIR/lupinho-sdk" ] && MISSING=1
    [ ! -d "$BUILD_DIR/lupi-codec" ] && MISSING=1

    if [ "$MISSING" -eq 1 ]; then
        echo "Algumas dependências estão faltando."
        echo "Deseja baixar a versão DEV (completa) ou GAME (somente essencial)?"
        read -p "[dev/game]: " version_choice
        case "$version_choice" in
            dev)
                echo "Baixando dependências (versão DEV)..."
                MODE="dev"
                printf "%s" "$MODE" > "$MODE_FILE"
                git_sync_dir "$BUILD_DIR/lupinho" "https://github.com/Hirikko/lupinho.git" "dev"
                git_sync_dir "$BUILD_DIR/lupinho-sdk" "https://github.com/lupi-org-br/lupinho-sdk.git"
                git_sync_dir "$BUILD_DIR/lupi-codec" "https://github.com/Hirikko/lupi-codec.git" "upgrades"

                git_sync_dir "$BUILD_DIR/lupinho/src/furnace" "https://github.com/Hirikko/furnace.git" "cli"
                git_sync_dir "$BUILD_DIR/lupi-codec/wav2vgm" "https://github.com/Hirikko/WAV2VGM.git" "cli"
                git_sync_dir "$BUILD_DIR/lupi-codec/vgm2fur" "https://github.com/Hirikko/vgm2fur.git" "cli"

                install_debug_lab
                ;;
            game)
                echo "Baixando dependências (versão GAME)..."
                MODE="game"
                printf "%s" "$MODE" > "$MODE_FILE"
                git_sync_dir "$BUILD_DIR/lupinho" "https://github.com/Hirikko/lupinho.git" "dev"
                git_sync_dir "$BUILD_DIR/lupinho-sdk" "https://github.com/lupi-org-br/lupinho-sdk.git"
                git_sync_dir "$BUILD_DIR/lupi-codec" "https://github.com/Hirikko/lupi-codec.git" "upgrades"

                install_caio_pernocas

                echo "Nota: A versão GAME não inclui as ferramentas de desenvolvimento."
                ;;
            *)
                echo "Opção inválida. Abortando."
                exit 1
                ;;
        esac
    else
        # Detecção de modo
        if [ -f "$MODE_FILE" ]; then
            MODE=$(cat "$MODE_FILE")
        elif [ -f "$SDK_SRC/.caio-pernocas-installed" ]; then
            MODE="game"
        elif [ -f "$SDK_SRC/.lupinho-debug-lab-installed" ]; then
            MODE="dev"
        elif [ -f "$SDK_SRC/main.lua" ] || [ -f "$SDK_SRC/game.lua" ] || [ -f "$SDK_SRC/lupi.yaml" ]; then
            MODE="user"
        fi

        echo "Verificando atualizações nas dependências (modo: ${MODE:-desconhecido})..."

        git_sync_dir "$BUILD_DIR/lupinho" "https://github.com/Hirikko/lupinho.git" "dev"
        git_sync_dir "$BUILD_DIR/lupinho-sdk" "https://github.com/lupi-org-br/lupinho-sdk.git"
        git_sync_dir "$BUILD_DIR/lupi-codec" "https://github.com/Hirikko/lupi-codec.git" "upgrades"

        if [ "$MODE" = "dev" ]; then
            [ -d "$BUILD_DIR/lupinho/src/furnace" ] && git_sync_dir "$BUILD_DIR/lupinho/src/furnace" "https://github.com/Hirikko/furnace.git" "cli"
            [ -d "$BUILD_DIR/lupi-codec/wav2vgm" ] && git_sync_dir "$BUILD_DIR/lupi-codec/wav2vgm" "https://github.com/Hirikko/WAV2VGM.git" "cli"
            [ -d "$BUILD_DIR/lupi-codec/vgm2fur" ] && git_sync_dir "$BUILD_DIR/lupi-codec/vgm2fur" "https://github.com/Hirikko/vgm2fur.git" "cli"
            install_debug_lab
        elif [ "$MODE" = "game" ]; then
            install_caio_pernocas
        else
            echo "Modo 'user': jogo do usuário em $SDK_SRC. Demos não serão instalados."
        fi
    fi
}

echo "[0/7] Verificando e atualizando dependências..."
check_dependencies

# Se MODE=dev mas Furnace não está clonado, pergunta o que fazer
check_furnace_setup

# Nome do jogo: prioridade GAME_NAME > lupi.yaml > marcador > pasta
if [ -z "$GAME_NAME" ] && [ -f "$SDK_SRC/lupi.yaml" ]; then
    GAME_NAME=$(grep -E '^name:' "$SDK_SRC/lupi.yaml" 2>/dev/null | head -n1 | sed -E 's/^name:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
fi
if [ -z "$GAME_NAME" ]; then
    if [ -f "$SDK_SRC/.caio-pernocas-installed" ]; then
        GAME_NAME="caio-pernocas"
    elif [ -f "$SDK_SRC/.lupinho-debug-lab-installed" ]; then
        GAME_NAME="lupinho-debug-lab"
    else
        GAME_NAME=$(basename "$SCRIPT_DIR")
    fi
fi
echo "Nome do jogo: $GAME_NAME"

check_lupinho_build

echo "[1/7] Limpando jogo..."
    mkdir -p "$JOGO"
    find "$JOGO" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +

echo "[2/7] Copiando arquivos do SDK..."
    cp -a "$SDK_SRC"/. "$JOGO"/

echo "[3/7] Gerando release..."
    mkdir -p "$RELEASE_DIR"
    cd "$CODEC_DIR"
    rm -rf "$RELEASE_DIR"
    lua run.lua "$JOGO" "$RELEASE_DIR"

echo "[4/7] Localizando o release gerado..."
    LATEST_RELEASE=$(find "$RELEASES_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -printf "%T@ %p\n" |
        sort -nr |
        head -n 1 |
        cut -d' ' -f2-)

    if [ -z "$LATEST_RELEASE" ] || [ ! -d "$LATEST_RELEASE" ]; then
        echo "Erro: nenhum release foi encontrado em:"
        echo "$RELEASES_DIR"
        exit 1
    fi

    echo "Release encontrado:"
    echo "$LATEST_RELEASE"

echo "[5/7] Compactando release..."
        cd "$LATEST_RELEASE"
        rm -f "$LUPI"
        zip -qr "$LUPI" .

    if [ ! -f "$LUPI" ]; then
        echo "Erro: jogo.lupi não foi criado."
        exit 1
    fi

    echo "Release compactado (temporário): $LUPI"

echo "[6/7] Copiando $GAME_NAME.lupi para a raiz de build..."
    rm -rf "$SCRIPT_DIR/$GAME_NAME.lupi"
    mv -f "$LUPI" "$SCRIPT_DIR/$GAME_NAME.lupi"
    echo "Arquivo final: $SCRIPT_DIR/$GAME_NAME.lupi"

echo "[7/7] Iniciando servidor Python em http://localhost:8080 ..."
    cd "$LUPINHO_SITE"
    python3 -m http.server 8080
