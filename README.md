<div align="center">

[![My Cloud](.github/banner.svg)](#readme)

[![Último commit](https://img.shields.io/github/last-commit/gabrielxreis/myclaude?color=brightgreen&label=atualizado&style=for-the-badge)](https://github.com/gabrielxreis/myclaude/commits/main "Histórico")
[![Claude Code](https://img.shields.io/badge/Claude_Code-assinatura-D97757.svg?style=for-the-badge&logo=anthropic&logoColor=white)](https://claude.com/claude-code "Claude Code")
[![ChatGPT](https://img.shields.io/badge/ChatGPT-via_Codex-10A37F.svg?style=for-the-badge&logo=openai&logoColor=white)](#perguntas-pelo-chatgpt "ChatGPT")
[![macOS](https://img.shields.io/badge/macOS-15+-lightblue.svg?style=for-the-badge&logo=apple&logoColor=black)](#instalacao "Instalação")
[![Swift](https://img.shields.io/badge/Swift-6-F05138.svg?style=for-the-badge&logo=swift&logoColor=white)](#desenvolvimento "Desenvolvimento")
[![Licença: MIT](https://img.shields.io/badge/-MIT-red.svg?style=for-the-badge)](LICENSE "Licença")

</div>

**My Cloud** é um assistente que mora no notch do seu Mac. Você chama pelo nome ("Ei Cloud", ou o nome que escolher), pede em voz alta e ele faz: abre apps, pesquisa, descarrega o cartão da câmera para o SSD, monta o projeto no DaVinci, responde perguntas e conversa com você. Por trás, ele usa o **Claude Code da sua assinatura** e o **ChatGPT pela sua conta**: nada de chave de API, nada de créditos extras. E ele é um bichinho: tem humor, nível, roupas que mudam com o clima e com as datas festivas, e reage ao que você está fazendo.

<div align="center">

<img src=".github/hero.gif" width="420" alt="Bolinho, o personagem padrão do My Cloud, passando pelos humores: parado, ouvindo, feliz, pensando e com sono">

<sub><b>Bolinho</b>, o personagem padrão: parado, ouvindo (pulinho e olhar para a câmera), feliz, pensando e com sono.</sub>

</div>

> **Cada pessoa usa as PRÓPRIAS contas.** O app não traz conta, chave nem login. Ele usa o Claude Code e o Codex que já estão logados no seu Mac. Conversas, atalhos e configurações ficam no seu computador.

* [O QUE ELE FAZ](#o-que-ele-faz)
    * [Voz e conversa contínua](#voz-e-conversa-continua)
    * [Ações instantâneas](#acoes-instantaneas)
    * [Cartão de memória](#cartao-de-memoria)
    * [Chat no notch e histórico](#chat-no-notch-e-historico)
    * [Perguntas pelo ChatGPT](#perguntas-pelo-chatgpt)
    * [Skills: /ogab e /ojhon](#skills-ogab-e-ojhon)
* [PERSONAGENS](#personagens)
* [INSTALAÇÃO](#instalacao)
* [CONFIGURAÇÃO](#configuracao)
    * [O que o Cloud pode fazer](#o-que-o-cloud-pode-fazer)
* [PRIVACIDADE](#privacidade)
* [DESENVOLVIMENTO](#desenvolvimento)
* [CRÉDITOS](#creditos)

<a id="o-que-ele-faz"></a>
# O QUE ELE FAZ

<a id="voz-e-conversa-continua"></a>
## Voz e conversa contínua

* **Chamado pelo nome.** "Ei Cloud", "Oi Cloud", "OK Cloud" ou "Hey Cloud", ou qualquer nome que você configurar ("Cláudio", "Jarvis"...). Ele entende variações que o Mac costuma escrever ("Claudio", "iCloud") e nunca acorda quando você só fala *do* Claude numa frase.
* **Faz enquanto você fala.** "Abre o Chrome e pesquisa animais da Antártida": o Chrome abre assim que você diz "Chrome", e a pesquisa sai quando a frase termina.
* **Continua ouvindo.** Depois de cada pedido ele segue escutando, sem novo chamado, até você dizer "obrigado", "valeu", "pode parar" ou ficar uns segundos em silêncio.
* **Sons e animação.** Um "tink" quando começa a ouvir, um "pop" quando termina, e o personagem pula e olha para você enquanto escuta.
* **Só texto ou com voz.** Por padrão a resposta aparece no notch. Se quiser que ele fale, escolha a voz do Mac ou a do ElevenLabs.

<a id="acoes-instantaneas"></a>
## Ações instantâneas

Rodam no próprio app, na hora, sem gastar o plano:

| Você diz | Ele faz |
|---|---|
| "abre o DaVinci", "fecha o Spotify" | abre ou fecha o app (nome aproximado vale: "da Vinci") |
| "abre a pasta Downloads", "abre a pasta Clientes" | abre a pasta no Finder |
| "abre o YouTube", "abre o site globo.com" | abre o site no navegador |
| "pesquisa receita de bolo" | pesquisa no Google |
| "abre a conversa com a Maria no WhatsApp" | abre a conversa (telefone dos Contatos) |
| "manda mensagem pro João no WhatsApp dizendo que chego às 8" | deixa a mensagem escrita; **você** aperta Enter |

<a id="cartao-de-memoria"></a>
## Cartão de memória

"**Cláudio, descarrega o cartão pro SSD no projeto Casamento Ana**":

1. Acha o cartão sozinho e reconhece a câmera (Sony, Canon, Nikon, GoPro, DJI, Panasonic, Fujifilm).
2. Pergunta na conversa só o que não sabe: câmera, qual SSD, qual pasta (e lembra a última).
3. Cria `SSD/Casamento Ana/Sony/SD1` (o próximo cartão vira `SD2`).
4. Copia **em segundo plano**, com o progresso no notch, em qualquer tela que você estiver.
5. Confere arquivo por arquivo e avisa com notificação. **Nunca mexe no cartão.**

E dá para pedir junto:

* **"nos dois SSDs"**: backup duplo, os dois ao mesmo tempo, os dois conferidos.
* **"com proxy"**: proxies 720p em `SD1/Proxy`.
* **"e transcreve"**: transcrição local (Whisper, grátis, no próprio Mac) em `SD1/Transcricoes`.
* **"e cria o projeto no DaVinci"**: a [/ogab](https://github.com/gabrielxreis/ogab) cria o projeto e monta a timeline.

<a id="chat-no-notch-e-historico"></a>
## Chat no notch e histórico

O balão do notch abre um chat compacto. O botão **Histórico** abre a janela grande com todas as conversas, de voz e digitadas, cada uma retomando o contexto de onde parou. Tocar na resposta que aparece embaixo do notch também abre a conversa.

<a id="perguntas-pelo-chatgpt"></a>
## Perguntas pelo ChatGPT

Perguntas e pesquisas ("quem ganhou o jogo?", "o que é...", "quanto custa...") vão para o **ChatGPT pelo Codex CLI**, logado com a sua conta do ChatGPT: sem API e sem créditos. Pedidos para *fazer* algo ficam com o Claude. Dá para mandar tudo para o Claude nos Ajustes.

<a id="skills-ogab-e-ojhon"></a>
## Skills: /ogab e /ojhon

O My Cloud vem com duas skills do Claude Code, instaladas junto:

* **[/ogab](https://github.com/gabrielxreis/ogab)**: editor de vídeo (DaVinci, Premiere, After Effects, legenda, motions, roteiro, Instagram).
* **[/ojhon](https://github.com/gabrielxreis/ojhon)**: gestor de tráfego (auditoria de anúncios, plano de mídia, criativos, relatórios).

As duas aparecem como atalhos no notch, e pedidos de vídeo e de anúncio vão direto para elas. Você pode fixar qualquer outra skill instalada como atalho, ou pedir ao Cloud: "cria uma ação rápida que...".

<a id="personagens"></a>
# PERSONAGENS

<div align="center">

<img src=".github/gang.gif" width="840" alt="Os 12 personagens do My Cloud se mexendo">

</div>

Doze bichinhos, cada um com suas manias, todos com os mesmos humores (ouvindo, pensando, falando, feliz, focado, com sono, carente, surpreso, tonto):

| | |
|---|---|
| **Bolinho** (padrão) | olhos de esfera que seguem o cursor, inclina a cabeça para ouvir, piscada dupla, fica tonto com três cutucadas |
| **Nuvem** | balança quando pensa, garoa quando está carente, arco-íris quando feliz |
| **Marshmallow** | amassa e estica, topete que balança, derrete com sono |
| **Vapor** | flutua, fica translúcido quando pensa, solta vapor quando se assusta |
| **Claquete** | a ripa abre quando fala e faz "clap" quando fica feliz |
| **Camerazinha** | a lente é o olho, com abertura que muda e "REC" piscando quando ouve |
| **Gotinha** | pinga quando triste, evapora quando dorme |
| **Pipoca** | estoura pipoquinhas quando feliz |
| **Lâmpada** | acende quando pensa ou fica feliz, apaga quando está carente |
| **Planetinha** | anel girando e luas orbitando quando os agentes trabalham |
| **Gatinho de nuvem** | orelhas em pé para ouvir, rabinho, rastro de arco-íris |
| **Bolha de sabão** | furta-cor, estoura e se forma de novo quando se assusta |

**Tamagotchi.** O card do notch mostra o nome, o humor do momento e o nível (Ovo, Filhote, Jovem, Adulto, Mestre), com três barras: **Humor** (sobe quando vocês interagem), **Energia** (o que resta do seu plano do Claude) e **Foco** (agentes trabalhando). Ele também vê em qual app você está e sugere algo que consegue fazer ali.

**Skins.** Padrão, cachecol, fone, boina de diretor, óculos escuros e coroa, ou **automática**: cachecol no frio, óculos no calor, garoa quando chove (clima da sua cidade pelo Open-Meteo, grátis) e roupa de festa no Natal, Ano Novo, Carnaval, Páscoa, Festa Junina, Dia das Crianças e Halloween.

<a id="instalacao"></a>
# INSTALAÇÃO

Dois cliques em **`Instalar My Cloud.command`**. Ele:

1. Instala o **Claude Code** (se faltar) e confere o login da sua assinatura.
2. Instala ou atualiza a **/ogab** e a **/ojhon**.
3. Instala o **RustDesk**, para acessar o Mac pelo celular.
4. Compila o My Cloud, apaga a versão antiga e instala em **Aplicativos**.

Depois, no próprio app (ícone na barra de menu → Ajustes):

* **Voz:** aceite o microfone e o reconhecimento de fala quando o Mac pedir.
* **Agentes:** "Instalar hooks" do Claude Code, para o Cloud ver as suas sessões.
* **ChatGPT (opcional):** `brew install --cask codex` e `codex login` com a sua conta.

**Atualização automática.** Uma vez por dia o My Cloud confere este repositório: se tiver versão nova, ele baixa, compila em segundo plano, troca a versão em Aplicativos e avisa. A /ogab e a /ojhon são atualizadas junto. Dá para desligar ou verificar na hora em **Ajustes → Geral → Atualizações**.

**Requisitos:** macOS 15 ou mais novo, Xcode (para compilar), assinatura do Claude (Pro ou Max). Para o cartão de memória com proxies e transcrição: ffmpeg e Whisper local, que a /ogab instala.

<a id="configuracao"></a>
# CONFIGURAÇÃO

Tudo em **Ajustes**:

* **Geral → Personagem:** o bichinho, a skin, a cidade do clima e os sons.
* **Voz:** nome do assistente (vários, separados por vírgula), microfone, idioma, quem responde perguntas (ChatGPT ou Claude) e se ele fala ou só escreve.
* **Agentes:** hooks do Claude Code e as skills /ogab e /ojhon.

<a id="o-que-o-cloud-pode-fazer"></a>
## O que o Cloud pode fazer

As ações instantâneas sempre funcionam. Para o resto, o Cloud usa o Claude Code em um destes modos:

| Modo | O que acontece |
|---|---|
| **Só consultar** | lê arquivos e pesquisa, não executa nada |
| **Lista de ações** (padrão) | só usa o que está na lista (regras de permissão do Claude Code, editáveis, com guia e exemplos). Fora da lista, ele não faz e avisa |
| **Automático** | modo automático do Claude Code: executa sozinho o que for seguro e bloqueia o arriscado. Vem desligado, com aviso, e só você liga |

Em qualquer modo, ele nunca apaga, publica ou envia mensagem sem você confirmar.

<a id="privacidade"></a>
# PRIVACIDADE

* Sem telemetria e sem conta do My Cloud.
* A voz é reconhecida **no próprio Mac**; só o texto do pedido vai para o Claude ou o ChatGPT, pelas suas contas.
* Conversas, atalhos e configurações ficam em `~/Library/Application Support/MyCloud`.
* Rede, só para o que você usa: Claude, ChatGPT e o clima (Open-Meteo).

<a id="desenvolvimento"></a>
# DESENVOLVIMENTO

```bash
cd NotchBuddy && xcodegen
../scripts/build-mycloud.sh
```

* `scripts/build-mycloud.sh`: compila, assina com identidade estável (o macOS guarda as permissões entre versões), troca a versão em Aplicativos e abre.
* `scripts/render-cloud.swift`: desenha os personagens em PNG e GIF (vitrine, ícone, quadros).
* `scripts/make-cloud-sounds.py`: gera os 29 sons originais do app.

O código Swift do app fica em `NotchBuddy/Sources/App`. Os personagens estão em `CloudPainter.swift`, o cérebro em `Voice/ClaudeCLIBrain.swift` e `Voice/ChatGPTBrain.swift`, e as ações locais em `Voice/CloudLocalActions.swift` e `Voice/CardOffload.swift`.

<a id="creditos"></a>
# CRÉDITOS

O My Cloud nasceu de um fork do **[Coucou](https://github.com/Louis-CFM/coucou)**, de Louis Raillé, cujo código é MIT. O nome Coucou, o personagem Mochi, os sons e as imagens do Coucou pertencem ao autor e **não fazem parte deste repositório**: o My Cloud tem personagens, ícone e sons próprios.

<div align="center">

<img src=".github/icone.png" width="96" alt="Ícone do My Cloud">

Feito por **Gabriel Reis** · [gabrielxreis.com](https://gabrielxreis.com) · [instagram.com/gabrielxreis_](https://instagram.com/gabrielxreis_)

</div>
