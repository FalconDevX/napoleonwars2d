"""Napis z nazwą gry (Wings of Empire) na przezroczystym tle - kilka wariantów + arkusz porównawczy.

Uruchom z katalogu projektu:  python tools/gen_title.py
Wynik: tools/napis_A.png, napis_B.png, napis_C.png (przezroczyste PNG) i tools/napis_warianty.png (podgląd).
Styl jak na ekranie tytułowym: Cinzel, złoto z połyskiem, ciemny obrys i miękki cień (czytelny na każdym tle),
orzeł Francji z assets/ui/fr_emblem.png.
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

FONT = "assets/fonts/Cinzel.ttf"
EAGLE = "assets/ui/fr_emblem.png"
SS = 2   # nadpróbkowanie: rysujemy 2x większe i zmniejszamy - gładkie krawędzie


def font(size, weight=700):
    f = ImageFont.truetype(FONT, size * SS)
    f.set_variation_by_axes([weight])
    return f


def text_mask(txt, f, tracking=0.0):
    """Maska tekstu z rozstrzeleniem liter (tracking w ułamku wysokości fontu)."""
    size = f.size
    widths = [f.getlength(c) for c in txt]
    track = tracking * size
    w = int(sum(widths) + track * (len(txt) - 1) + size)
    h = int(size * 1.6)
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    x = size * 0.5
    for c, cw in zip(txt, widths):
        d.text((x, size * 0.2), c, font=f, fill=255)
        x += cw + track
    return m.crop(m.getbbox())


def gold_fill(size, top=(255, 236, 178), mid=(222, 182, 98), low=(150, 104, 42)):
    """Pionowy gradient złota: jasny połysk u góry, ciemniejszy spód (jak metal w świetle z góry)."""
    w, h = size
    g = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        if t < 0.45:
            k = t / 0.45
            c = [int(top[i] + (mid[i] - top[i]) * k) for i in range(3)]
        else:
            k = (t - 0.45) / 0.55
            c = [int(mid[i] + (low[i] - mid[i]) * k) for i in range(3)]
        g.putpixel((0, y), tuple(c))
    return g.resize((w, h))


def flat_fill(size, col):
    return Image.new("RGB", size, col)


def styled(mask, fill, outline=(38, 26, 12), out_px=3, shadow=0.65):
    """Maska -> warstwa RGBA: miękki cień, ciemny obrys, wypełnienie, cienki połysk na górnych krawędziach."""
    pad = 40 * SS
    w, h = mask.size
    m = Image.new("L", (w + pad * 2, h + pad * 2), 0)
    m.paste(mask, (pad, pad))
    out = Image.new("RGBA", m.size, (0, 0, 0, 0))
    # cień: rozmyty, lekko przesunięty w dół
    sh = m.filter(ImageFilter.MaxFilter(1 + 2 * (out_px + 2) * SS)).filter(ImageFilter.GaussianBlur(9 * SS))
    sh = sh.point(lambda v: int(v * shadow))
    shl = Image.new("RGBA", m.size, (0, 0, 0, 0))
    shl.putalpha(sh)
    out.alpha_composite(shl, (0, 5 * SS))
    # obrys
    ol = m.filter(ImageFilter.MaxFilter(1 + 2 * out_px * SS))
    oll = Image.new("RGBA", m.size, outline + (0,))
    oll.putalpha(ol)
    out.alpha_composite(oll)
    # wypełnienie (gradient dopasowany do wysokości samych liter)
    fl = Image.new("RGBA", m.size, (0, 0, 0, 0))
    fill_img = fill((w, h)).convert("RGBA")
    fl.paste(fill_img, (pad, pad))
    fl.putalpha(m)
    out.alpha_composite(fl)
    # połysk: jasna krawędź tam, gdzie litera "zaczyna się" od góry
    shifted = ImageChops.offset(m, 0, 2 * SS)
    edge = ImageChops.subtract(m, shifted).filter(ImageFilter.GaussianBlur(0.6 * SS)).point(lambda v: int(v * 0.55))
    hl = Image.new("RGBA", m.size, (255, 250, 225, 0))
    hl.putalpha(edge)
    out.alpha_composite(hl)
    return out.crop(out.getbbox())


def ornament(width, gold=(214, 176, 98), dim=(140, 114, 64)):
    """Linia ozdobna z rombami, jak pod tytułem w grze."""
    h = 28 * SS
    im = Image.new("RGBA", (width, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cy = h // 2
    d.line([(10 * SS, cy), (width - 10 * SS, cy)], fill=dim + (255,), width=2 * SS)

    def diamond(cx, r, col):
        d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=col + (255,))

    diamond(width // 2, 11 * SS, gold)
    diamond(width // 2, 5 * SS, (255, 236, 178))
    diamond(10 * SS, 6 * SS, dim)
    diamond(width - 10 * SS, 6 * SS, dim)
    # cienki cień pod linią, żeby była widoczna na jasnym tle
    sh = im.split()[3].filter(ImageFilter.GaussianBlur(3 * SS)).point(lambda v: int(v * 0.5))
    base = Image.new("RGBA", im.size, (0, 0, 0, 0))
    base.putalpha(sh)
    base.alpha_composite(im)
    return base


def eagle(height):
    e = Image.open(EAGLE).convert("RGBA")
    w = int(e.width * height / e.height)
    e = e.resize((w, height), Image.LANCZOS)
    sh = e.split()[3].filter(ImageFilter.GaussianBlur(6 * SS)).point(lambda v: int(v * 0.6))
    pad = 20 * SS
    out = Image.new("RGBA", (w + pad * 2, height + pad * 2), (0, 0, 0, 0))
    shl = Image.new("RGBA", out.size, (0, 0, 0, 0))
    shl.paste((0, 0, 0, 255), (pad, pad + 4 * SS), sh)
    out.alpha_composite(shl)
    out.alpha_composite(e, (pad, pad))
    return out


def stack(parts, gap):
    """Elementy jeden pod drugim, wyśrodkowane. parts: lista (obraz, odstęp_po)."""
    w = max(p.width for p, _ in parts)
    h = sum(p.height for p, _ in parts) + sum(g for _, g in parts[:-1])
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    y = 0
    for p, g in parts:
        out.alpha_composite(p, ((w - p.width) // 2, y))
        y += p.height + g
    return out


def finish(im, margin=30):
    im = im.crop(im.getbbox())
    m = margin * SS
    out = Image.new("RGBA", (im.width + 2 * m, im.height + 2 * m), (0, 0, 0, 0))
    out.alpha_composite(im, (m, m))
    return out.resize((out.width // SS, out.height // SS), Image.LANCZOS)


CREAM = lambda size: flat_fill(size, (242, 234, 210))


def variant_a():
    """Jak w menu gry: orzeł, złote WINGS OF, kremowe EMPIRE, linia z rombami, podtytuł."""
    t1 = styled(text_mask("WINGS OF", font(190, 700), 0.04), gold_fill)
    t2 = styled(text_mask("EMPIRE", font(150, 600), 0.18), lambda s: gold_fill(s, (255, 250, 232), (240, 230, 200), (196, 180, 140)))
    orn = ornament(int(t1.width * 0.92))
    sub = styled(text_mask("BATTLES OF THE GRANDE ARMÉE  ·  1805 – 1815", font(40, 500), 0.12),
                 lambda s: flat_fill(s, (214, 206, 186)), out_px=2, shadow=0.5)
    return finish(stack([(eagle(230 * SS), 0), (t1, -20 * SS), (t2, 10 * SS), (orn, 18 * SS), (sub, 0)], 0))


def variant_b():
    """Jedna linia: WINGS OF EMPIRE, orzeł nad środkiem, linia z rombami pod spodem."""
    t = styled(text_mask("WINGS OF EMPIRE", font(170, 800), 0.06), gold_fill)
    return finish(stack([(eagle(200 * SS), 6 * SS), (t, 14 * SS), (ornament(int(t.width * 0.8)), 0)], 0))


def variant_c():
    """Pionowy znak: wielkie WINGS / małe OF między liniami / wielkie EMPIRE, ciężkie złoto."""
    big = font(230, 900)
    t1 = styled(text_mask("WINGS", big, 0.1), gold_fill, out_px=4)
    t3 = styled(text_mask("EMPIRE", big, 0.1), gold_fill, out_px=4)
    of = styled(text_mask("OF", font(70, 700), 0.4), lambda s: flat_fill(s, (242, 234, 210)), out_px=2)
    w = int(max(t1.width, t3.width) * 0.42)
    row = Image.new("RGBA", (w * 2 + of.width + 40 * SS, max(of.height, 28 * SS)), (0, 0, 0, 0))
    l = ornament(w)
    row.alpha_composite(l, (0, (row.height - l.height) // 2))
    row.alpha_composite(of, (w + 20 * SS, (row.height - of.height) // 2))
    row.alpha_composite(l, (w + of.width + 40 * SS, (row.height - l.height) // 2))
    return finish(stack([(eagle(220 * SS), 4 * SS), (t1, 6 * SS), (row, 6 * SS), (t3, 0)], 0))


def sheet(images, path):
    """Podgląd: każdy wariant na ciemnym tle, na jasnym tle i na szachownicy (widać przezroczystość)."""
    cell_w = max(i.width for i in images) // 2 + 40
    rows = []
    for im in images:
        small = im.resize((im.width // 2, im.height // 2), Image.LANCZOS)
        row = Image.new("RGB", (cell_w * 3, small.height + 40), (0, 0, 0))
        bgs = [Image.new("RGB", (cell_w, row.height), (22, 22, 26)), Image.new("RGB", (cell_w, row.height), (190, 196, 170))]
        chk = Image.new("RGB", (cell_w, row.height), (200, 200, 200))
        dc = ImageDraw.Draw(chk)
        for y in range(0, row.height, 16):
            for x in range(0, cell_w, 16):
                if (x // 16 + y // 16) % 2:
                    dc.rectangle([x, y, x + 15, y + 15], fill=(150, 150, 150))
        bgs.append(chk)
        for k, bg in enumerate(bgs):
            bg = bg.convert("RGBA")
            bg.alpha_composite(small, ((cell_w - small.width) // 2, 20))
            row.paste(bg.convert("RGB"), (k * cell_w, 0))
        rows.append(row)
    out = Image.new("RGB", (cell_w * 3, sum(r.height for r in rows) + 10 * len(rows)), (60, 60, 60))
    y = 0
    for r in rows:
        out.paste(r, (0, y))
        y += r.height + 10
    out.save(path)


if __name__ == "__main__":
    vs = {"A": variant_a(), "B": variant_b(), "C": variant_c()}
    for k, im in vs.items():
        im.save("tools/napis_%s.png" % k)
        print("tools/napis_%s.png" % k, im.size)
    sheet(list(vs.values()), "tools/napis_warianty.png")
