# Coin Kings

Jogo Roblox de estratégia: compra-se um exército com um orçamento fixo,
posiciona-se às escondidas e assiste-se à batalha automática. Campanha a solo
como corpo do jogo, PvP 1v1 com ranking por cima. **Nunca se vende poder** — o
orçamento é igual para os dois lados e ganha quem decide melhor.

O contexto completo, a estratégia e os critérios de paragem estão em
[CLAUDE.md](CLAUDE.md).

**Estado: fase 2 (MVP) em curso.** Tutorial automático na primeira partida,
**7 arenas por troféus** (cada uma desbloqueia uma tropa), PvP por fila com
melhor de 3, as 8 tropas, compra e posicionamento validados no servidor,
6 partidas em paralelo por servidor e perfil persistente. Faltam os feitiços,
o bot de fila, o leaderboard e o analytics.

## Arrancar

```bash
rokit install
```

```bash
rojo serve
```

No Roblox Studio: instalar o plugin do Rojo (`rojo plugin install`), abrir um
*Baseplate* novo, clicar em **Rojo → Connect**. A árvore é criada a partir de
[default.project.json](default.project.json); a arena é construída em runtime
pelo `MapService`, por isso o lugar pode ficar vazio.

## Testar (critério da fase 1)

1. No Studio, **Test → Clients and Servers → 2 Players → Start**.
2 jogadores são precisos: o matchmaking emparelha-os em ≤ 1 s.
2. Em cada cliente: tocar numa tropa na loja e **arrastar para a própria
   metade** (a pré-visualização fica verde se a posição servir, vermelha se
   não). Arrastar uma unidade já colocada move-a; o botão **Vender** (ou o
   botão direito do rato) devolve o ouro.
3. **Pronto** nos dois clientes salta o resto da preparação.
4. Reveal (3 s) → batalha → ecrã de resultado → volta ao lobby e começa outra.
5. Output do Studio deve ficar sem erros nem avisos.

Para o emulador de telemóvel: **Test → Device**, com um telefone selecionado.
A UI é desenhada por código, com botões grandes, e o posicionamento funciona com
toque.

## Estrutura

```
src/
  server/  Bootstrap.server.luau
           Services/ MatchmakingService  emparelha os 2 jogadores
                     MatchService        máquina de estados + autoridade do exército
                     CombatService       simulação da batalha a 10 Hz
                     EconomyService      ouro da ronda
                     MapService          constrói a arena
  client/  Bootstrap.client.luau
           State.luau       espelho do estado do servidor (hub dos eventos)
           UIUtil.luau      atalhos de UI
           UnitVisual.luau  o corpo de uma unidade
           Controllers/ UIController, ShopController, PlacementController,
                        CameraController, UnitsController
  shared/  Config/ Troops, Maps, Match      (únicos valores de balanceamento)
           Types.luau, Net.luau, Locale.luau, Util/Placement.luau
```

## Regras do código

- `--!strict` em todos os ficheiros; identificadores em inglês, texto do
  jogador no `Locale`.
- Valores de balanceamento **só** em `shared/Config/*`.
- O servidor é a autoridade: o cliente manda intenções pelo `Net` e desenha o
  que o servidor confirma. A regra de posicionamento vive em
  `shared/Util/Placement.luau` para os dois lados usarem o mesmo critério.
- Cada sistema é um ModuleScript com `init()` e `start()`, carregado pelo
  bootstrap do servidor ou do cliente.

## Fase seguinte (MVP)

Pela ordem definida no [CLAUDE.md](CLAUDE.md):

1. ~~Vários jogos por servidor~~ — **feito**: 6 partidas em paralelo, uma arena
   por slot. Falta pôr **Max Players = 12** nas Game Settings do lugar.
2. ~~Melhor de 3 e as 8 tropas~~ — **feito**: `roundsToWin = 2`,
   `maxRounds = 3`, as 8 tropas no `troopPool` e a IA de suporte do curandeiro
   no `CombatService`. A loja passou a deslizar na horizontal.
3. ~~DataService~~ — **feito**: DataStore com retry, session lock e versão do
   esquema; grava ao sair, de 60 em 60 s e no `BindToClose`. Para testar a
   persistência no Studio é preciso ligar **Game Settings → Security → Enable
   Studio Access to API Services**.
4. ~~Tutorial e arenas~~ — **feito**: tutorial automático na primeira partida e
   7 arenas por troféus, cada uma a desbloquear uma tropa.
5. ~~Bot de fila~~ — **feito**: passados 20 s de espera arranca um treino
   contra o bot, sem efeito nos troféus.
6. **Leaderboard**, 2 feitiços e analytics mínimo.

Critério para fechar a fase: alpha com **D1 ≥ 12%** e **≥ 2 partidas por
sessão**.
