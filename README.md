# build-lupi.sh — Compilador e Empacotador de Jogos Lupi
Script Bash que automatiza o fluxo completo de compilação, empacotamento e execução de jogos para o console **Lupi** e o simulador **Lupinho**. 
Cuida da sincronização dos repositórios, compilação do Furnace e do Lupinho (WASM), geração do release via `lupi-codec`, e serve o jogo em `http://localhost:8080`.

---
## 📋 Requisitos
- **Bash** 4.0+ (use `./build-lupi.sh` ou `bash build-lupi.sh`, **não** `sh build-lupi.sh`)
- **Git** (para sincronização dos repositórios)
- **Lua 5.5+** (para o `lupi-codec`)
- **ImageMagick** (`magick` no `PATH`)
- **zip**, **curl**, **python3**
- **Emscripten SDK** (`emsdk`) no `PATH` — necessário apenas para compilar o Lupinho/Furnace
- **cmake**, **ninja** — para compilar o Furnace em modo DEV
---
## 📁 Estrutura de Pastas
Após a primeira execução, o script organiza os arquivos assim:
````
raiz-do-projeto/
├── build-lupi.sh
├── .lupi-mode ← persiste a escolha DEV/GAME (criado automaticamente)
├── jogos-demo/ ← cache dos jogos demo (clonados via git)
│ ├── caio-pernocas/ (modo GAME)
│ └── lupinho-debug-lab/ (modo DEV)
├── lupinho/ ← simulador (fork: Hirikko/lupinho:dev)
│ ├── src/
│ │ ├── furnace/ ← tracker (fork: Hirikko/furnace:cli) — só DEV
│ │ ├── music/
│ │ │ └── build_furnace.sh
│ │ └── libs/web/furnace-web/
│ │ └── libfurengine.a ← gerado após compilar o Furnace
│ └── site/
│ └── dist/ ← game.wasm, game.html, game.js (saída da compilação do lupinho)
├── lupinho-sdk/ ← SDK com template de jogo
│ └── src/ ← jogo do usuário ou demo copiado
│ ├── game.lua ou main.lua
│ ├── lupi.yaml ← metadados do jogo (obrigatório)
│ └── ...
├── lupi-codec/ ← codec de empacotamento (fork: Hirikko/lupi-codec:upgrades)
│ ├── wav2vgm/ ← só DEV
│ ├── vgm2fur/ ← só DEV
│ └── jogo-release/
│ └── releases/
│ ├── <timestamp>/ ← releases versionados
│ └── jogo.lupi ← arquivo compactado (temporário)
├── lupinho-debug-lab.lupi ← release do demo (só DEV)
├── caio-pernocas.lupi ← release do demo (só GAME)
└── <nome-do-jogo>.lupi ← release final do jogo atual
````
---
## 🎮 Modos de Uso
O script opera em três modos, detectados automaticamente:

| Modo | Quando é usado | O que faz |
| :--- | :--- | :--- |
| **`dev`** | Primeira execução escolhendo `dev` ou `.lupi-mode` = `dev` | Instala Debug Lab + furnace + wav2vgm + vgm2fur. Compila o Lupinho em modo `debug` (com painel de hardware). |
| **`game`** | Primeira execução escolhendo `game` ou `.lupi-mode` = `game` | Instala Caio-Pernocas como jogo de exemplo. Compila o Lupinho em modo `web` (build de produção). |
| **`user`** | `lupinho-sdk/src/` já tem `main.lua`/`game.lua`/`lupi.yaml` e não há marcador de demo | Usa o jogo do usuário sem sobrescrever nada. Modo automático para desenvolvimento próprio. |

A escolha fica persistida em `.lupi-mode` na raiz. Para trocar, remova o arquivo (ou edite) e rode novamente.

---
## 🚀 Primeira Execução

```bash
./build-lupi.sh
```
O script vai:
1. Detectar que faltam dependências e perguntar: [dev/game]
2. Clonar os repositórios correspondentes via git
3. Clonar o demo correspondente em jogos-demo/ (cache) e copiar para lupinho-sdk/src/
4. Perguntar se deseja compilar o Lupinho (e o Furnace, se DEV)
5. Gerar o release via lupi-codec
6. Compactar o .lupi com o nome correto
7. Iniciar o servidor em http://localhost:8080
## Exemplo (modo DEV)
```text
Algumas dependências estão faltando.
Deseja baixar a versão DEV (completa) ou GAME (somente essencial)?
[dev/game]: dev
Clonando lupinho...
Clonando lupinho-sdk...
Clonando lupi-codec...
Clonando furnace...
Clonando wav2vgm...
Clonando vgm2fur...
Clonando lupinho-debug-lab...
Arquivos de lupinho-debug-lab copiados para .../lupinho-sdk/src
Nome do jogo: lupinho-debug-lab
Arquivos ausentes em site/dist: game.wasm game.html game.js
Deseja compilar agora: Furnace (build_furnace.sh) e depois Lupinho (make debug)? (s/n): s
...
Lupinho compilado com sucesso.
[1/7] ... [7/7] Servidor em http://localhost:8080
```
## 🔄 Execuções Subsequentes
```bash
./build-lupi.sh
```
O script vai:
1. Verificar atualizações nas dependências via `git fetch`/`pull` (só puxa objetos se houver commits novos)
2. **Preservar** o jogo em `lupinho-sdk/src/` se houver `main.lua`/`game.lua`/`lupi.yaml`
3. Pular compilação se `site/dist/game.wasm`, `game.html` e `game.js` já existirem
4. Em DEV, verificar se o Furnace está compilado (`libfurengine.a`); se não estiver, perguntar
5. Gerar o release e subir webserver local de python3 em `http://localhost:8080`
### Exemplo (modo USER)
```text
Verificando atualizações nas dependências (modo: user)...
Jogo do usuário detectado em .../lupinho-sdk/src. Preservando.
Furnace já clonado e compilado (libfurengine.a presente).
Nome do jogo: sonic-1-sms
Lupinho já compilado (game.wasm, game.html e game.js encontrados).
...
Arquivo final: /home/.../sonic-1-sms.lupi
```
---
## 🎨 Detecção do Nome do Jogo
O nome do `.lupi` final segue esta ordem de prioridade:
1. **Variável de ambiente** `GAME_NAME` (override manual)
2. **`lupi.yaml`** em `lupinho-sdk/src/` — campo `name:` normalizado
3. **Marcador** do demo (`.caio-pernocas-installed` → `caio-pernocas`, `.lupinho-debug-lab-installed` → `lupinho-debug-lab`)
4. **Nome da pasta** onde está o `build-lupi.sh` (fallback)
Exemplo de `lupi.yaml`:
```yaml
name: Sonic 1 SMS
public: true
version: 1.0
```
Vira `sonic-1-sms.lupi` (minúsculas, espaços → hífen, apenas `a-z0-9-`).
Para sobrescrever manualmente:
```bash
GAME_NAME=sonic-1-sms-dev ./build-lupi.sh
```
---
## 🔥 Compilação do Furnace (modo DEV)
O Furnace é compilado uma única vez, gerando `libfurengine.a` em `lupinho/src/libs/web/furnace-web/`.
O script verifica:

|Estado|Comportamento|
|---|---|
|Pasta + `libfurengine.a`|Silencioso, segue o fluxo|
|Pasta clonada mas sem `lib`|Pergunta `[1/2/3]` a cada execução|
|Sem pasta e sem `lib`|Pergunta `[1/2/3]`|
Menu de escolha:
```text
O que deseja fazer?
  1) Clonar Furnace (sem compilar)
  2) Clonar e compilar Furnace
  3) Nada (seguir com o que já está compilado)
```
- **Opção 1**: clona se necessário, mas não compila. Na próxima execução, o script vai perguntar de novo.
- **Opção 2**: clona, inicializa submódulos e executa `build_furnace.sh`.
- **Opção 3**: segue sem mexer. Se `lib` não existir, avisa que recompilar o Lupinho pode falhar no link.
### Forçar recompilação manual
```bash
rm lupinho/src/libs/web/furnace-web/libfurengine.a
./build-lupi.sh
```
Na próxima execução, o script detecta a ausência e oferece recompilar.

---
## 🧱 Compilação do Lupinho (WASM)
Verificados três arquivos em `lupinho/site/dist/`:
- `game.wasm`
- `game.html`
- `game.js`
Se algum faltar, o script pergunta se deseja compilar:
- **`make web`** (modo GAME e USER)
- **`make debug`** (modo DEV — inclui painel `LUPI HARDWARE DEBUG`)

O `Makefile` é procurado em em `lupinho/src/`.

---
## 🎯 Trabalhando com um Jogo Próprio
### Início rápido
1. Coloque os arquivos do seu jogo em `lupinho-sdk/src/` (deve ter `main.lua`, `game.lua` ou `lupi.yaml`)
2. Crie `lupinho-sdk/src/lupi.yaml`:
```yaml 
name: Meu Jogo
public: false
version: 1.0
```
3. Rode `./build-lupi.sh`
4. O resultado será `meu-jogo.lupi` na raiz
### Trocar para um demo
Para instalar o demo DEV (Debug Lab) ou GAME (Caio-Pernocas), o `src/` precisa estar "limpo" (sem `main.lua`/`game.lua`/`lupi.yaml`):
```bash
rm -rf lupinho-sdk/src/*
echo "dev" > .lupi-mode   # ou "game"
./build-lupi.sh
```
Na próxima execução, o script vai copiar o demo do cache `jogos-demo/` para `src/`.
### Trocar de demo (DEBUG ↔ GAME)
```bash
# Remove marcador e conteúdo
rm -rf lupinho-sdk/src/*
echo "game" > .lupi-mode
./build-lupi.sh
```
Se `jogos-demo/caio-pernocas/` já existir no cache, é copiado direto, sem novo clone.

---
## 📦 Cache de Demos (`jogos-demo/`)
Os demos clonados ficam em `jogos-demo/` (fora do `lupinho-sdk/src/`). Isso permite:
- Manter múltiplos demos no cache
- Trocar entre eles sem clonar de novo
- Preservar jogos do usuário sem sobrescrever
### Atualizar um demo
```bash
rm -rf jogos-demo/lupinho-debug-lab
./build-lupi.sh
```
### Limpar todo o cache
```bash
rm -rf jogos-demo/
```
Adicione `jogos-demo/` ao `.gitignore` do seu projeto.

---
## 🔀 Trocar de Modo (DEV ↔ GAME)
O modo fica gravado em `.lupi-mode`:
```bash
cat .lupi-mode    # mostra "dev" ou "game"
```
Para trocar:
```bash
# Exemplo: migrar de GAME para DEV
echo "dev" > .lupi-mode
rm -rf lupinho-sdk/src/*       # remove o Caio-Pernocas
rm -rf lupinho/site/dist       # força recompilar (opcional)
./build-lupi.sh
```
O script vai detectar o novo modo e instalar o demo correspondente, perguntar sobre o Furnace, e recompilar com `make debug`.

---
## 🔄 Atualizar Dependências
O script faz `git fetch` + `git pull` automaticamente quando há commits novos.
Para forçar a atualização de um repositório específico:
```bash
cd lupinho && git pull origin dev && cd ..
cd lupinho-sdk && git pull origin main && cd ..
cd lupi-codec && git pull origin upgrades && cd ..
```
Para recompilar após atualização:
```bash
rm -rf lupinho/site/dist
./build-lupi.sh
```
---
## 🔧 Variáveis de Ambiente

| Variável    | Descrição                           | Padrão                      |
| ----------- | ----------------------------------- | --------------------------- |
| `GAME_NAME` | Sobrescreve o nome do `.lupi` final | Detectado (ver seção acima) |
Exemplo:
```bash
GAME_NAME=sonic-1-sms-nightly ./build-lupi.sh
```
---
## 🐛 Troubleshooting
### "Compilação abortada. O servidor não funcionará sem o Lupinho compilado."
Você respondeu `n` à pergunta de compilação, mas `site/dist/` está vazio. Rode novamente e responda `s`.
### "libfurengine.a ausente — se precisar recompilar o Lupinho, o 'make debug' pode falhar no link."
Você escolheu clonar o Furnace sem compilar. Para resolver:
```bash
./build-lupi.sh
# escolha 2) Clonar e compilar
```
### "Erro: A compilação do Lupinho falhou (game.wasm/game.html/game.js ainda ausentes)."
Verifique os logs do `make` acima. Causas comuns:
- `emsdk` não está no `PATH` → `source ~/emsdk/emsdk_env.sh`
- `libfurengine.a` ausente → recompile o Furnace
- Ferramentas do sistema faltando (`cmake`, `ninja`)
### "Outro demo já está em ... Preservando."
Você tentou instalar DEV mas o GAME já está em `src/`. Para forçar a troca:
```
bash
rm -rf lupinho-sdk/src/*
echo "dev" > .lupi-mode
./build-lupi.sh
```
### Erro de permissão em `.git/objects/pack/*`
Resquício de versões antigas do script. Limpe o cache:
```bash
rm -rf jogos-demo/
./build-lupi.sh
```
### Nome do `.lupi` saiu errado (ex.: `teste.lupi`)
Falta `lupi.yaml` em `lupinho-sdk/src/` ou `GAME_NAME` não foi exportado. Crie o `lupi.yaml` ou rode:
```
bash
GAME_NAME=meu-jogo ./build-lupi.sh
```
---
## 📝 Notas
- O script **nunca** sobrescreve `lupinho-sdk/src/` se detectar `main.lua`, `game.lua` ou `lupi.yaml` (a menos que você peça explicitamente via `rm -rf`).
- O cache `jogos-demo/` **não** é removido automaticamente — você controla quando limpar.
- Releases antigos em `lupi-codec/jogo-release/releases/` **não** são removidos (o `lupi-codec` mantém histórico por timestamp).
- O `.lupi` final fica sempre na raiz, com nome detectado (não sobrescreve o `jogo.lupi` interno do codec).
---
## 🔗 Links Úteis
- [Lupinho (fork dev)](https://github.com/Hirikko/lupinho/tree/dev)
- [Lupinho oficial](https://github.com/lupi-org-br/lupinho)
- [Lupinho SDK](https://github.com/lupi-org-br/lupinho-sdk)
- [Lupi Codec (fork upgrades)](https://github.com/Hirikko/lupi-codec/tree/upgrades)
- [Furnace (fork cli)](https://github.com/Hirikko/furnace/tree/cli)
- [WAV2VGM (fork cli)](https://github.com/Hirikko/WAV2VGM/tree/cli)
- [vgm2fur (fork cli)](https://github.com/Hirikko/vgm2fur/tree/cli)
- [Lupinho Debug Lab](https://github.com/Hirikko/Lupinho-Debug-Lab)
- [Caio-Pernocas (demo)](https://github.com/Hirikko/caio-pernocas)
- [Documentação do Lupi](https://lupi.api.br/docs/index.html)