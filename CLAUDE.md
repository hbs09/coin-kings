# Coin Kings — contexto para o Claude Code

Jogo Roblox de estratégia: **campanha a solo como corpo, PvP 1v1 com ranking por cima**. Recebe-se um orçamento, compram-se tropas e feitiços, posicionam-se às escondidas na própria metade de um mapa limpo e assiste-se à batalha automática, lançando os feitiços manualmente. Ganha quem decide melhor. **Nunca se vende poder.**

## Estratégia e risco (ler antes de mexer no roadmap)

Decidido a 14/10/2026, depois de estudar o mercado. **A procura existe; a retenção é que é o problema.**

- O concorrente mais próximo, **Units Battlegrounds** ("primeiro auto-battler do Roblox"), fez 73 M de visitas e está hoje com ~17 jogadores em simultâneo (pico de 3 635 em jun/2025). **Make Your Own Army**: 11 M de visitas desde 2017, 8 jogadores hoje.
- O que sobreviveu no género foi **PvE com progressão**: *The Battle Bricks* (`maxPlayers = 1`) tem 144 M de visitas e ~2 000 jogadores quatro anos depois; o tower defense cooperativo chega aos 100 K de pico.
- **Não há caso conhecido de 1v1 com ranking sustentado no Roblox.** Um 1v1 puro precisa de massa crítica simultânea; quando a curva desce, a fila morre primeiro e o resto vai atrás.

Daí as três decisões que mandam neste documento:

1. **A campanha PvE é a espinha do jogo**, não um modo de treino. O `BotService` é peça central, não recurso de fila vazia.
2. **Diferença face ao Units Battlegrounds:** lá o poder vem da coleção, dos upgrades e do trading; aqui vem só das decisões, com orçamento igual. Isso evita o power creep que mata o PvP — mas **retira o motor de retenção padrão do Roblox** (grind, abrir, trocar). Substituí-lo (ranked com significado, campanha, temporadas, cosméticos) é o problema central do projeto, não um detalhe.
3. **Nada de Battle Pass, clãs, temporadas ou replays antes de haver prova de retenção.**

## O travão — critérios de paragem ou pivô

Medidos na alpha, com 50–100 jogadores e analytics ligado. Decididos a frio, antes de haver sentimentos pelo projeto:

- **D1 < 8%** ou **menos de 2 partidas por sessão** → o loop está partido. Arranjar o início; não acrescentar conteúdo.
- **D1 entre 8% e 15%** → normal para a plataforma. Continuar e otimizar o encadear de partidas.
- **Fila acima de 20 s no pico de jogadores** → o PvP não se sustenta sozinho; a campanha PvE passa a ser o jogo principal e o ranked fica como extra.

Referência real (GameAnalytics, milhares de jogos com 1 M+ MAU): o D1 **mediano** do Roblox anda nos **10,3%**, e sobe com a duração da sessão — 7,9% para sessões de 7–12 min, 11,5% para 19–24 min. Os 25% que este documento pedia antes são topo de plataforma, não um alvo de MVP.

## Stack e convenções
- Luau com `--!strict` em todos os ficheiros. Rojo para sincronizar com o Studio. Git.
- Identificadores em inglês; o texto que o jogador vê fica em PT/EN, num módulo `Locale`.
- Os valores de balanceamento vivem **só** em `ReplicatedStorage/Shared/Config/*`; nada fica hardcoded na lógica.
- **O servidor é a autoridade:** o cliente envia intenções e o servidor valida tudo (ouro, posições, cooldowns). O cliente apenas desenha e anima.
- Cada sistema é um ModuleScript com `init()` e `start()`, carregado por um bootstrap único no servidor e outro no cliente.
- Todos os `RemoteEvent` e `RemoteFunction` ficam centralizados em `Shared/Net.luau`, com validação de tipos e rate limit.

## Estrutura
```
src/
  server/  Bootstrap.server.luau
           Services/ MatchmakingService, MatchService, CombatService,
                     EconomyService, MapService, BotService,
                     RankService, DataService, AnalyticsService
  client/  Bootstrap.client.luau
           State.luau, UIUtil.luau, UnitVisual.luau
           Controllers/ ShopController, PlacementController (rato + toque),
                        SpellController, CameraController, UIController,
                        UnitsController
  shared/  Config/ Troops, Spells, Maps, Rank, Match, Campaign
           Types.luau, Net.luau, Locale.luau, Util/ (Placement)
```
O que já existe está no [README.md](README.md); o resto desta lista é o destino.

## Loop da partida (máquina de estados no MatchService)
`Queue → Prep (45 s: comprar e posicionar) → Reveal (3 s) → Battle (máx. 90 s) → RoundEnd → … → MatchEnd`
- Melhor de 3 rondas. O orçamento é de 1000 ouro por ronda e quem perde a ronda recebe +150 na seguinte.
- Durante a fase de preparação, o cliente **não recebe** dados do exército adversário.
- A ronda acaba quando um lado fica sem unidades. Se o tempo acabar, ganha quem tiver mais valor (em ouro) vivo.
- No fim da partida: ecrã de resultado, ΔElo, XP e botão de revanche (os dois aceitam → nova partida imediata).

## Tropas (Config/Troops) — valores iniciais, ajustáveis
| id | custo | papel | forte vs | fraca vs |
|---|---|---|---|---|
| soldier | 20 | massa | archer | mage, knight |
| spearman | 35 | anti-cavalaria | knight | archer |
| archer | 40 | distância | infantaria lenta | knight |
| shieldbearer | 60 | tanque | archer | mage |
| knight | 80 | flanco rápido | archer, mage | spearman |
| fire_mage | 120 | dano em área | grupos | knight |
| healer | 100 | cura aliados | — | corpo a corpo |
| giant | 250 | elite | soldier | spearman em massa |

Cada tropa define: `hp, damage, range, attackSpeed, moveSpeed, aoeRadius?, bonusVs: {[id]: multiplier}`.
IA: procura o inimigo válido mais próximo, aproxima-se até ao alcance e ataca; o curandeiro procura o aliado ferido mais próximo.

## Feitiços (Config/Spells) — máx. 2 por ronda
meteor 150 (dano em área pequena) · divine_shield 120 (5 s de invulnerabilidade em área) · freeze 100 (3 s de paragem em área) · fury 130 (+40% de velocidade e dano durante 6 s). Lançados durante a batalha; o servidor valida o cooldown e a área.

## Limites técnicos
- Máx. **40 unidades por jogador**. O objetivo são 60 fps em telemóvel.
- Simulação no servidor em tick fixo (10 Hz). O cliente interpola as posições e só replica o estado mínimo (id, posição, hp, estado).
- Evitar um `Humanoid` por unidade se pesar: preferir modelos ancorados com movimento por CFrame. Pathfinding simples num mapa plano.
- **Vários jogos em paralelo por servidor — feito.** 6 partidas por servidor (`Config/Match.maxMatchesPerServer`), uma arena por slot, afastadas 500 studs em X. Cada partida tem o seu estado e a sua `CombatService.Session`; a replicação é só para os dois jogadores dela. **As coordenadas que viajam na rede são locais à arena**: o `arenaOffsetX` vai no `MatchState` e o cliente soma-o apenas para desenhar, por isso as regras de `Config/Maps` valem para todas as arenas. O lugar no Studio precisa de **Max Players = 12** (Game Settings).

## Ranking (RankService)
- Elo escondido (inicial 1000, K = 32, K = 48 nas primeiras 20 partidas).
- Escalões visíveis: Bronze, Prata, Ouro, Platina, Diamante, Mestre (3 divisões cada) e Lenda (top 100).
- Matchmaking: Elo ±100, alargando +50 a cada 10 s. Se a espera passar 20 s → partida contra o BotService, marcada como "treino" e sem efeito no Elo. **Esperas longas e recorrentes são o sinal de que o PvP não se sustenta** — medir e registar o tempo de fila desde o primeiro dia.
- Leaderboard global via OrderedDataStore, atualizado de 5 em 5 minutos. Existe um modo casual separado, sem Elo.
- Temporadas de 6 a 8 semanas, com reset parcial (−1 escalão).

## Dados do jogador (DataService, DataStore com retry, session lock e versão do esquema)
```
{ version, elo, wins, losses, season, level, xp, coins,
  unlockedTroops = {}, cosmetics = {}, equipped = {}, dailyQuests = {}, lastLogin }
```
Guardar ao sair, de 60 em 60 s, e em `BindToClose`.

## Campanha PvE (BotService) — o corpo do jogo
- Capítulos com dificuldade crescente, cada um com um exército inimigo fixo e um orçamento definido em `Config/Campaign`. O jogador resolve o puzzle: que tropas comprar e onde pô-las.
- É aqui que se desbloqueiam tropas e se aprende o counter de cada uma — o tutorial é o primeiro capítulo.
- Usa o mesmo `MatchService`/`CombatService` do PvP; muda só quem é o adversário.
- Objetivo de desenho: dar motivo para voltar amanhã sem vender poder nem grind de coleção.

## Progressão e retenção
- Tutorial de 90 s contra um bot (capítulo 1 da campanha). As 3 primeiras partidas PvP são contra bots fáceis.
- Desbloqueios de tropas por XP (tudo acessível em cerca de 20 h). Nível de conta 1 a 100, com cosméticos.
- 3 missões diárias e a primeira vitória do dia vale XP a dobrar.
- **Encadear partidas é a alavanca com maior impacto no D1** (a retenção acompanha a duração da sessão). A revanche e o voltar à fila sem fricção são funcionalidade de primeira linha, não polimento.
- Fase 4: desafiar amigos, modo espectador, replays, clãs.

## Monetização (só cosmético)
Battle Pass, skins de tropas (a mesma hitbox), efeitos de feitiço, emotes, bandeiras, Game Pass VIP (aura e +10% de XP) e servidores privados. **Proibido:** qualquer vantagem em partida, caixas aleatórias pagas e pressão falsa ("última oportunidade").

## Roadmap — trabalhar fase a fase e não avançar sem cumprir o critério
1. **Protótipo — FEITO (14/10/2026).** Mapa plano com duas metades; soldier, archer e knight; compra validada no servidor; posicionamento por arrastar; batalha até um lado morrer; 1 ronda. *Critério cumprido:* 2 jogadores locais jogaram uma partida completa sem erros na Output.
2. **MVP:** ~~vários jogos por servidor~~ (feito), melhor de 3 (só mudar `Config/Match`), as 8 tropas (falta a IA do curandeiro), 2 feitiços, DataService, campanha PvE com os primeiros capítulos, Elo e leaderboard, UI para telemóvel. *Critério:* alpha fechada com D1 ≥ 12% e ≥ 2 partidas por sessão — ver **O travão**.
3. **Lançamento:** 4 feitiços, mapa com rio e ponte, modo casual, missões, nível de conta, mais capítulos de campanha, analytics completo (`AnalyticsService`: funil do tutorial, taxa de vitória por tropa, revanche).
4. **Temporada 1:** Battle Pass, escalões e temporadas, amigos, espectador, replays, eventos.

**Analytics mínimo entra na fase 2, não na 3:** sem medir D1, partidas por sessão e tempo de fila, não há como saber se o critério do MVP passou.

## Definição de pronto (por tarefa)
- Sem erros nem avisos na Output, com `--!strict` a passar.
- Testado em Studio com 2 jogadores e no emulador de telemóvel.
- Nenhum valor de balanceamento fora de `Config`; nenhuma decisão de jogo do lado do cliente.
- Explicar no fim de cada tarefa o que mudou e como se testa.
