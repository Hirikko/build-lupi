# Build Lupi
Script Bash que prepara o ambiente, sincroniza os repositórios, compila
o Lupinho, empacota o jogo e sobe um servidor local para testar.

Tudo o que você precisa para transformar seu projeto em um arquivo `.lupi`
executável no console Lupi (ou no simulador Lupinho).

---
## O que o Build Lupi faz

Em ordem, quando você roda `./build-lupi.sh`:
1. Verifica dependências do sistema e do Emscripten.
2. Sincroniza os repositórios (lupinho, lupinho-sdk, lupi-codec, furnace, etc.).
3. Escolhe (ou confirma) qual jogo será compilado.
4. Faz backup de `lupinho-sdk/src/` se o conteúdo mudou.
5. Compila o Lupinho (`make web` ou `make debug`).
6. Copia o SDK para uma pasta de trabalho.
7. Gera o release com o `lupi-codec`.
8. Compacta tudo em `<nome-do-jogo>.lupi`.
9. Sobe um servidor local em `http://localhost:8080`.

---
## Requisitos
- **Bash**
- **Linux** (suporte oficial) — macOS funciona parcialmente, veja a seção
  "Limitações conhecidas" (Não tenho como testar)
- Ferramentas do sistema: `git`, `make`, `cmake`, `ninja`, `zip`,
  `curl`, `python3`, `imagemagick`, `lua`
  - No Linux, o script instala automaticamente via `apt`, `dnf` ou `pacman`.
  - No macOS, via Homebrew.
- **Emscripten (emsdk)** — se não estiver instalado, o script oferece baixar.
---
## Primeira execução
```bash
./build-lupi.sh
```
Na primeira vez o script pergunta se você quer a versão **DEV** (completa,  
com Furnace) ou **GAME** (essencial).
A escolha define quais repositórios serão clonados.

Ao final, ele cria o arquivo `.lupi-select` com a sua configuração inicial  
e começa o build.

---
## Uso no dia a dia
```bash
./build-lupi.sh                    # fluxo normal (usa .lupi-select)
./build-lupi.sh meu-jogo           # seleção rápida por nome
./build-lupi.sh --select           # força o menu interativo
./build-lupi.sh --help             # ajuda
```
### Trocar configuração
```bash
./build-lupi.sh --cfg  seletor=desliga   # altera e continua o build
./build-lupi.sh --cfg-only modo=dev      # altera e sai (sem build)
```
### Opções aceitas por `--cfg` / `--cfg-only`

|Chave|Valores aceitos|
|---|---|
|`seletor`|`liga`, `on`, `true`, `1` / `desliga`, `off`, `false`, `0`|
|`modo`|`dev`, `game`, `user`|
|`update`|`ask`, `sim`, `perguntar` / `silent`, `nunca`, `silenciar`|

---
## O arquivo `.lupi-select`
Fica na raiz do projeto. É a configuração persistente do Build Lupi.
```ini
jogo=meu-jogo
modo=user
seletor=liga
update=ask
```

|Chave|Significado|
|---|---|
|`jogo`|Nome do projeto selecionado (pasta em `jogos-demo/` ou um dos dois oficiais).|
|`modo`|Categoria de compilação: `game`, `dev` ou `user`.|
|`seletor`|`liga` mostra o menu interativo; `desliga` pula o menu e usa o `jogo=` salvo (preserva `lupinho-sdk/src/`).|
|`update`|`ask` pergunta antes de atualizar o próprio script; `silent` nunca pergunta.|
**Migração automática:** se o seu `.lupi-select` for de uma versão antiga,  
o script adiciona as chaves faltantes sozinho na primeira execução.

---
## Modos de compilação
Existem três categorias de projeto, mas apenas **dois modos reais de  
compilação** (`make web` e `make debug`).

|Categoria|Exemplo|Compilação usada|
|---|---|---|
|`game`|Caio-Pernocas|`make web`|
|`dev`|Lupinho Debug Lab|`make debug` (exige Furnace)|
|`user`|Qualquer projeto seu|Regras do SDK (`make web`)|
**Reuso inteligente:** o Build Lupi grava o modo usado em  
`lupinho/site/dist/.build-mode` e tenta reaproveitar builds existentes.
- `game` → `game`: reaproveita.
- `dev` → `dev`: reaproveita se os artefatos do Furnace estiverem atualizados.
- `game` → `dev`: **recompila** (build `game` não serve para `dev`).
- `dev` → `game`: reaproveita (build `dev` serve para `game`).
---
## Seletor: `liga` vs `desliga`
- **`seletor=liga`** (padrão): 
	A cada execução o script mostra o menu interativo para escolher o projeto.
- **`seletor=desliga`**: 
	O script **não troca** o conteúdo de  `lupinho-sdk/src/`.
	Ele compila o que estiver lá (registrado em `jogo=`).

Esse segundo modo é ideal para **desenvolvimento contínuo**: você edita  
o código em `lupinho-sdk/src/` e roda o build quantas vezes quiser, sem  
que o script substitua seus arquivos.

---
## Estrutura de diretórios

Depois da primeira execução `dev` , você verá:
```text
build-lupi.sh              # este script
.lupi-select               # configuração persistente
.last-src-hash             # hash do conteúdo atual de lupinho-sdk/src/
.emsdk-path                # caminho do emsdk em uso (opcional)
lupinho/                   # engine + simulador
lupinho-sdk/               # SDK usado pelos jogos
lupinho-sdk/src/           # conteúdo do jogo em desenvolvimento
lupi-codec/                # gera o release .lupi
furnace/                   # biblioteca de áudio (obrigatória em DEV)
wav2vgm/                   # conversor de áudio
vgm2fur/                   # conversor de áudio
emsdk/                     # Emscripten local (se escolhido na 1ª execução)
jogos-demo/                # caches dos projetos de demonstração
bkp_jogos/                 # backups automáticos de lupinho-sdk/src/
build-lupi/                # cópia do próprio Build Lupi (para auto-update)
```
---
## Backups automáticos
A cada execução o script calcula um **hash SHA-256** do conteúdo de `lupinho-sdk/src/`. 
Se o hash mudou desde o último backup, um ZIP é criado 
antes de qualquer substituição.
- Local: 
	  `bkp_jogos/<nome-do-jogo>/`
- Nome: 
	  `<nome>-backup-AAAA-MM-DD-HHMMSS.zip`
- Limite: 
	  **8 backups** por jogo (os mais antigos são removidos).
- Identificação:
	  Usa o `name:` do `lupi.yaml`, se existir; senão o nome da pasta.
O hash do último backup fica em `.last-src-hash`.

**Quando o script troca de jogo em `src/`, ele faz backup antes de  
qualquer `rm`.** Se estiver em `seletor=desliga`, ele só faz backup se detectar mudanças reais.

---
## Sincronização Git
Na inicialização, o Build Lupi sincroniza:

|Repositório|Branch|
|---|---|
|Build Lupi|`main`|
|Lupinho|`dev`|
|Lupinho SDK|padrão|
|Lupi Codec|`upgrades`|
|Furnace|`cli`|
|WAV2VGM|`cli`|
|vgm2fur|`cli`|
|Emscripten SDK|`latest`|
**A sincronização preserva modificações locais quando possível.** 
Os casos especiais (projetos em `jogos-demo/`) podem usar `stash` +  `reset --hard` para forçar alinhamento com o remoto — esses diretórios são tratados como cache.

**Auto-update do script:** 
	Se o `build-lupi/` local estiver atrás do remoto, o script pergunta se quer atualizar (respeitando `update=ask` ou `update=silent`). 
	A versão nova entra em vigor na **próxima execução**.

---
## Furnace (obrigatório em DEV)
O modo `dev` precisa de dois artefatos:
- `lupinho/src/libs/web/furnace-web/libfurengine.a`
- `lupinho/src/libs/web/furnace-web/fur_player-web.o`
Se estiverem ausentes ou desatualizados, o script abre um menu:
1. Clonar Furnace (sem compilar).
2. Clonar e compilar Furnace.
3. Seguir sem compilar.

**Compilar Furnace pode levar vários minutos.** 
Em `game` o Furnace não  é exigido, mas se você tentar rodar `make debug` manualmente sem os  
artefatos, vai falhar.

Se o cache do CMake do Furnace apontar para um `emcc` diferente do atual, o script avisa e sugere recompilar.

---
## Empacotamento e servidor
Depois da compilação:
1. O conteúdo do SDK é copiado para `lupi-codec/jogo/`.
2. O `lupi-codec` gera o release (`lua run.lua jogo/ jogo-release/`).
3. O release mais recente é compactado em `<nome-do-jogo>.lupi`,   copiado para a raiz do projeto.
4. O servidor sobe em **`http://localhost:8080`**, servindo `lupinho/site/`.

Para encerrar o servidor: `Ctrl+C`.

---
## Arquivos de estado

|Arquivo|O que guarda|
|---|---|
|`.lupi-select`|Configuração do seletor e do modo.|
|`.last-src-hash`|Hash SHA-256 do último backup de `lupinho-sdk/src/`.|
|`.emsdk-path`|Caminho do emsdk carregado com sucesso.|
|`site/dist/.build-mode`|Modo (`dev`/`game`) do último build do Lupinho.|
|`site/dist/game.*`|Artefatos do build (`game.wasm`, `game.html`, `game.js`).|

---
## Solução de problemas
**O script pergunta toda vez qual jogo compilar.**  
Você está em `seletor=liga`.
Para escolher uma vez e não perguntar mais:  
	`./build-lupi.sh --cfg-only seletor=desliga`

**`fur_player-web.o ausente em GAME mode`.**  
O modo `game` pode usar um `.o` pré-compilado. Rode uma vez em `dev`  para gerá-lo:
 `./build-lupi.sh --cfg-only modo=dev` e depois  
`./build-lupi.sh`.

**`libfurengine.a não encontrada, mas o modo é DEV`.**  
Compile o Furnace primeiro. 
No menu do Build Lupi, escolha a opção 2  (clonar e compilar).

**Compilação do Lupinho falhou.**  
Verifique se `emsdk` está ativo (`emcc --version`). 
Se necessário, rode `./build-lupi.sh` de novo — o script reinstala Emscripten.

**Conflitos no `git pull`.**  
Resolva manualmente na pasta indicada e rode de novo. O Build Lupi  **não** força `reset --hard` em `lupinho/` nem nos SDKs.

**Perdi um jogo que estava em `lupinho-sdk/src/`.**  
Verifique `bkp_jogos/<nome>/`. 
Se não houver backup, o conteúdo não estava protegido no momento da substituição.

---
## Limitações conhecidas (Eu não tenho certeza dessa parte, não tenho como testar)
- **macOS:** o script aceita `darwin` e instala dependências via  
    Homebrew, mas usa ferramentas GNU (`find -printf`, `sha256sum`,  
    `sort -z`, `xargs -r`, `sed -i` sem sufixo) que **não** existem  
    por padrão no BSD do macOS. Se você usa macOS, instale  
    `coreutils` e `findutils` via brew e ajuste o `PATH`.
- **Requisitos de build do Furnace** podem variar conforme o estado do  
    repositório upstream. Se a compilação falhar, verifique  
    `furnace/README` no repositório clonado.
---
## Resumo dos comandos
# Fluxo normal
./build-lupi.sh
# Selecionar projeto direto (respeita seletor)
./build-lupi.sh meu-jogo
# Forçar menu interativo
./build-lupi.sh --select
# Alterar configuração e continuar
./build-lupi.sh --cfg seletor=liga
./build-lupi.sh --cfg modo=dev
./build-lupi.sh --cfg update=silent
# Alterar configuração e sair (sem build)
./build-lupi.sh --cfg-only seletor=desliga
# Ajuda
./build-lupi.sh --help

---
