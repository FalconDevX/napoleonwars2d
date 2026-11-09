# Wycinanie tła portretów modelem BiRefNet (rembg), czyszczenie białej obwódki,
# łagodne zanikanie dołu postaci, dopasowanie całej postaci do kadru 3:4 (600x800).
import sys, os, numpy as np
from PIL import Image, ImageFilter
from rembg import remove, new_session
SRC = sys.argv[1]; OUT = sys.argv[2]
W, H = 600, 800
M={1:"fr_fusiliers",2:"fr_chasseurs",3:"fr_voltigeurs",4:"fr_garde_nat",5:"fr_chass_cheval",6:"fr_hussars",7:"fr_dragoons",
8:"fr_art6",9:"fr_art8",10:"fr_grenadiers",11:"fr_carabiniers",12:"fr_sappers",13:"fr_lancers",14:"fr_carab_cheval",
16:"fr_art12",17:"fr_horse_art",18:"fr_howitzers",19:"fr_yg_tirailleurs",20:"fr_fus_gren",21:"fr_marins",22:"fr_chass_pied",
23:"fr_chass_garde",24:"fr_mamelukes",25:"fr_red_lancers",26:"fr_drag_imp",27:"fr_gren_cheval",28:"fr_gendarmes",
29:"fr_art_garde",30:"fr_horse_art_garde",31:"fr_pontoniers",32:"fr_larrey",33:"fr_marshal",34:"fr_napoleon",
35:"fr_pol_chevau",36:"fr_swiss",37:"fr_westphal"}
if len(sys.argv) > 3:   # inna nacja: mapowanie numer->klucz z pliku JSON
    import json
    M = {int(k): v for k, v in json.load(open(sys.argv[3], encoding="utf-8")).items()}
ses = new_session("birefnet-general")

def process(path):
    src = Image.open(path).convert("RGB")
    cut = remove(src, session=ses)
    a = np.asarray(cut).astype(np.float32)
    rgb, al = a[..., :3], a[..., 3] / 255.0
    # białe tło wmieszane w półprzezroczyste krawędzie -> usuń (brak jasnej obwódki)
    bg = np.median(np.concatenate([np.asarray(src)[0], np.asarray(src)[-1]]).astype(np.float32), axis=0)
    aa = np.maximum(al, 1e-3)[..., None]
    rgb = np.where(al[..., None] < 0.98, np.clip((rgb - bg * (1 - aa)) / aa, 0, 255), rgb)
    # wyblakły, prawie biały dół malunku -> zanika w przezroczystość
    ys, xs = np.nonzero(al > 0.1)
    y0, y1 = ys.min(), ys.max()
    fade_h = max(1, int((y1 - y0) * 0.14))
    grad = np.clip((y1 - np.arange(al.shape[0])) / fade_h, 0, 1)[:, None]
    whiteish = np.clip((rgb.min(axis=2) - 170.0) / 70.0, 0, 1) * np.clip(1 - (rgb.max(axis=2) - rgb.min(axis=2)) / 40.0, 0, 1)
    al = al * (1 - whiteish * (1 - grad) * 0.85) * np.clip(grad * 1.6, 0, 1) ** 0.5
    im = Image.fromarray(np.dstack([rgb, al * 255]).astype(np.uint8))
    return im

def fit(im):
    bb = im.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox()
    im = im.crop(bb)
    w, h = im.size
    if w / h > 1.25:
        al = np.asarray(im.getchannel("A")) > 20
        xs = np.nonzero(al[: max(1, int(h * 0.15))].any(axis=0))[0]
        cx = int(xs.mean()) if xs.size else w // 2
        cw = int(h * 1.25); x0 = max(0, min(w - cw, cx - cw // 2))
        im = im.crop((x0, 0, x0 + cw, h)); im = im.crop(im.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox())
        w, h = im.size
    pad = 0.03
    s = min(W * (1 - 2 * pad) / w, H * (1 - pad) / h)
    im = im.resize((max(1, int(w * s)), max(1, int(h * s))), Image.LANCZOS)
    r, g, b, a = im.split()
    sharp = Image.merge("RGB", (r, g, b)).filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    im = Image.merge("RGBA", (*sharp.split(), a))
    can = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    y = int(H * pad) if im.size[1] < H * 0.9 else H - im.size[1]
    can.alpha_composite(im, ((W - im.size[0]) // 2, y))
    return can

for i, key in M.items():
    fit(process(os.path.join(SRC, f"{i}.png"))).save(os.path.join(OUT, key + ".png"), optimize=True)
    print(key, flush=True)
