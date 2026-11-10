
# 🎮 Build Lupi — Compilador e Empacotador de Jogos
**Automatização completa do fluxo de desenvolvimento, compilação, empacotamento e execução de jogos para o console Lupi e o simulador Lupinho.**

O `build-lupi.sh` é um script Bash que automatiza o ambiente de desenvolvimento do ecossistema Lupi.
Ele gerencia a sincronização dos repositórios, instalação de dependências, seleção de jogos, backups automáticos, integração com Furnace, compilação do Lupinho em WebAssembly (WASM) e geração do pacote final `.lupi` através do `lupi-codec`.

Ao finalizar o processo, também inicia um servidor HTTP local para executar e testar o simulador diretamente no navegador.

O objetivo é simplificar todo o processo de build, evitando configurações manuais, protegendo os projetos e reaproveitando compilações existentes sempre que possível.

---
## ✨ Funcionalidades
- **Automação de dependências:** verifica ferramentas necessárias e oferece a instalação das que estiverem ausentes.
- **Gerenciamento do Emscripten:** detecta, instala e configura automaticamente o Emscripten SDK.
- **Sincronização Git:** clona e atualiza os repositórios utilizados pelo ambiente.
- **Seletor interativo:** permite alternar entre jogos de demonstração e projetos personalizados.
- **Modo de desenvolvimento contínuo:** preserva o conteúdo de `lupinho-sdk/src/`, evitando substituições indesejadas.
- **Backups inteligentes:** detecta modificações nos arquivos do projeto através de hashes SHA-256.
- **Backups rotativos:** mantém até 9 backups independentes por jogo.
- **Integração com Furnace:** gerencia a biblioteca de áudio e os artefatos necessários para o modo DEV.
- **Build inteligente:** verifica arquivos, artefatos, modos de compilação e caches antes de recompilar.
- **Geração de releases:** utiliza o `lupi-codec` para produzir o pacote final `.lupi`.
- **Servidor local:** disponibiliza o simulador através de HTTP na porta 8080.
## 📋 Requisitos
### Sistemas operacionais
- Linux.
- macOS.
### Ferramentas necessárias

| Dependência      | Finalidade                          |
| ---------------- | ----------------------------------- |
| Bash             | Execução do script                  |
| Git              | Sincronização dos repositórios      |
| Make             | Compilação                          |
| CMake            | Configuração do Furnace             |
| Ninja            | Sistema de build                    |
| ZIP              | Empacotamento                       |
| Curl             | Transferências                      |
| Python 3         | Servidor HTTP                       |
| ImageMagick      | Processamento de imagens            |
| Lua5.5           | Execução do Lupinho Codec e lupinho |
| Emscripten SDK   | Compilação WebAssembly              |
| Emscripten C/C++ | Compilação de código C/C++          |

O Emscripten é necessário para compilar o Lupinho e seus componentes Web. O Furnace também utiliza CMake e Ninja durante sua compilação.
### Gerenciadores de pacotes suportados
**Linux:**
- APT
- DNF
- Pacman

**macOS:** (Não foi Testado)
- Homebrew

> **Observação:** o script verifica a presença do comando `lua`, mas não valida sua versão. No Linux, quando necessário, tenta instalar Lua 5.3 e seus arquivos de desenvolvimento. A versão efetivamente compatível deve atender às dependências do codec utilizado.

> **macOS:** instale Bash 4 ou superior. A versão fornecida originalmente pelo sistema pode não ser compatível com o script. Algumas operações também utilizam ferramentas e opções típicas do GNU/Linux, portanto a compatibilidade completa com macOS deve ser verificada.

---
## 🚀 Instalação
Clone o repositório:
```bash
git clone https://github.com/Hirikko/build-lupi.git
```

Entre na pasta:
```bash
cd build-lupi
```

Dê permissão de execução:
```bash
chmod +x build-lupi.sh
```

Execute:
```bash
./build-lupi.sh
```

Também é possível executar diretamente pelo Bash:
```bash
bash build-lupi.sh
```

**Importante:** não execute com `sh build-lupi.sh`, pois o script utiliza recursos específicos do Bash.
### Primeira execução
Na primeira execução, o script realiza as seguintes operações:

1. Detecta o sistema operacional e verifica as dependências.
2. Localiza ou instala o Emscripten SDK.
3. Clona os repositórios necessários.
4. Configura os componentes do ambiente.
5. Sincroniza os jogos de demonstração.
6. Cria a configuração `.lupi-select`.
7. Apresenta o seletor interativo de jogos.
8. Prepara o projeto para compilação e empacotamento.

Algumas operações solicitam confirmação do usuário, especialmente instalação de pacotes, seleção de jogos e compilação de componentes.

---
## 🎛️ Interface de linha de comando
O script possui uma CLI que permite controlar a seleção de jogos e as configurações do ambiente.

| Comando                                      | Comportamento                                    |
| -------------------------------------------- | ------------------------------------------------ |
| `./build-lupi.sh`                            | Executa o build conforme a configuração atual.   |
| `./build-lupi.sh <nome-do-jogo>`             | Seleciona diretamente um jogo e executa o build. |
| `./build-lupi.sh --select`                   | Força a abertura do seletor interativo.          |
| `./build-lupi.sh --cfg seletor=liga`         | Ativa o seletor e continua o build.              |
| `./build-lupi.sh --cfg seletor=desliga`      | Desativa o seletor e continua o build.           |
| `./build-lupi.sh --cfg-only seletor=liga`    | Ativa o seletor e encerra sem compilar.          |
| `./build-lupi.sh --cfg-only seletor=desliga` | Desativa o seletor e encerra sem compilar.       |
| `./build-lupi.sh --help`                     | Exibe a ajuda.                                   |
Também são aceitos os atalhos:
- `-s` para `--select`.
- `-h` para `--help`.
### Valores de configuração aceitos

| Ativar | Desativar |
| ------ | --------- |
| `liga` | `desliga` |
| `on`   | `off`     |
| `true` | `false`   |
| `1`    | `0`       |
### Diferença entre `--cfg` e `--cfg-only`

**`--cfg`**
Altera a configuração e continua a execução normal do script.
```bash
./build-lupi.sh --cfg seletor=liga
```

**`--cfg-only`**
Altera a configuração e encerra sem executar o processo de compilação.
```bash
./build-lupi.sh --cfg-only seletor=desliga
```

> **Atenção:** os comandos de configuração exigem que `.lupi-select` já exista. Na primeira execução, rode o script normalmente para inicializar o ambiente.

---
## ⚙️ Configuração: `.lupi-select`
O arquivo `.lupi-select`, localizado na raiz do projeto, armazena o jogo selecionado e o comportamento do seletor.

Exemplo:
```ini
jogo=caio-pernocas
seletor=liga
```
### Parâmetros

**`jogo`**
Identifica o projeto atualmente selecionado.
Exemplos:
- `caio-pernocas`
- `lupinho-debug-lab`
- `meu-jogo`

**`seletor`**
Controla o comportamento da seleção de projetos.
- `liga`: apresenta o menu interativo durante as execuções.
- `desliga`: preserva o conteúdo atual de `lupinho-sdk/src/` e utiliza o projeto existente.
### Migração automática
O script oferece compatibilidade com configurações antigas.

São reconhecidos:
- O arquivo `.lupi-mode`, que utilizava os valores `dev`, `game` e `user`.
- A flag `making_game=1` presente nos antigos marcadores de instalação.

A migração converte essas informações para o novo formato `.lupi-select`.

Quando encontra `making_game=1`, o script interpreta essa configuração como `seletor=desliga` e remove a flag antiga.

---
## 🎮 Modos de trabalho

O script identifica três tipos de seleção de projetos.
### 1. GAME — Caio-Pernocas

<badge color="success">Web</badge>
Utilizado pelo projeto `caio-pernocas`.

- Executa a compilação padrão do Lupinho.
- Utiliza `make web`, quando disponível.
- Não exige a compilação do Furnace como parte do fluxo de build GAME.
- Pode reutilizar um build DEV existente, caso os artefatos necessários estejam disponíveis.

### 2. DEV — Lupinho Debug Lab

<badge color="info">Debug</badge>

Utilizado pelo projeto `lupinho-debug-lab`.

- Executa a compilação Debug do Lupinho.
- Utiliza `make debug`.
- Gerencia a integração com Furnace.
- Verifica a biblioteca `libfurengine.a`.
- Verifica o objeto `fur_player-web.o`.
- Detecta artefatos desatualizados.
- Verifica a compatibilidade do cache CMake com o Emscripten atual.
### 3. USER — Projetos personalizados

Utilizado para qualquer outro projeto selecionado dentro de `jogos-demo/`.
O modo USER identifica o nome do projeto e utiliza seus arquivos no SDK.

Ele não representa um terceiro tipo de compilação independente: o script continua utilizando as regras de build e compatibilidade do Lupinho.

---
## 🎛️ Seletor de jogos
O seletor permite alternar entre os projetos disponíveis.

Na execução interativa, são apresentadas três opções principais:
```text
Qual jogo deseja compilar?

  1) Caio-Pernocas     (build web   — sem furnace)
  2) Lupinho Debug Lab (build debug — com furnace)
  3) Outro (pasta em jogos-demo/)
```
A terceira opção permite selecionar qualquer outra pasta existente em `jogos-demo/`.
### Seleção direta
Também é possível selecionar um projeto pelo terminal:
```bash
./build-lupi.sh meu-jogo
```
O nome deve corresponder a uma pasta existente em `jogos-demo/`.
Utilize `--cfg seletor=liga` para voltar a permitir a seleção normal.
### Forçar o seletor
Mesmo com o seletor desativado:
```bash
./build-lupi.sh --select
```

O menu será apresentado, mas a configuração permanente não será alterada.

---
## 🧑‍💻 Modo de desenvolvimento contínuo
Quando estiver desenvolvendo um jogo próprio, é recomendável utilizar:
```bash
./build-lupi.sh --cfg-only seletor=desliga
```

Nesse modo:
- O script não apresenta o seletor automaticamente.
- O conteúdo de `lupinho-sdk/src/` é preservado.
- Não substitui o projeto atual por uma demonstração.
- Verifica alterações no código-fonte.
- Cria backups automáticos quando detecta alterações desde o último backup.

Isso permite executar repetidamente o script durante o desenvolvimento sem precisar selecionar novamente o jogo.

Para voltar ao modo interativo:
```
bash
./build-lupi.sh --cfg-only seletor=liga
```

---
## 💾 Sistema de backup inteligente

O sistema de backup protege os projetos durante a troca de jogos e durante o desenvolvimento.
Os backups são organizados individualmente por projeto:
```text
bkp_jogos/
├── caio-pernocas/
│   ├── caio-pernocas-backup-20261110-101234.zip
│   └── caio-pernocas-backup-20261110-111234.zip
│
├── lupinho-debug-lab/
│   └── lupinho-debug-lab-backup-20261110-121234.zip
│
└── meu-jogo/
    └── meu-jogo-backup-20261110-131234.zip
```
### Quando os backups são criados?
O script realiza backups em diferentes situações:

1 - **Troca de jogo**
	Antes de substituir o conteúdo atual de `lupinho-sdk/src/`, o projeto anterior pode ser armazenado em um arquivo ZIP.

2 - **Projeto personalizado**
	Quando existe um jogo próprio no diretório `src/`, o script pode solicitar confirmação antes de substituí-lo.

3 - **Alterações durante o desenvolvimento**

Quando o seletor está desativado, o script calcula o hash SHA-256 do conteúdo de `src/` e compara com o último hash armazenado.
Se detectar alterações, cria automaticamente um backup antes de continuar.
### Características
- Até 8 backups por jogo.
- Rotação independente para cada projeto.
- Exclusão automática dos backups mais antigos.
- Nomes com data e horário.
- Identificação do nome do jogo pelo `lupi.yaml`, quando disponível.
- Exclusão de arquivos internos do Git e marcadores de instalação.
- Migração automática dos backups antigos.
### Detecção de alterações
O arquivo `.last-src-hash` armazena o hash do conteúdo de `lupinho-sdk/src/` registrado no último backup.

O cálculo considera os arquivos e seus conteúdos, permitindo detectar modificações mesmo quando não existe alteração no histórico Git.

> **Importante:** o backup é uma proteção adicional. Recomenda-se manter também o controle de versão dos projetos com Git.
---
## 🎵 Integração com Furnace

O Furnace é utilizado na integração de áudio do Lupinho.
No modo DEV, o script verifica se o ambiente está preparado e oferece opções para instalar e compilar os componentes necessários.
### Artefatos verificados

| Arquivo            | Finalidade                         |
| ------------------ | ---------------------------------- |
| `libfurengine.a`   | Biblioteca compilada do Furnace    |
| `fur_player-web.o` | Objeto do player de áudio para Web |
| `CMakeCache.txt`   | Configuração do build do Furnace   |
### Processo de preparação
Quando necessário, o script permite:
1. Clonar o repositório Furnace.
2. Inicializar seus submódulos Git.
3. Configurar o link simbólico dentro do Lupinho.
4. Compilar a biblioteca do Furnace.
5. Compilar o objeto `fur_player-web.o`.

O script também verifica se o código-fonte `fur_player.cpp` foi modificado depois da geração do objeto.

Isso evita reutilizar um artefato desatualizado.

---
## 🏗️ Sistema de compilação inteligente

Antes de iniciar uma compilação, o script verifica os arquivos existentes em `lupinho/site/dist/`.

Os arquivos principais esperados são:
```text
site/dist/
├── game.wasm
├── game.html
├── game.js
└── .build-mode
```

O arquivo `.build-mode` registra o modo utilizado na geração do build.
### Reaproveitamento de builds
O script tenta evitar recompilações desnecessárias.

| Transição   | Comportamento                                        |
| ----------- | ---------------------------------------------------- |
| GAME → GAME | Reutiliza se o build estiver válido                  |
| DEV → DEV   | Reutiliza se os artefatos estiverem válidos          |
| GAME → DEV  | Recompila quando o build GAME não atende ao modo DEV |
| DEV → GAME  | Pode reutilizar o build DEV existente                |
A reutilização depende da presença dos arquivos necessários e da consistência dos artefatos.

### Particularidade da integração com Furnace

No modo DEV, o script também verifica a biblioteca e o objeto do Furnace.

No modo GAME, a ausência de `fur_player-web.o` pode gerar um aviso. Caso o ambiente tenha sido instalado do zero, pode ser necessário executar uma compilação DEV primeiro para gerar esse objeto.

---
## 🚀 Fluxo de compilação

O processo principal está dividido em oito etapas.

|Etapa|Operação|
|---|---|
|0|Verificação das dependências do sistema|
|1|Sincronização dos repositórios e preparação do jogo|
|2|Limpeza do diretório de trabalho do codec|
|3|Cópia dos arquivos do SDK|
|4|Geração do release pelo `lupi-codec`|
|5|Localização do release gerado|
|6|Compactação dos arquivos|
|7|Geração do pacote final `.lupi`|
|8|Inicialização do servidor HTTP|
### Ordem de compilação no modo DEV

A preparação dos componentes de áudio segue esta sequência:

1. **Furnace:** gera a biblioteca `libfurengine.a`.
2. **Fur Player:** compila `fur_player-web.o`.
3. **Lupinho:** gera o WebAssembly utilizando `make debug`.

No modo GAME, o script utiliza a compilação Web padrão.

### Geração do arquivo `.lupi`

Depois da compilação do Lupinho, o script utiliza o `lupi-codec`:
```bash
lua run.lua jogo/ jogo-release/
```

O release gerado é compactado em formato ZIP e renomeado para:
```text
<nome-do-jogo>.lupi
```

O arquivo final fica na raiz do diretório onde o script está localizado.

---
## 🌐 Execução local

Após gerar o pacote `.lupi`, o script inicia automaticamente um servidor HTTP:
```bash
python3 -m http.server 8080
```

O servidor utiliza o diretório:
```text
lupinho/site/
```

Acesse pelo navegador:
**http://localhost:8080**
Para encerrar o servidor:
```text
Ctrl + C
```

---
## 📁 Estrutura de diretórios
A estrutura abaixo representa a organização esperada dos arquivos e repositórios após a preparação do ambiente.
```text
build-lupi/
│
├── build-lupi.sh
│
├── build-lupi/                 # Repositório do script
│
├── .lupi-select                # Configuração do seletor
├── .last-src-hash              # Hash do último backup
├── .emsdk-path                 # Caminho salvo do Emscripten
│
├── bkp_jogos/                  # Backups organizados por jogo
│   ├── caio-pernocas/
│   └── meu-jogo/
│
├── jogos-demo/                 # Cache dos projetos de demonstração
│   ├── caio-pernocas/
│   └── lupinho-debug-lab/
│
├── lupinho/                    # Simulador Lupinho
│   ├── src/
│   │   ├── music/
│   │   └── libs/web/
│   └── site/
│       └── dist/
│
├── lupinho-sdk/                # SDK de desenvolvimento
│   └── src/                    # Projeto atualmente selecionado
│
├── lupi-codec/                 # Ferramenta de empacotamento
│   ├── jogo/
│   └── jogo-release/
│       └── releases/
│
├── furnace/                    # Repositório Furnace
├── wav2vgm/                    # Conversor WAV para VGM
├── vgm2fur/                    # Conversor VGM para Furnace
│
├── emsdk/                      # Emscripten SDK (se instalado aqui)
│
└── meu-jogo.lupi               # Release final
```

Os diretórios `build-lupi/`, `emsdk/` e os arquivos auxiliares podem variar conforme a instalação e a localização do script.

O repositório `build-lupi` é sincronizado automaticamente quando o script não está sendo executado de dentro dele próprio.

---
## 🔄 Repositórios sincronizados

O ambiente utiliza os seguintes repositórios:

|Projeto|Repositório|Branch|
|---|---|---|
|Build Lupi|Hirikko/build-lupi|`main`|
|Lupinho|Hirikko/lupinho|`dev`|
|Lupinho SDK|[lupi-org-br/lupinho-sdk](https://github.com/lupi-org-br/lupinho-sdk)|Padrão|
|Lupi Codec|Hirikko/lupi-codec|`upgrades`|
|Furnace|Hirikko/furnace|`cli`|
|WAV2VGM|Hirikko/WAV2VGM|`cli`|
|vgm2fur|Hirikko/vgm2fur|`cli`|
|Emscripten SDK|emscripten-core/emsdk|`latest`|

Os projetos de demonstração também são sincronizados automaticamente:
- Caio-Pernocas
- [Lupinho Debug Lab](https://github.com/Hirikko/Lupinho-Debug-Lab)
### Estratégia de sincronização
O script verifica a branch atual, consulta o repositório remoto e tenta atualizar os projetos sem descartar alterações locais automaticamente.

Os jogos de demonstração possuem um processo específico de sincronização, que pode utilizar `stash` e `reset --hard` para restaurar o conteúdo remoto quando a atualização convencional falha.

> **Atenção:** modificações locais nos caches dos jogos de demonstração podem ser descartadas durante a sincronização. Não utilize esses diretórios como único local de armazenamento dos seus projetos.

---
## 🛠️ Solução de problemas

### Nenhum jogo selecionado

Verifique se o arquivo `.lupi-select` está correto.

Caso esteja corrompido, remova-o:
```bash
rm -f .lupi-select
```

Execute novamente:
```bash
./build-lupi.sh
```

O seletor será inicializado novamente.
### Emscripten não encontrado
Verifique se o Emscripten está instalado e se o ambiente foi carregado.

O script procura o SDK nos seguintes locais:
- Caminho definido pela variável `EMSDK_DIR`.
- Caminho salvo em `.emsdk-path`.
- Diretório `emsdk/` do projeto.
- Diretório `~/emsdk`.

Caso não encontre uma instalação válida, oferece a instalação do SDK.
### `fur_player-web.o` ausente no modo GAME
O objeto pode não existir em uma instalação nova.

Execute uma vez o build em modo DEV para preparar os componentes necessários do Furnace.
Depois, retorne ao projeto GAME.
### Furnace não compila
Verifique:
- Se os submódulos Git foram inicializados.
- Se o Emscripten está disponível.
- Se CMake e Ninja estão instalados.
- Se os artefatos antigos foram removidos quando necessário.
### Conflitos na sincronização Git
Se um repositório não conseguir atualizar, entre na pasta correspondente:
```bash
cd lupinho
```

Verifique as modificações:

```bash
git status
```
Resolva os conflitos ou preserve suas alterações antes de atualizar novamente.
**Atenção:** `git reset --hard` descarta modificações locais. Utilize somente quando tiver certeza de que não precisa preservá-las.
### Porta 8080 ocupada
O servidor utiliza a porta 8080 fixa.
Verifique se outro processo está utilizando essa porta e encerre-o antes de executar novamente.

---

## 🔗 Links úteis

### Ecossistema Lupi
- [Documentação oficial do Lupi](https://lupi.api.br/docs/index.html)
- [Lupinho — Fork de desenvolvimento](https://github.com/Hirikko/lupinho/tree/dev)
- [Lupinho oficial](https://github.com/lupi-org-br/lupinho)
- [Lupinho SDK](https://github.com/lupi-org-br/lupinho-sdk)
- [Lupi Codec — Fork upgrades](https://github.com/Hirikko/lupi-codec/tree/upgrades)
### Ferramentas e componentes
- [Furnace — Fork CLI](https://github.com/Hirikko/furnace/tree/cli)
- WAV2VGM
- vgm2fur
- Emscripten SDK
### Projetos de demonstração
- Caio-Pernocas
- [Lupinho Debug Lab](https://github.com/Hirikko/Lupinho-Debug-Lab)

---
## 📄 Licença
Consulte o arquivo `LICENSE` deste repositório para conhecer os termos de utilização, modificação e distribuição.

---
**Build Lupi** — Um único script para preparar o ambiente, selecionar projetos, compilar e empacotar jogos do ecossistema Lupi.

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