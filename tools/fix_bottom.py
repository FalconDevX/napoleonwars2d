# Usuwa jasne (białe) pociągnięcia pędzla w dolnej części portretu - dół postaci zanika w przezroczystość.
import glob, os, sys, numpy as np
from PIL import Image
from scipy import ndimage
for f in glob.glob(os.path.join(sys.argv[1], "*.png")):
    a = np.asarray(Image.open(f).convert("RGBA")).astype(np.float32)
    rgb, al = a[..., :3], a[..., 3] / 255.0
    ys = np.nonzero((al > 0.1).any(axis=1))[0]
    y0, y1 = ys.min(), ys.max()
    zone = int((y1 - y0) * 0.22)
    t = np.clip((np.arange(al.shape[0]) - (y1 - zone)) / max(1, zone), 0, 1)[:, None]   # 0 nad strefą, 1 na dole
    mn = rgb.min(axis=2); ch = rgb.max(axis=2) - mn
    whiteish = np.clip((mn - 150.0) / 60.0, 0, 1) * np.clip(1 - ch / 45.0, 0, 1)
    whiteish = ndimage.gaussian_filter(whiteish, 1.0)
    al = al * (1 - np.clip(whiteish * (0.4 + 1.2 * t), 0, 1))
    al = al * (1 - 0.6 * t ** 2)          # łagodne wygaszenie samego dołu
    al[al < 0.04] = 0
    out = np.dstack([rgb, al * 255]).astype(np.uint8)
    Image.fromarray(out).save(os.path.join(sys.argv[2], os.path.basename(f)), optimize=True)
print("ok")
