#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR"

JOGO="$BUILD_DIR/lupi-codec/jogo"
SDK_SRC="$BUILD_DIR/lupinho-sdk/src"
CODEC_DIR="$BUILD_DIR/lupi-codec"
RELEASE_DIR="$CODEC_DIR/jogo-release"
RELEASES_DIR="$RELEASE_DIR/releases"
LUPI="$RELEASES_DIR/jogo.lupi"
LUPINHO_SITE="$BUILD_DIR/lupinho/site"

echo "[1/7] Limpando jogo..."
	find "$JOGO" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +

echo "[2/7] Copiando arquivos do SDK..."
	cp -a "$SDK_SRC"/. "$JOGO"/

echo "[3/7] Gerando release..."
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

	echo "jogo.lupi criado:"
	echo "$LUPI"

echo "[6/7] Copiando jogo.lupi para a raiz de build..."
	rm -rf "$SCRIPT_DIR/jogo.lupi"
	mv -f "$LUPI" "$SCRIPT_DIR/jogo.lupi"

echo "[7/7] Iniciando servidor Python em http://localhost:8080 ..."
	cd "$LUPINHO_SITE"
	python3 -m http.server 8080
