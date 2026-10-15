# Prompt para o Gemini gerar a UI do Coin Kings

Três prompts. **A** dá as duas maquetas de ecrã (para decidir o aspeto), **B** dá
as peças soltas em PNG transparente (é o que se carrega no Roblox), **C** dá os
retratos das tropas e os ícones dos feitiços. Usar nesta ordem: só se pedem as
peças depois de o aspeto estar decidido na maqueta, senão geram-se 40 ficheiros
para o lixo.

**A regra que não se pode esquecer:** nas peças reutilizáveis (botões, painéis)
**o texto não vai na imagem**. O texto é desenhado pelo motor por cima, porque o
jogo é PT/EN e o número do ouro muda a cada compra. Nas maquetas o texto aparece,
para se ver o resultado; nos ficheiros finais não.

---

## Prompt A — as duas maquetas

```
És um artista de UI de jogos mobile. Desenha a interface de um jogo de estratégia
do Roblox chamado "Coin Kings", para crianças dos 8 aos 13 anos.

ESTILO
Cartoon grosso e colorido, ao nível de acabamento do Clash Royale e do Brawl
Stars, mas com desenho original. Botões carnudos, com brilho em cima e bordo
escuro em baixo, como se tivessem volume. Contornos escuros grossos (3 a 5 px) a
separar tudo. Cantos redondos generosos (16 a 24 px). Molduras douradas nos
sítios importantes. Cores muito saturadas e contraste alto. Letras gordas e
largas, nunca finas.
NÃO: minimalismo, flat design cinzento, realismo, estilo corporativo, sombras
subtis, aspeto de aplicação de telemóvel.

PALETA (usar exatamente estes valores)
fundo escuro #1A1D28 · painel #282D3E · painel claro #343A4E
dourado #FFCB47 e #E29B20 (ouro, destaques, molduras)
verde #60D688 e #34A860 (confirmar, jogar)
vermelho #F05F5C e #C43838 (erros, desistir, vender)
azul #68B2F0 (informação, gelo)
texto branco #F4F6FC

FORMATO
Paisagem 16:9, 1920x1080, um ecrã por imagem. Sem moldura de telemóvel em volta,
sem mãos, sem apresentação em perspetiva: só a interface, a ocupar a imagem toda.
Deixa livres os 60 px centrais do topo — no Roblox essa zona é tapada pela barra
do próprio jogo.

ECRÃ 1 — MENU PRINCIPAL
Fundo: um campo de batalha medieval cartoon, desfocado e escurecido.
- Em cima ao centro: o título "Coin Kings" em letras gordas douradas com contorno
  escuro, tipo emblema.
- Painel central grande com, por ordem:
  "Arena 1 · Campo de Treino", com um emblema redondo da arena à esquerda
  "0 troféus" em números enormes dourados, com um ícone de troféu ao lado
  uma barra de progresso grossa e dourada, quase vazia, com contorno escuro
  "Próxima arena aos 200 troféus · dá Lanceiro", em texto pequeno
  "Nível 1 · 0 moedas · 0V/0D", em texto pequeno
- Botão verde enorme, o maior elemento do ecrã: ícone de espadas cruzadas mais o
  texto "Jogar online".
- Dois botões menores por baixo, lado a lado, cada um com o seu ícone:
  "Repetir tutorial" (livro) e "Classificação" (pódio).

ECRÃ 2 — DENTRO DA PARTIDA, FASE DE PREPARAÇÃO
Fundo: vista de cima e ligeiramente inclinada de um campo retangular verde,
dividido ao meio, com soldadinhos cartoon de um lado. O fundo é só contexto; o
que importa é a interface por cima.
- Barra em cima ao centro (a começar abaixo dos 60 px livres): "Preparação" em
  cima, o relógio "0:45" em números enormes, "Ronda 1" em baixo.
- Canto superior direito: botão vermelho pequeno "Desistir", com uma bandeira.
- Em baixo à esquerda, acima da loja: pastilha com moeda e "820" em dourado
  grande, e abaixo um boneco com "12/40".
- Em baixo, a atravessar quase toda a largura: a loja, um carrossel horizontal
  com 5 cartas de tropa à vista. Cada carta tem o retrato da tropa numa moldura,
  o nome em baixo ("Soldado", "Arqueiro", "Cavaleiro", "Lanceiro", "Gigante") e o
  custo numa pastilha dourada no canto ("20", "40", "80", "35", "250"). A carta
  escolhida está um pouco maior e com o contorno dourado aceso.
- Em baixo à direita, a coluna de ações: botão cinzento "Vender" com uma moeda a
  sair, e por baixo um botão verde grande "Pronto" com um visto.
- À direita ao meio, na vertical: dois botões redondos de feitiço, cada um com
  ícone e o nome por baixo — "Meteoro" (bola de fogo) e "Gelo" (cristal azul).
- Ao centro, por cima do campo: a dica "Arrasta para a tua metade para colocar",
  em texto claro sobre uma faixa escura translúcida.

Gera as duas imagens.
```

---

## Prompt B — as peças soltas

```
A partir do estilo da maqueta anterior, gera as peças da interface em ficheiros
separados, cada uma com fundo totalmente transparente (PNG com canal alpha).

REGRA PRINCIPAL: nenhuma peça leva texto escrito. O texto é desenhado pelo motor
do jogo por cima. Onde devia estar o texto, deixa a superfície lisa e vazia. Os
ícones vão em ficheiros só deles, nunca colados ao botão.

BOTÕES (cada um em três versões: normal, premido, e desligado a cinzento)
- verde grande, 420x120
- cinzento médio, 320x96
- vermelho pequeno, 220x72
- redondo azul, 128x128 (feitiço)
Bordos uniformes e os quatro cantos iguais, para a imagem poder ser esticada sem
deformar o contorno (9-slice).

PAINÉIS
- painel escuro com moldura dourada, 800x600
- pastilha pequena para números, 240x80
- barra de progresso: o trilho vazio e a barra cheia dourada, em duas peças
  separadas, 640x56
- faixa translúcida para dicas, 900x72
- moldura de carta de tropa, 220x300, com um quadrado vazio em cima para o
  retrato e uma zona lisa em baixo para o nome

ÍCONES (um por ficheiro, 256x256, com silhueta clara e contorno escuro grosso,
legíveis quando reduzidos a 48x48)
moeda de ouro · troféu · relógio de areia · boneco (contador de unidades) ·
visto · etiqueta de venda · bandeira branca · pódio · livro aberto ·
espadas cruzadas · engrenagem

Devolve também, em texto, a lista dos ficheiros com as dimensões de cada um.
```

---

## Prompt C — tropas e feitiços

```
No mesmo estilo cartoon de contorno grosso, gera retratos para cartas de um jogo
do Roblox. Cada um numa imagem separada, 512x512, fundo transparente, figura de
corpo inteiro vista de frente, pose heroica e parada, cabeça grande e proporções
exageradas de desenho animado. Estilo infantil e simpático: nunca realista, nunca
assustador, sem sangue, sem caras agressivas. Sem texto na imagem.

1. Soldado — armadura simples azul, espada curta e escudo pequeno
2. Lanceiro — lança comprida, elmo de aba
3. Arqueiro — capuz verde, arco em tensão
4. Escudeiro — escudo enorme a tapar meio corpo, armadura pesada
5. Cavaleiro — armadura brilhante, capa vermelha, espada grande
6. Mago de Fogo — túnica vermelha e laranja, cajado com uma bola de fogo
7. Curandeiro — túnica branca e dourada, cajado com um cristal verde a brilhar
8. Gigante — enorme, maça de madeira, ar bonacheirão

E dois ícones de feitiço, 512x512, transparentes:
Meteoro — bola de fogo em queda, com rasto
Gelo — cristal azul com flocos de neve em volta
```

---

## Depois de receber as imagens

1. Guardar em `assets/ui/` (essa pasta não vai para o Roblox, é só o original).
2. No Studio: **Asset Manager → Images → Add Images**, carregar tudo, e copiar o
   `rbxassetid://` de cada uma.
3. Dar-me a lista `nome do ficheiro → rbxassetid`. Eu crio um
   `Shared/Config/Assets.luau` com os ids e troco os frames de cor sólida por
   `ImageLabel` e `ImageButton`. Com os ids todos num ficheiro, trocar um desenho
   mais tarde é mudar uma linha.
4. A maqueta **não entra no jogo** — a interface continua a ser construída em
   Luau. As imagens entram; o desenho do ecrã entra como decisão, não como
   ficheiro.

### O que costuma correr mal
- **Texto nas imagens.** Se vier com texto, é para refazer: o texto do jogo tem de
  ser do motor, por causa do PT/EN e dos números que mudam.
- **Transparência.** Os modelos de imagem falham o alpha com frequência. Se vier
  com fundo branco ou com o xadrez pintado, pedir outra vez a insistir em "fundo
  transparente, canal alpha".
- **Coerência.** Gerado tudo de uma vez, o estilo varia entre ficheiros. Gerar em
  lotes pequenos e pedir sempre "no mesmo estilo das imagens anteriores".
- **Limite do Roblox.** Acima de 1024x1024 a imagem é reduzida; não vale a pena
  pedir 4K.


---

# Resultado da primeira ronda (15/10/2026)

**Ficou bom:** os painéis, os botões e as 10 figuras do Prompt C. Estão em
`assets/ui/`, já cortadas e com fundo transparente.

**Falhou:** os 11 ícones do Prompt B. Vieram todos em grande plano e cortados —
pedaços de forma sem se perceber o que são, e três em branco. O padrão é claro:
**pedir um desenho pequeno num ficheiro só dele faz o modelo encher a tela e
cortar.** O Prompt C correu bem precisamente por ser o contrário: dez figuras
numa folha só, cada uma pequena dentro da imagem.

O Prompt C também veio com o xadrez *pintado* em JPG, em vez de transparência.
Isso resolve-se do nosso lado (ver abaixo), por isso não vale a pena voltar a
pedir só por causa disso.

## Prompt D — os ícones, desta vez numa folha só

```
Gera UMA única imagem com 12 ícones de interface de jogo, dispostos numa grelha
de 4 colunas por 3 linhas, com muito espaço vazio entre eles. Cada ícone ocupa
pouco mais de metade da sua célula: tem de caber inteiro, com margem à volta, e
nunca pode tocar nos vizinhos nem nas bordas da imagem.

Estilo: cartoon grosso e colorido, contorno preto espesso, cores saturadas, o
mesmo estilo dos bonecos medievais que geraste antes. Objetos simples e
reconhecíveis, vistos de frente, sem cenário e sem texto.

Fundo cinzento liso #808080 em toda a imagem, sem xadrez e sem padrão nenhum.

Os ícones, por ordem de leitura:
1. moeda de ouro com o símbolo de uma coroa
2. troféu de ouro com asas
3. ampulheta de madeira e areia dourada
4. busto de soldado de elmo azul (serve de contador de unidades)
5. visto verde grosso
6. etiqueta de preço com uma moeda
7. bandeira branca de rendição numa haste
8. pódio de três degraus com uma coroa em cima
9. livro antigo aberto
10. duas espadas cruzadas
11. engrenagem metálica
12. saco de moedas aberto
```

**Porquê fundo cinzento liso e não transparente:** o modelo falha o alpha quase
sempre, e um cinzento neutro é trivial de recortar — é exatamente o que o
`scripts/cut-sheet.py` já faz com a folha das tropas. Pedir transparência e
receber xadrez pintado dá o mesmo trabalho com pior qualidade de bordos.

## Recortar uma folha nova

```bash
python -I scripts/cut-sheet.py "caminho/para/a-folha.png" assets/ui/icons
```

O script tira o fundo (só o que estiver ligado à moldura, para não abrir buracos
no branco das figuras), separa por peças ligadas em vez de cortar em grelha — a
maça do gigante e a chama do meteoro sobrepunham-se em x e um corte a direito
estragava as duas — e grava cada figura centrada em 512x512.
