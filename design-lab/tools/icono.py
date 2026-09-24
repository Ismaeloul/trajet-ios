"""Icono de la app «Cristal»: el billete.

Un billete opaco (el que enseña los minutos en la app) con la caja amarilla
de la vía en su matriz, sobre el fondo neutro del sistema. Sale de los tokens
de design-lab/tokens.json (bg, ticket, ticketInk, via, viaInk, accent).

Tres variantes, como pide iOS 18+ (appearances del AppIcon):
  - clara:   fondo claro, billete oscuro (ticket claro = oklch 15%)
  - oscura:  fondo oscuro, billete claro
  - tintada: solo formas en escala de grises sobre negro; iOS le pone el tinte

    python design-lab/tools/icono.py

Escribe los 1024 px en Trajet/Resources/Assets.xcassets/AppIcon.appiconset/
y una vista previa en design-lab/capturas/icono.png. Solo Pillow.
"""
import json
import os

from PIL import Image, ImageDraw, ImageFilter

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOKENS = os.path.join(RAIZ, "design-lab", "tokens.json")
DESTINO = os.path.join(RAIZ, "Trajet", "Resources", "Assets.xcassets", "AppIcon.appiconset")
N = 1024
S = 4          # supersampling para bordes limpios


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def tokens():
    c = json.load(open(TOKENS, encoding="utf-8"))["color"]
    return {k: {m: hexrgb(c[k][m]["hex"]) for m in ("light", "dark")}
            for k in ("bg", "ticket", "ticketInk", "via", "viaInk", "accent", "surface")}


def rr(draw, box, r, fill):
    draw.rounded_rectangle(box, radius=r, fill=fill)


def billete(modo, t):
    """modo: 'light' | 'dark' | 'tinted'"""
    n = N * S
    if modo == "tinted":
        fondo, ticket, ink, via, via_ink = (0, 0, 0), (235, 235, 235), (20, 20, 20), (255, 255, 255), (0, 0, 0)
    else:
        fondo, ticket, ink = t["bg"][modo], t["ticket"][modo], t["ticketInk"][modo]
        via, via_ink = t["via"][modo], t["viaInk"][modo]

    im = Image.new("RGB", (n, n), fondo)
    d = ImageDraw.Draw(im)

    # Un suave halo de cristal detrás del billete (solo en claro/oscuro): el
    # cristal es la capa de controles; el billete, el dato.
    if modo != "tinted":
        halo = Image.new("RGB", (n, n), fondo)
        hd = ImageDraw.Draw(halo)
        tono = tuple(min(255, v + (18 if modo == "dark" else -10)) for v in fondo)
        rr(hd, (n * 0.10, n * 0.20, n * 0.90, n * 0.80), n * 0.20, tono)
        halo = halo.filter(ImageFilter.GaussianBlur(n * 0.05))
        im = halo
        d = ImageDraw.Draw(im)

    # El billete: opaco, esquinas 22 % del ancho (radios concéntricos de la app).
    x0, y0, x1, y1 = n * 0.14, n * 0.27, n * 0.86, n * 0.73
    rr(d, (x0, y0, x1, y1), (y1 - y0) * 0.30, ticket)

    # Los «minutos»: dos barras gruesas y una corta (una cifra grande y «min»),
    # abstractas para que el icono no dependa de una tipografía.
    g = (y1 - y0)
    bx = x0 + g * 0.26
    by = y0 + g * 0.26
    rr(d, (bx, by, bx + g * 0.28, by + g * 0.48), g * 0.07, ink)            # la cifra
    rr(d, (bx + g * 0.34, by + g * 0.36, bx + g * 0.62, by + g * 0.48), g * 0.06,
       tuple(int(v * 0.55 + 128 * 0.45) for v in ink) if modo != "tinted" else (110, 110, 110))  # «min»

    # La caja de la vía, en la matriz del billete (derecha): sólida, amarilla.
    vx0, vy0 = x1 - g * 0.62, y0 + g * 0.20
    vx1, vy1 = x1 - g * 0.18, y1 - g * 0.20
    rr(d, (vx0, vy0, vx1, vy1), g * 0.12, via)
    # dentro: el número de vía como dos trazos
    cx = (vx0 + vx1) / 2
    rr(d, (cx - g * 0.05, vy0 + g * 0.16, cx + g * 0.05, vy1 - g * 0.16), g * 0.05, via_ink)
    rr(d, (cx + g * 0.09, vy0 + g * 0.16, cx + g * 0.19, vy1 - g * 0.16), g * 0.05, via_ink)

    return im.resize((N, N), Image.LANCZOS)


def main():
    t = tokens()
    os.makedirs(DESTINO, exist_ok=True)
    nombres = {"light": "icon-1024.png", "dark": "icon-1024-dark.png", "tinted": "icon-1024-tinted.png"}
    ims = {}
    for modo, nombre in nombres.items():
        im = billete(modo, t)
        im.save(os.path.join(DESTINO, nombre), optimize=True)
        ims[modo] = im
    contents = {
        "images": [
            {"filename": nombres["light"], "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}],
             "filename": nombres["dark"], "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "tinted"}],
             "filename": nombres["tinted"], "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(DESTINO, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")
    # Vista previa: las tres juntas, con las esquinas de iOS.
    prev = Image.new("RGB", (3 * 360 + 80, 420), (128, 128, 128))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, N, N), radius=int(N * 0.2237), fill=255)
    for i, modo in enumerate(("light", "dark", "tinted")):
        im = ims[modo].copy()
        im.putalpha(mask)
        prev.paste(im.resize((360, 360), Image.LANCZOS), (20 + i * 380, 30), im.resize((360, 360), Image.LANCZOS))
    prev.save(os.path.join(RAIZ, "design-lab", "capturas", "icono.png"), optimize=True)
    print("icono escrito:", list(nombres.values()))


if __name__ == "__main__":
    main()
