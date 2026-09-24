#!/usr/bin/env bash
# Crea (o reutiliza) un simulador con el runtime de iOS mas nuevo, lo arranca,
# lo deja listo para los tests y escribe su UDID (solo el UDID va por stdout).
# Uso: UDID=$(bash scripts/ci-sim.sh "iPhone 16" Trajet-16)
set -euo pipefail
modelo=${1:-iPhone 16}
nombre=${2:-Trajet-sim}
runtime=$(xcrun simctl list runtimes -j | python3 -c '
import json,sys
rs=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS")]
rs.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(rs[-1]["identifier"])')
tipo=$(xcrun simctl list devicetypes -j | python3 -c '
import json,sys
m=sys.argv[1]
ts=[t for t in json.load(sys.stdin)["devicetypes"] if t["name"]==m]
print(ts[0]["identifier"])' "$modelo")
existente=$(xcrun simctl list devices -j | python3 -c '
import json,sys
n=sys.argv[1]
for rt,ds in json.load(sys.stdin)["devices"].items():
    for d in ds:
        if d["name"]==n and d.get("isAvailable"): print(d["udid"]); raise SystemExit
' "$nombre")
if [ -n "$existente" ]; then udid=$existente; else udid=$(xcrun simctl create "$nombre" "$tipo" "$runtime"); fi

# Arrancado (si ya lo estaba, no pasa nada).
xcrun simctl boot "$udid" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
# Sin el aviso del teclado «desliza para escribir» (en el simulador sale la
# primera vez que se escribe y tapa el formulario: el boton de emparejar
# quedaba debajo y las capturas salian con el aviso).
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true >/dev/null 2>&1 || true
xcrun simctl spawn "$udid" defaults write com.apple.Preferences UIKeyboardDidShowInternationalInfoIntroduction -bool true >/dev/null 2>&1 || true
echo "$udid"
