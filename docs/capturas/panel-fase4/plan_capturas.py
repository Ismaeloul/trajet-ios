"""Genera el plan de capturas del panel para design-lab/tools/capturar.mjs.

Uso: python plan_capturas.py <carpeta-de-salida> > plan.json

Cada grupo (movil/pc x claro/oscuro) recorre el panel como un usuario:
carga, QR, anular, emparejar (el iPhone se simula con fetch a
POST /api/v1/pair desde la propia pagina), dispositivos, revocar con
confirmacion, clave corta y clave falsa (PRIM la rechaza), cuota, salud,
Ollama, andenes, errores, ajustes con error y panel sin conexion.
"""
import json
import sys

OUT = sys.argv[1].rstrip("/\\")
BASE = "http://127.0.0.1:7796"

SIZES = {"movil": (390, 844), "pc": (1440, 900)}
SCHEMES = {"claro": "light", "oscuro": "dark"}

FAKE_KEY = "CLAVEFALSA1234567890"

# --- trozos de JS -----------------------------------------------------------
def into(sel):
    return f"document.querySelector('{sel}').scrollIntoView({{block:'start'}});"

def sleep(ms):
    return f"await new Promise(r=>setTimeout(r,{ms}));"

def js_async(*parts):
    return "(async()=>{" + "".join(parts) + "})()"

PAIR_FETCH = (
    "await fetch('/api/v1/pair',{method:'POST',headers:{'Content-Type':'application/json'},"
    "body:JSON.stringify({code:document.getElementById('pair-code').textContent,"
    "device_name:'iPhone de Isma',device_model:'iPhone17,1',app_version:'2.0'})});"
)

def shots_for(size, scheme):
    w, h = SIZES[size]
    sch = SCHEMES[scheme]
    suf = f"{size}-{scheme}"
    common = {"width": w, "height": h, "dpr": 2, "scheme": sch, "reducedMotion": True}

    def shot(name, **kw):
        s = dict(common)
        s.update(kw)
        s.setdefault("url", "/")
        s["out"] = f"{OUT}/{name}-{suf}.png"
        return s

    def same(name, **kw):
        return shot(name, sameUrl=True, **kw)

    return [
        # 1. la carga: cabecera, resumen, avisos (arriba del todo)
        shot("01-panel", loadMs=2500, waitMs=800),
        # 2. emparejar en reposo
        same("02-emparejar-reposo", eval=into("#emparejar"), waitMs=600, selector="#emparejar"),
        # 3. QR con codigo y cuenta atras
        same("03-emparejar-qr", eval=into("#emparejar") + "document.getElementById('pair-start').click();",
             waitMs=1800, selector="#emparejar"),
        # 4. anulado
        same("04-emparejar-anulado", eval="document.getElementById('pair-cancel').click();",
             waitMs=1200, selector="#emparejar"),
        # 5. otro codigo y el iPhone (fetch) lo canjea: «Emparejado»
        same("05-emparejar-emparejado",
             eval=js_async("document.getElementById('pair-restart').click();", sleep(1500), PAIR_FETCH, sleep(3200)),
             waitMs=800, selector="#emparejar"),
        # 6. dispositivos con el iPhone recien emparejado
        same("06-dispositivos", eval=into("#dispositivos"), waitMs=1200, selector="#dispositivos"),
        # 7. revocar: dialogo de confirmacion (pantalla entera: el dialogo es modal)
        same("07-dispositivos-revocar-dialogo",
             eval="document.querySelector('#dev-list .btn-danger-soft').click();", waitMs=900),
        # 8. revocado: lista vacia y aviso flotante
        same("08-dispositivos-revocado", eval="document.getElementById('dlg-ok').click();", waitMs=1500),
        # 9. clave: sin clave (recuadro rojo y formulario)
        same("09-clave-sin-clave", eval=into("#clave"), waitMs=600, selector="#clave"),
        # 10. clave demasiado corta (lo para el propio panel, sin llamar al servidor)
        same("10-clave-corta",
             eval=into("#clave") + "document.getElementById('key-input').value='corta';"
                  "document.getElementById('key-submit').click();", waitMs=700, selector="#clave"),
        # 11. clave falsa: PRIM la rechaza (422) y el campo se vacia
        same("11-clave-rechazada",
             eval=js_async(into("#clave"),
                           f"document.getElementById('key-input').value='{FAKE_KEY}';",
                           "document.getElementById('key-submit').click();", sleep(7000)),
             waitMs=600, selector="#clave"),
        # 12-15. cuota, salud, ollama, andenes
        same("12-cuota", eval=into("#cuota"), waitMs=700, selector="#cuota"),
        same("13-salud", eval=into("#salud"), waitMs=700, selector="#salud"),
        same("14-traduccion-ollama", eval=into("#traduccion"), waitMs=700, selector="#traduccion"),
        same("15-andenes", eval=into("#andenes"), waitMs=700, selector="#andenes"),
        # 16. errores recientes, desplegados
        same("16-errores", eval="document.getElementById('err-details').open=true;" + into("#errores"),
             waitMs=700, selector="#errores"),
        # 17. ajustes del QR con las direcciones guardadas
        same("17-ajustes", eval=into("#ajustes"), waitMs=700, selector="#ajustes"),
        # 18. ajustes: direccion con ruta (error del panel, sin llamar al servidor)
        same("18-ajustes-error",
             eval=into("#ajustes") + "document.getElementById('set-lan').value='http://192.168.1.10:7796/api';"
                  "document.getElementById('set-save').click();", waitMs=700, selector="#ajustes"),
        # 19. sin conexion: la red falla y el panel lo dice (fetch rechazado desde la pagina)
        same("19-sin-conexion",
             eval="window.scrollTo(0,0);window.fetch=()=>Promise.reject(new TypeError('sin red'));"
                  "document.getElementById('refresh').click();", waitMs=1200),
    ]


def gifs():
    """GIF en movil claro, a 1x (390x844 exactos), con animaciones."""
    w, h = SIZES["movil"]
    common = {"width": w, "height": h, "dpr": 1, "scheme": "light", "reducedMotion": False, "url": "/"}

    def gif(name, frames, interval, **kw):
        s = dict(common)
        s.update(kw)
        s["gif"] = {"frames": frames, "intervalMs": interval}
        if "evalEach" in kw:
            s["gif"]["evalEach"] = s.pop("evalEach")
        s["out"] = f"{OUT}/{name}.gif"
        return s

    return [
        # generar el QR y ver correr la cuenta atras (unos 12 s)
        gif("gif-1-generar-qr-cuenta-atras", 22, 550, loadMs=2500,
            eval=into("#emparejar") + "document.getElementById('pair-start').click();", waitMs=300,
            selector="#emparejar"),
        # el iPhone canjea el codigo en el 4.o fotograma y el panel pasa a «Emparejado»
        gif("gif-2-paso-a-emparejado", 16, 500, sameUrl=True, waitMs=200, selector="#emparejar",
            evalEach="window.__f=(window.__f||0)+1;if(window.__f===4){" + PAIR_FETCH.replace("await ", "") + "}"),
        # revocar el iPhone recien emparejado: dialogo, confirmar, lista vacia y aviso
        gif("gif-3-revocar-dispositivo", 22, 450, sameUrl=True, eval=into("#dispositivos"), waitMs=1500,
            evalEach="window.__g=(window.__g||0)+1;"
                     "if(window.__g===3){document.querySelector('#dev-list .btn-danger-soft').click();}"
                     "if(window.__g===10){document.getElementById('dlg-ok').click();}"),
        # pegar una clave falsa: «Probando con PRIM…» y el rechazo con motivo
        gif("gif-4-clave-rechazada", 24, 500, sameUrl=True, eval=into("#clave"), waitMs=600,
            evalEach="window.__k=(window.__k||0)+1;"
                     f"if(window.__k===2){{document.getElementById('key-input').value='{FAKE_KEY}';"
                     "document.getElementById('key-submit').click();}"),
    ]


plan = {"base": BASE, "shots": []}
for size in SIZES:
    for scheme in SCHEMES:
        plan["shots"] += shots_for(size, scheme)
plan["shots"] += gifs()
json.dump(plan, sys.stdout, ensure_ascii=False, indent=1)
