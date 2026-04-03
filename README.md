# 📺 Projeto TVBox – IFSP Salto | Multitool Fork

[![Shell Script](https://img.shields.io/badge/Shell_Script-Bash-2E7D32?logo=gnu-bash&logoColor=white&style=flat-square)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/Version-1.0.0-1565C0?style=flat-square)](https://github.com/projetotvbox/multitool/releases)
[![Views](https://hits.sh/github.com/projetotvbox/multitool.svg?style=flat-square&label=views&color=0A66C2)](https://hits.sh/github.com/projetotvbox/multitool/)

> **Language / Idioma:** [English](README.en.md) | **[🟢 Português]**

## 🏫 Sobre o Projeto

O **Projeto TVBox – IFSP Salto** é uma iniciativa de extensão do [Instituto Federal de São Paulo, Campus Salto](https://slt.ifsp.edu.br), que recebe TVBoxes apreendidas pela Receita Federal e as transforma em ferramentas de inclusão digital.

O processo envolve a **descaracterização completa** dos dispositivos — remoção do sistema proprietário e instalação de distribuições Linux adaptadas para arquitetura ARM — e sua posterior doação a escolas públicas de regiões carentes, ampliando o acesso à tecnologia para comunidades que mais precisam.

Além da descaracterização, o projeto mantém parte dos dispositivos para uso interno em pesquisa, desenvolvimento e experimentação, gerando ferramentas, sistemas operacionais customizados e documentação técnica aberta para a comunidade.

---

## 💡 Motivações deste Fork

O [Multitool original](https://github.com/paolosabatino/multitool), desenvolvido por Paolo Sabatino, é a ferramenta base utilizada para o processo de descaracterização. Este fork surgiu de duas necessidades principais:

**1. Melhorias no processo de build (`create_image.sh`)**
- Interface TUI interativa com `dialog` no lugar de saída de texto simples
- Seleção de configuração de board via menu, populado automaticamente a partir dos arquivos `.conf`
- Sistema de logging estruturado com marcadores por estágio, captura de saída de comandos e rotação automática de logs
- Gerenciamento automático de recursos via `trap`, garantindo desmontagem de loop devices e pontos de montagem em caso de falha
- Suporte a **imagem embutida**: permite selecionar um `.gz` na hora da compilação para incluí-lo diretamente na pasta de backups da imagem gerada, eliminando etapas manuais de cópia pós-gravação

**2. Funcionalidades voltadas à descaracterização em massa (`multitool.sh`)**
- **Auto-restore**: permite configurar um arquivo de backup para ser restaurado automaticamente no próximo boot, sem interação humana — ideal para operações em lote
- **Verificação de integridade adaptativa**: ao configurar o auto-restore, o sistema gera e armazena metadados de checksum (SHA256 completo para arquivos pequenos, amostras de head/mid/tail para arquivos grandes), verificados automaticamente antes de cada restore
- **Seleção automática de dispositivo**: se houver apenas um eMMC disponível, o restore é iniciado sem perguntas; se houver mais de um, o técnico escolhe manualmente para evitar gravações acidentais

---

## 🔧 O que é o Multitool?

O Multitool é um sistema Linux mínimo que roda diretamente de um cartão SD, projetado para TV boxes baseadas em chips Rockchip. Ele inicializa antes do sistema interno da box e oferece um menu interativo para operações de baixo nível sobre a memória eMMC do dispositivo.

### Funcionalidades disponíveis no menu

| Opção | Descrição |
|-------|-----------|
| Backup flash | Cria um backup comprimido (`.gz`) da eMMC para a partição MULTITOOL |
| Restore flash | Restaura um backup existente para a eMMC |
| Erase flash | Apaga o conteúdo da eMMC |
| Drop to Bash shell | Acessa um shell interativo para operações manuais |
| Burn image to flash | Grava uma imagem diretamente na eMMC (suporta `.gz`, `.zip`, `.7z`, `.tar`, `.img`) |
| Configure auto restore | Define qual backup será restaurado automaticamente no próximo boot |
| Show Current Auto-Restore | Exibe detalhes da configuração de auto-restore atual |
| Install Jump start on NAND | Instala bootloader alternativo em dispositivos com NAND (apenas rknand) |
| Install Armbian via steP-nand | Instala Armbian diretamente na NAND via steP-nand (apenas rknand) |
| Change DDR Command Rate | Altera o timing DDR para dispositivos rk322x com problemas de estabilidade |
| Reboot / Shutdown | Reinicia ou desliga o dispositivo |

---

## 🚀 Como compilar a imagem

### Pré-requisitos

Sistema baseado em Debian. Instale as dependências:

```sh
sudo apt install multistrap squashfs-tools parted dosfstools ntfs-3g dialog zenity
```

Clone o repositório:

```sh
git clone https://github.com/projetotvbox/multitool
cd multitool
```

### Compilando

```sh
sudo ./create_image.sh
```

O script apresentará:

1. **Seleção de configuração de board** — menu interativo com os arquivos disponíveis em `sources/*.conf`
2. **Imagem embutida (opcional)** — permite selecionar um `.gz` para incluir diretamente na pasta de backups da imagem gerada
3. **Auto-restore (opcional)** — se uma imagem embutida for selecionada, pergunta se deseja ativá-lo para que o restore ocorra automaticamente no primeiro boot

A imagem final é gerada em `dist-$board/multitool.img`.

> ⚠️ O script requer permissões de root, pois precisa manipular loop devices.

> 📝 Logs de build são salvos em `logs/` e rotacionados automaticamente, mantendo os 10 mais recentes.

### Gravando a imagem no cartão SD

```sh
sudo dd if=dist-$board/multitool.img of=/dev/sdX bs=4M conv=sync,fsync
```

Substitua `/dev/sdX` pelo dispositivo do seu cartão SD.

Alternativamente, utilize o [Balena Etcher](https://etcher.balena.io/) para gravar a imagem de forma gráfica e multiplataforma (Windows, macOS e Linux).

---

## 📋 Como usar o Multitool na box

### Boot

Insira o cartão SD na TV box e ligue-a. O sistema iniciará automaticamente pelo cartão e apresentará o menu principal do Multitool.

> 💡 Dependendo do modelo da box, pode ser necessário pressionar um botão de recovery durante a inicialização para forçar o boot pelo SD.

### Processo de descaracterização em lote

O fluxo recomendado para operações em massa com auto-restore pré-configurado:

1. Compile a imagem com uma imagem embutida e auto-restore habilitado
2. Grave a imagem no cartão SD
3. Insira o SD na box e ligue
4. O Multitool detecta a configuração de auto-restore, exibe uma contagem regressiva de 10 segundos e inicia o restore automaticamente
5. Ao término, oferece a opção de desligar imediatamente ou aguardar — por padrão, desliga após 10 segundos
6. Remova o cartão SD; o dispositivo está pronto

### Configurando o auto-restore manualmente

Caso a imagem não tenha sido compilada com auto-restore, é possível configurá-lo pelo menu:

1. Copie o arquivo `.gz` de backup para a pasta `backups/` da partição MULTITOOL
2. No menu, acesse **"Configure auto restore file image"**
3. Selecione o arquivo desejado
4. O sistema calculará o checksum de integridade e gravará a configuração
5. Na próxima vez que a box for ligada com o SD inserido, o restore ocorrerá automaticamente

---

## 🔗 Referências

- [Repositório original — Paolo Sabatino](https://github.com/paolosabatino/multitool)
- [Instituto Federal de São Paulo — Campus Salto](https://slt.ifsp.edu.br)

---

Feito com 🐧 no IFSP Salto · Tecnologia a serviço da educação pública