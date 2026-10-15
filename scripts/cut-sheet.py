"""Recorta uma folha de arte gerada por IA em PNGs soltos com fundo transparente.

    python -I scripts/cut-sheet.py <folha> <pasta-destino> [nome1,nome2,...] [lado]

Os modelos de imagem falham a transparência quase sempre: devolvem o xadrez
*pintado* ou um fundo liso. Este script resolve isso de fora.

Três decisões que custaram a chegar lá:

1. **O fundo é só o que está ligado à moldura.** Marcar por cor apanhava também
   o branco da túnica do curandeiro e a prata das armaduras, e abria buracos no
   meio das figuras.
2. **A separação é por peças ligadas, não por grelha.** Na folha das tropas a
   maça do gigante e a chama do meteoro sobrepõem-se em x: qualquer corte a
   direito estragava uma das duas.
3. **Os pedaços soltos vão para a figura mais próxima.** As brasas do meteoro e
   os flocos de neve do gelo são peças separadas e fazem parte do desenho.

Depende do Pillow: `pip install pillow`.
"""
import os
import sys
from collections import deque

from PIL import Image, ImageFilter

SCALE = 4  # a ligação decide-se em miniatura; o recorte é no tamanho real
SAT = 16  # acima disto a cor tem matiz e não é fundo neutro
TOL = 10
RAMP = 22  # degraus de cor entre transparente e opaco
MIN_AREA = 3000  # em pixeis da miniatura, para ignorar sujidade do jpeg
OUT_SIZE = 512


def background_tones(im: Image.Image) -> list[int]:
    """Os cinzentos do fundo, lidos na moldura da imagem."""
    w, h = im.size
    px = im.load()
    edge = [px[x, y] for x in range(0, w, 7) for y in (0, h - 1)]
    edge += [px[x, y] for y in range(0, h, 7) for x in (0, w - 1)]
    counts: dict[int, int] = {}
    for r, g, b in edge:
        if max(r, g, b) - min(r, g, b) <= SAT:
            counts[(r + g + b) // 3] = counts.get((r + g + b) // 3, 0) + 1
    tones: list[int] = []
    for tone, _ in sorted(counts.items(), key=lambda kv: -kv[1]):
        if all(abs(tone - t) > TOL * 2 for t in tones):
            tones.append(tone)
        if len(tones) == 2:
            break
    return tones


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    src, out_dir = argv[1], argv[2]
    names = argv[3].split(",") if len(argv) > 3 and argv[3] else []
    size = int(argv[4]) if len(argv) > 4 else OUT_SIZE

    im = Image.open(src).convert("RGB")
    W, H = im.size
    tones = background_tones(im)
    if not tones:
        print("não encontrei um fundo neutro na moldura da imagem")
        return 1
    print(f"{W}x{H}, fundo nos cinzentos {tones}")

    lo, hi = min(tones) - TOL, max(tones) + TOL

    def gap(v: int) -> int:
        """A que distância este cinzento está da banda do fundo.

        Com um xadrez são dois tons, e o degrau entre eles também é fundo — daí
        ser uma banda inteira e não dois valores soltos.
        """
        if v < lo:
            return lo - v
        if v > hi:
            return v - hi
        return 0

    def is_bg(rgb) -> bool:
        r, g, b = rgb
        if max(r, g, b) - min(r, g, b) > SAT:
            return False
        return gap((r + g + b) // 3) == 0

    def opacity(rgb) -> int:
        """Transparência em rampa, em vez de tudo ou nada.

        Um corte seco deixava a auréola cinzenta do jpeg à volta das figuras, e
        apagá-la com uma erosão comia os contornos finos: a bandeira branca
        ficava com o traço aos bocados. A rampa resolve as duas coisas.
        """
        r, g, b = rgb
        if max(r, g, b) - min(r, g, b) > SAT:
            return 255
        return max(0, min(255, gap((r + g + b) // 3) * 255 // RAMP))

    sw, sh = W // SCALE, H // SCALE
    spx = im.resize((sw, sh), Image.NEAREST).load()
    cand = bytearray(sw * sh)
    for y in range(sh):
        for x in range(sw):
            if is_bg(spx[x, y]):
                cand[y * sw + x] = 1

    def flood(seeds, passable, out, mark):
        q = deque(seeds)
        for i in seeds:
            out[i] = mark
        while q:
            i = q.popleft()
            x, y = i % sw, i // sw
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < sw and 0 <= ny < sh:
                    j = ny * sw + nx
                    if passable(j) and out[j] == 0:
                        out[j] = mark
                        q.append(j)

    bg = bytearray(sw * sh)
    border = [y * sw + x for x in range(sw) for y in (0, sh - 1) if cand[y * sw + x]]
    border += [y * sw + x for y in range(sh) for x in (0, sw - 1) if cand[y * sw + x]]
    flood(border, lambda j: cand[j], bg, 1)

    label = [0] * (sw * sh)
    groups: dict[int, list[int]] = {}
    mark = 0
    for i in range(sw * sh):
        if not bg[i] and label[i] == 0:
            mark += 1
            flood([i], lambda j: not bg[j], label, mark)
    for i, m in enumerate(label):
        if m:
            groups.setdefault(m, []).append(i)

    # Com os nomes dados, as figuras são simplesmente as N peças maiores: um
    # limite de área fixo falhava nas figuras magras (o visto, a bandeira).
    by_area = sorted(groups, key=lambda m: -len(groups[m]))
    anchors = by_area[:len(names)] if names else [m for m in by_area if len(groups[m]) >= MIN_AREA]
    print(f"{len(groups)} peças, {len(anchors)} figuras")
    if len(anchors) < len(names):
        print(f"só encontrei {len(anchors)} peças para {len(names)} nomes")
        return 1

    def centre(ids: list[int]) -> tuple[float, float]:
        px = [p for m in ids for p in groups[m]]
        return sum(p % sw for p in px) / len(px), sum(p // sw for p in px) / len(px)

    members = {m: [m] for m in anchors}
    centres = {m: centre([m]) for m in anchors}
    for m in groups:
        if m in members:
            continue
        cx, cy = centre([m])
        near = min(anchors, key=lambda a: (centres[a][0] - cx) ** 2 + (centres[a][1] - cy) ** 2)
        members[near].append(m)

    # ordem de leitura, por linhas de altura semelhante
    rows: list[list[int]] = []
    for m in sorted(anchors, key=lambda m: centres[m][1]):
        if rows and abs(centres[rows[-1][0]][1] - centres[m][1]) < sh / 8:
            rows[-1].append(m)
        else:
            rows.append([m])
    order = [m for row in rows for m in sorted(row, key=lambda m: centres[m][0])]

    os.makedirs(out_dir, exist_ok=True)
    full = im.load()
    for index, m in enumerate(order):
        own = Image.new("L", (sw, sh), 0)
        o = own.load()
        for g in members[m]:
            for p in groups[g]:
                o[p % sw, p // sw] = 255
        big = own.resize((W, H), Image.NEAREST).filter(ImageFilter.MaxFilter(9)).load()

        alpha = Image.new("L", (W, H), 0)
        a = alpha.load()
        for y in range(H):
            for x in range(W):
                if big[x, y]:
                    a[x, y] = opacity(full[x, y])

        piece = im.copy()
        piece.putalpha(alpha)
        piece = piece.crop(alpha.point(lambda v: 255 if v > 128 else 0).getbbox())

        side = max(piece.size)
        pad = int(side * 0.04)
        canvas = Image.new("RGBA", (side + pad * 2, side + pad * 2), (0, 0, 0, 0))
        canvas.alpha_composite(piece, ((canvas.size[0] - piece.size[0]) // 2,
                                       (canvas.size[1] - piece.size[1]) // 2))
        canvas = canvas.resize((size, size), Image.LANCZOS)

        name = names[index] if names else f"{index + 1:02d}"
        canvas.save(os.path.join(out_dir, name + ".png"))
        print(f"  {name}.png  <- {piece.size[0]}x{piece.size[1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
