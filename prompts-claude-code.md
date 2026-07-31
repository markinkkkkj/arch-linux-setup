# Prompts para o Claude Code — `install.sh` do Arch + Sway

Repositório único contendo o provisionador **e** os dotfiles. Execução exclusivamente
por clone (sem `curl | bash`).

Sequência de 10 prompts. **Rode um por vez**, revise o resultado, faça commit, só então
passe para o próximo. Um prompt gigante produz código genérico e difícil de auditar.

---

## Preparação (antes do primeiro prompt)

Estrutura sugerida do repositório:

```
meu-setup/
├── install.sh              # provisionador
├── dotfiles.sh             # gestão do stow (Prompt 5)
├── CLAUDE.md               # criado pelo Prompt 0
├── README.md               # criado pelo Prompt 9
├── .gitignore              # criado pelo Prompt 6
├── docs/
│   └── relato.txt          # auditoria de hardware da máquina real
├── pkgs/                   # opcional: listas de pacotes em texto
│   ├── 00-base.txt
│   └── ...
├── dotfiles/               # raiz do stow
│   ├── sway/.config/sway/config
│   ├── waybar/.config/waybar/...
│   ├── foot/.config/foot/...
│   └── ...
└── files/                  # arquivos avulsos (snippets, unidades systemd)
```

O `docs/relato.txt` é o item mais importante: é a fonte de verdade sobre o seu hardware.
Sem ele, o Claude Code trabalha com suposições genéricas de internet.

Separar `dotfiles/` como raiz do stow (em vez de espalhar as pastas stow na raiz do
repositório) evita que o stow tente criar link para `install.sh`, `.git`, `README.md`
e afins.

---

## Prompt 0 — Contexto do projeto (gera o `CLAUDE.md`)

> Estou construindo um repositório que contém, ao mesmo tempo, um script de
> provisionamento da minha máquina Arch Linux e os meus dotfiles. Leia o `install.sh`
> atual e o `docs/relato.txt` (auditoria de hardware da máquina real).
>
> Crie um arquivo `CLAUDE.md` na raiz consolidando o contexto do projeto. Deve conter:
>
> **Hardware alvo:** ThinkPad T14 Gen 1, modelo 20S1002LBR (variante brasileira, teclado
> ABNT2). Intel i7-10610U (Comet Lake), gráficos Intel UHD via driver `i915`, Wi-Fi Intel
> AX201 via `iwlwifi`, Ethernet `e1000e`, áudio Intel SOF (`sof-hda-dsp`) com codec ALC257,
> webcam integrada funcionando via v4l2.
>
> **Particionamento (CRÍTICO):** a máquina é triple boot — Windows (NTFS), Arch Linux
> (ext4, raiz), macOS (APFS). A partição EFI de 1 GB montada em `/boot` é COMPARTILHADA
> entre o bootloader do Windows, o do Linux e o OpenCore do hackintosh.
>
> **Ambiente:** Sway (Wayland), iniciado manualmente a partir do TTY. Terminal `foot`,
> barra `waybar`, launcher `wofi`, navegador Zen Browser, editor VS Code. AUR via `yay`.
> Dotfiles gerenciados com GNU Stow, com `dotfiles/` como raiz do stow. Locale
> `en_US.UTF-8`. zram de 4 GB já configurado.
>
> **Modelo de execução:** o script roda EXCLUSIVAMENTE a partir do repositório clonado
> (`git clone && cd && ./install.sh`). Não há suporte a `curl | bash`, então entrada
> interativa via `read` é permitida normalmente — stdin é um terminal de verdade.
>
> **Uso:** desenvolvimento de software, com interesse em Flutter.
>
> **Regras invioláveis para qualquer código gerado neste projeto:**
> 1. NUNCA escrever, mover, apagar ou reformatar nada dentro de `/boot` — é a ESP
>    compartilhada; um erro ali quebra o boot dos três sistemas operacionais.
> 2. NUNCA modificar tabela de partições, rodar `mkfs`, `fdisk`, `parted` ou `dd`.
> 3. NUNCA executar o `install.sh` nesta máquina para testar. Testes só em container.
> 4. Todo `rm -rf` deve ter o caminho validado como não-vazio antes.
> 5. Nunca habilitar `tlp` e `power-profiles-daemon` juntos — eles conflitam.
> 6. O script roda como usuário normal e escala com `sudo` pontualmente; nunca como root.
> 7. NUNCA versionar segredo neste repositório: chave privada, token, senha, cookie de
>    sessão. Ao adicionar qualquer dotfile novo, verificar antes se ele carrega credencial.
>
> Não altere o `install.sh` ainda. Só crie o `CLAUDE.md`.

---

## Prompt 1 — Endurecer o esqueleto

> Refatore o `install.sh` mantendo a estrutura de funções `check_*` que já existe, mas
> corrigindo os problemas abaixo. Não adicione pacotes novos ainda — só a infraestrutura.
>
> **Correções de robustez:**
> - Trocar `set -e` por `set -euo pipefail`.
> - Adicionar `trap` de erro que reporta comando e número da linha, e `trap` de saída
>   que faz limpeza.
> - `sudo -v` expira em ~15 minutos. Adicionar um keep-alive em background que renova
>   o timestamp, e matá-lo no trap de saída.
> - `check_internet` usa `ping`, que falha em rede que bloqueia ICMP. Trocar por uma
>   requisição HTTPS a `https://archlinux.org`.
> - `check_disk_space` mede `/`, mas o cache do pacman fica em `/var/cache/pacman/pkg`.
>   Medir o filesystem que realmente contém esse caminho. Elevar o mínimo para 15 GB.
> - `check_yay` clona no diretório atual e usa `cd ../`. Trocar por diretório temporário
>   via `mktemp -d`, com remoção garantida por trap, usando `pushd`/`popd`.
> - `base-devel` não inclui `git`, mas `check_yay` depende dele. Garantir `git` instalado
>   antes de qualquer clone.
> - Adicionar `sudo pacman -Syu` antes de qualquer instalação, para evitar partial upgrade.
>
> **Consciência de repositório (o script só roda clonado):**
> - Resolver o diretório do próprio script de forma confiável, seguindo symlink, e usar
>   isso como raiz para todo caminho relativo. Nunca depender do diretório de trabalho
>   atual: preciso poder rodar `./install.sh` de qualquer lugar.
> - Adicionar uma verificação `check_repo` que aborta com mensagem clara se o script não
>   estiver dentro do repositório esperado (por exemplo, se `dotfiles/` e `docs/` não
>   existirem ao lado dele). Isso evita execução de uma cópia solta e órfã.
> - Registrar no log o commit atual (`git rev-parse --short HEAD`) e avisar se a árvore
>   de trabalho estiver suja, para eu sempre saber qual versão gerou aquele estado.
>
> **Instalação tolerante a falha:**
> Criar uma função `install_pkgs` que recebe um array e tenta instalar tudo de uma vez.
> Se falhar (um único nome errado hoje derruba o array inteiro), cai num loop
> pacote-a-pacote, acumula os que falharam num array global, e continua. No fim da
> execução, imprimir o resumo dos que não instalaram.
>
> **Flags de linha de comando:**
> `--dry-run` (mostra o que faria sem executar), `--only=<grupo>`, `--skip=<grupo>`,
> `--yes` (não interativo), `--help`.
>
> **Log:** duplicar toda a saída para `~/arch-setup-AAAAMMDD-HHMMSS.log` mantendo as
> cores no terminal mas sem códigos ANSI no arquivo.
>
> Mantenha o estilo do código atual: funções curtas, `error()` com cor. Adicione também
> `info()`, `warn()` e `success()` no mesmo padrão.

---

## Prompt 2 — Grupos de pacotes

> Agora popule os pacotes. Como o script roda a partir do repositório clonado, os pacotes
> devem ficar em arquivos de texto na pasta `pkgs/`, um por grupo, com prefixo numérico
> definindo a ordem de instalação. Formato: um pacote por linha, `#` inicia comentário,
> linhas vazias ignoradas.
>
> Crie uma função `read_pkgs` que lê um desses arquivos removendo comentários e linhas
> vazias, e falha com mensagem clara se o arquivo não existir. Pacotes do AUR ficam em
> `pkgs/aur/`, separados, porque são instalados pelo yay e não pelo pacman.
>
> Grupos: `base`, `hardware`, `session`, `audio`, `network`, `fonts`, `theme`, `files`,
> `apps`, `codecs`, `printing`, `power`, `dev`. Cada arquivo começa com um comentário de
> cabeçalho explicando a função do grupo, e cada pacote não-óbvio leva comentário inline
> explicando por que está ali.
>
> Requisitos por grupo, derivados da auditoria em `docs/relato.txt`:
>
> - **hardware:** firmware SOF (o áudio desta máquina não funciona sem ele), configuração
>   UCM do ALSA, microcode Intel, driver de mídia Intel e Vulkan para aceleração de vídeo,
>   `fwupd`.
> - **session:** XWayland (ausente hoje), os três portais XDG incluindo o backend GTK
>   (é ele que fornece o seletor de arquivos dos navegadores), agente polkit, chaveiro.
> - **audio:** pilha PipeWire completa incluindo a camada ALSA e JACK, utilitários de
>   diagnóstico e uma GUI de controle de volume.
> - **fonts:** cobertura para latim, CJK e emoji, mais uma Nerd Font (o Waybar depende
>   dela para os ícones), mais fontes métricas compatíveis com as da Microsoft.
> - **files:** thumbnails, montagem automática de dispositivos removíveis, suporte a MTP
>   para celular, e suporte de leitura a NTFS e APFS — esta máquina é triple boot e hoje
>   não consegue ler as partições dos outros dois sistemas.
> - **apps:** ao menos um aplicativo para cada tipo de arquivo comum (PDF, imagem, vídeo,
>   áudio, arquivo compactado, documento de escritório, editor de texto gráfico). Incluir
>   Firefox como navegador reserva além do Zen, que vem do AUR e pode quebrar em update.
> - **power:** usar TLP (não `power-profiles-daemon`), `thermald`, `brightnessctl`.
> - **dev:** ferramentas de linha de comando modernas, Docker, runtimes, `stow`.
>
> Antes de finalizar, valide que todo nome de pacote existe de fato nos repositórios
> oficiais usando `pacman -Ssq '^nome$'`, e separe corretamente o que só existe no AUR.
> Se algum nome não existir mais, me avise em vez de chutar um substituto.
>
> Adicione ao `--dry-run` uma validação que percorre todas as listas e reporta nomes
> inexistentes, para eu pegar erro de digitação sem instalar nada.

---

## Prompt 3 — Configuração de sistema (a parte que não é pacote)

> Adicione uma etapa de configuração que roda depois da instalação dos pacotes. Cada item
> deve ser **idempotente** — rodar duas vezes não pode duplicar linha nem sobrescrever
> customização feita à mão. Antes de editar qualquer arquivo em `/etc`, fazer backup com
> sufixo `.bak-AAAAMMDD`.
>
> Onde fizer sentido, use arquivos-modelo versionados em `files/` em vez de gerar o
> conteúdo dentro do script com heredoc — fica mais fácil de revisar no diff.
>
> 1. **Teclado:** esta máquina tem teclado ABNT2, mas o sistema está configurado como US.
>    Configurar `/etc/vconsole.conf` para `br-abnt2`. Perguntar antes, já que é uma
>    mudança visível (padrão "não alterar" quando `--yes` estiver ativo).
> 2. **Variáveis de ambiente Wayland** em `~/.config/environment.d/`: habilitar Wayland
>    nativo para Firefox/Zen, Qt, Electron, SDL e Java. Definir `XDG_CURRENT_DESKTOP=sway`
>    — hoje está vazio, e é essa variável que faz os portais escolherem o backend certo.
>    Como o Sway é iniciado a partir do TTY, garantir que a variável esteja definida
>    ANTES do Sway subir, não só dentro da sessão.
> 3. **Configuração dos portais** em `~/.config/xdg-desktop-portal/`: screencast pelo
>    backend `wlr`, todo o resto (principalmente o seletor de arquivos) pelo `gtk`.
> 4. **`/etc/nsswitch.conf`:** adicionar `mdns_minimal` na linha `hosts` para descoberta
>    de impressora em rede. Editar de forma idempotente, sem duplicar entrada.
> 5. **Grupos do usuário:** `video`, `input`, e `docker` se o Docker for instalado.
>    Avisar que é preciso relogar para valer.
> 6. **`xdg-user-dirs-update`** para criar as pastas padrão do home.
> 7. **Aplicativos padrão:** definir via `xdg-mime default` para PDF, imagem, vídeo,
>    áudio, texto, pasta, arquivo compactado e `http`/`https`. Hoje quase tudo está
>    apontado para o navegador ou para nada.
> 8. **`/etc/pacman.conf`:** habilitar `Color`, `ParallelDownloads` e `VerbosePkgLists`.
>    Perguntar antes de habilitar o `multilib`.
> 9. **Limite de carga da bateria em 80%** via TLP — a bateria está com 82% da saúde
>    original e isso desacelera a degradação.
>
> Não mexer em `/etc/fstab`, em `/boot`, nem em nada relacionado a bootloader.

---

## Prompt 4 — Serviços

> Adicione a etapa de habilitação de serviços, executada por último.
>
> Regras:
> - Só habilitar serviço cujo pacote foi de fato instalado com sucesso — consultar a
>   lista de falhas acumulada pela `install_pkgs`.
> - Verificar se já está ativo antes de agir, para o script ser idempotente.
> - **Verificação de conflito obrigatória:** se `power-profiles-daemon` estiver ativo,
>   abortar a habilitação do TLP com mensagem explicativa em vez de habilitar os dois.
> - Serviços de sistema: NetworkManager, bluetooth, cups.socket, avahi-daemon, tlp,
>   thermald, fstrim.timer, ufw, paccache.timer.
> - Docker: habilitar só se eu confirmar.
> - Verificar (sem alterar) se os serviços de usuário do PipeWire estão ativos, e reportar.
>
> Além disso, gere `files/sway-exec-snippet.conf` com os `exec` necessários para os
> daemons que hoje não sobem: agente polkit, daemon de notificação `mako`, `udiskie` para
> montagem automática, applets de rede e bluetooth, monitor de clipboard, `kanshi` e
> `gammastep`. Grave nesse arquivo separado em vez de editar meu config do Sway
> diretamente — quero revisar e integrar eu mesmo ao dotfile versionado.

---

## Prompt 5 — Dotfiles com GNU Stow

> Crie um script `dotfiles.sh` (chamado pelo `install.sh` via flag `--dotfiles`, e também
> executável sozinho) que gerencia os dotfiles versionados **neste mesmo repositório**.
>
> - A raiz do stow é a pasta `dotfiles/` do repositório; o alvo é `$HOME`. Estrutura:
>   `dotfiles/<pacote>/.config/<app>/...`, onde `<pacote>` é uma pasta stow (sway, waybar,
>   foot, wofi, mako, nvim, zsh, git).
> - Usar `stow --dir` e `--target` explicitamente, resolvidos a partir do diretório do
>   repositório — nunca depender do diretório de trabalho atual.
> - Se `dotfiles/` não existir, criar o esqueleto de diretórios vazio.
> - **Antes de aplicar, detectar conflitos:** arquivo real já existente no destino faz o
>   stow falhar. Para cada conflito, mover o original para `~/dotfiles-backup-AAAAMMDD/`
>   preservando a estrutura de caminho, e só então aplicar. Listar tudo que foi movido.
> - Rodar `stow --simulate` primeiro e mostrar o plano; só aplicar depois de confirmação
>   (respeitando `--yes`).
> - Suportar `--restow`, `--delete <pacote>` e `--list` (mostra quais pacotes stow existem
>   e quais estão atualmente aplicados).
> - Nunca sobrescrever ou apagar um arquivo real sem antes movê-lo para o backup.
>
> **Atenção a um risco específico deste modelo:** como os dotfiles viram symlinks
> apontando para dentro do repositório, mover ou renomear a pasta do repositório quebra
> todos eles de uma vez. Adicione ao `--doctor` uma verificação de symlinks quebrados no
> `~/.config`, e mencione esse comportamento no README.

---

## Prompt 6 — Higiene e segredos do repositório

> Este repositório contém meus dotfiles e pode vir a ser público. Quero garantir que
> nenhum segredo entre nele.
>
> 1. Crie um `.gitignore` abrangente cobrindo os vazamentos típicos de repositório de
>    dotfiles: chaves privadas de SSH e GPG, `known_hosts`, tokens de CLIs (gh, aws, gcloud,
>    npm, docker), arquivos `.env`, histórico de shell, bancos de dados de navegador,
>    caches, e credenciais de sincronização de editor.
> 2. Escreva um script `scripts/check-secrets.sh` que varre os arquivos versionados
>    procurando padrões de credencial: blocos de chave privada, strings que pareçam token
>    (sequências longas alfanuméricas com prefixo conhecido), atribuições de variável com
>    nome sugestivo (`*_TOKEN`, `*_SECRET`, `*_PASSWORD`, `*_KEY`), e URLs com credencial
>    embutida. Deve sair com código diferente de zero se encontrar algo.
> 3. Configure esse script como hook de pre-commit, com instrução de instalação no README.
>    O hook precisa ser instalável por mim explicitamente (hooks não são versionados pelo
>    git por padrão) — inclua um comando para isso.
> 4. Documente no README que, se um segredo chegar a ser commitado, apagar o arquivo não
>    basta: ele permanece no histórico e a credencial deve ser considerada comprometida
>    e rotacionada.
>
> Rode o `check-secrets.sh` no estado atual do repositório e me mostre o resultado.

---

## Prompt 7 — Modo `--doctor`

> Adicione ao `install.sh` uma flag `--doctor` que roda **somente diagnóstico**, sem
> instalar nem modificar nada, e reporta cada item como OK / AVISO / FALHA com uma
> sugestão de correção para os que não passarem.
>
> Verificações:
> - Áudio: existe placa registrada em `/proc/asound/cards`, existe sink que não seja
>   `auto_null`, e o firmware SOF está presente no disco.
> - Sessão: tipo da sessão é wayland, `DISPLAY` está definido (XWayland ativo),
>   `XDG_CURRENT_DESKTOP` está preenchido.
> - Portais: o backend GTK está registrado no barramento, não só o wlr.
> - Processos: agente polkit rodando, daemon de notificação rodando.
> - Fontes: `fc-match emoji` resolve para uma fonte de emoji de verdade e não para um
>   fallback genérico; `fc-match monospace` resolve para a Nerd Font esperada.
> - Aplicativos padrão: cada tipo MIME principal tem handler definido.
> - Vídeo: `vainfo` reporta perfis de aceleração.
> - Energia: exatamente um gerenciador de energia ativo, nunca dois.
> - Dotfiles: nenhum symlink quebrado em `~/.config`, e os pacotes stow esperados estão
>   de fato aplicados.
> - Saúde: `systemctl --failed` vazio, erros de prioridade <=3 no boot atual.
> - Pacotes: comparar as listas em `pkgs/` contra o que está instalado e listar ausências.
>
> Código de saída diferente de zero se houver qualquer FALHA, para poder usar em CI.

---

## Prompt 8 — Testar em container (não pule este)

> Quero validar o script sem arriscar a minha máquina real.
>
> Crie um `Dockerfile` baseado em `archlinux:base-devel` e um script `test.sh` que:
> - Sobe o container com um usuário não-root com sudo sem senha.
> - Copia o repositório inteiro (não só o `install.sh`, já que agora ele depende de
>   `pkgs/`, `dotfiles/` e `files/`) e roda primeiro com `--dry-run`, depois de verdade.
> - Testa também o `dotfiles.sh`, incluindo o caminho de conflito: criar um arquivo real
>   em `~/.config` que colida com um pacote stow e verificar que ele é movido para o
>   backup em vez de perdido.
> - Verifica o código de saída e imprime o resumo de pacotes que falharam.
>
> Documente no README quais partes **não são testáveis** em container e precisam de
> validação manual na máquina real: qualquer coisa que dependa de hardware (áudio,
> firmware, backlight), de systemd rodando como PID 1, de sessão gráfica, ou de serviços
> que exigem privilégio real.
>
> Rode o teste e me mostre o resultado. **Não execute o `install.sh` fora do container.**

---

## Prompt 9 — README

> Escreva o `README.md` do repositório contendo:
>
> - O que o repositório é: provisionador + dotfiles da minha máquina.
> - **Instalação**, começando pelo pré-requisito que as pessoas esquecem: numa instalação
>   limpa do Arch, o `git` não vem incluído no `base`, então é preciso instalá-lo antes de
>   conseguir clonar. Sequência completa: instalar git, clonar, entrar na pasta, executar.
> - Todas as flags disponíveis.
> - A lista de grupos de pacotes com uma linha de descrição cada.
> - Como funcionam os dotfiles: stow, estrutura de pastas, como adicionar um app novo, e o
>   aviso de que mover ou renomear a pasta do repositório quebra todos os symlinks.
> - Como instalar o hook de pre-commit de verificação de segredos.
> - O que precisa ser feito manualmente depois: relogar por causa dos grupos, integrar o
>   snippet ao config do Sway, reiniciar para o áudio carregar o firmware.
> - Seção de solução de problemas cobrindo os casos que já enfrentei nesta máquina: áudio
>   sem sink (firmware SOF ausente), aplicativo X11 que não abre (XWayland ausente), e
>   seletor de arquivos que não aparece no navegador (portal GTK ausente).
>
> Não inclua instrução de instalação via `curl | bash` — este script depende do repositório
> clonado e não funciona por pipe.

---

## Regras que valem para todos os prompts

Se o Claude Code começar a divagar, cole isto:

> Lembretes: não execute o `install.sh` nesta máquina — só em container. Não toque em
> `/boot` (ESP compartilhada entre três sistemas operacionais). Não gere código que
> particione, formate ou use `dd`. Todo caminho relativo deve ser resolvido a partir do
> diretório do repositório, nunca do diretório de trabalho atual. Valide nomes de pacote
> com `pacman -Ssq` antes de incluir; se um pacote não existir, me pergunte em vez de
> substituir por conta própria. Prefira funções curtas e legíveis a soluções espertas —
> vou manter este script sozinho.
