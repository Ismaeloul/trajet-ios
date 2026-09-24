#!/usr/bin/env bash
# Capturas automaticas (modo «capturas» del CI): CapturasUITests sobre lo que
# ya compilo el paso de compilar (build/sim), en
#   iPhone SE (3.a gen.), iPhone 16 y iPhone 16 Pro Max, en claro y oscuro,
#   y el iPhone 16 con letra grande (accessibility-large),
# con la barra de estado limpia (9:41, wifi, bateria llena).
# Cada juego queda en build/capturas/<dispositivo>-<modo>/*.png (nombre claro);
# el .xcresult de cada pasada, en build/capturas-<dispositivo>-<modo>.xcresult.
#
# Uso: bash scripts/ci-capturas.sh [pasada…]
#   sin argumentos, las siete pasadas en fila (mas de dos horas: el CI las
#   reparte en varios trabajos); con argumentos, solo esas, p. ej.
#   bash scripts/ci-capturas.sh iphone-16-claro iphone-16-oscuro
set -uo pipefail
cd "$(dirname "$0")/.."
raiz="$PWD/build/capturas"
mkdir -p "$raiz"

# modelo del simulador | carpeta | modo (claro | oscuro | letra-grande)
todas=(
  "iPhone 16|iphone-16|claro"
  "iPhone 16|iphone-16|oscuro"
  "iPhone SE (3rd generation)|iphone-se|claro"
  "iPhone SE (3rd generation)|iphone-se|oscuro"
  "iPhone 16 Pro Max|iphone-16-pro-max|claro"
  "iPhone 16 Pro Max|iphone-16-pro-max|oscuro"
  "iPhone 16|iphone-16|letra-grande"
)
if [ $# -gt 0 ]; then
  pasadas=()
  for pedida in "$@"; do
    encontrada=0
    for p in "${todas[@]}"; do
      IFS='|' read -r modelo carpeta modo <<< "$p"
      if [ "$carpeta-$modo" = "$pedida" ]; then pasadas+=("$p"); encontrada=1; fi
    done
    if [ "$encontrada" = 0 ]; then
      echo "pasada desconocida: $pedida (valen: $(for p in "${todas[@]}"; do IFS='|' read -r _ c m <<< "$p"; printf '%s ' "$c-$m"; done))"
      exit 2
    fi
  done
else
  pasadas=("${todas[@]}")
fi

fallo=0
for pasada in "${pasadas[@]}"; do
  IFS='|' read -r modelo carpeta modo <<< "$pasada"
  echo "==> $modelo · $modo"
  if ! UDID=$(bash scripts/ci-sim.sh "$modelo" "Trajet-capturas-$carpeta"); then
    echo "    no se ha podido crear el simulador"; fallo=1; continue
  fi

  # Aspecto y tamano de letra.
  case "$modo" in
    oscuro)       aspecto=dark;  letra=large ;;
    letra-grande) aspecto=light; letra=accessibility-large ;;
    *)            aspecto=light; letra=large ;;
  esac
  xcrun simctl ui "$UDID" appearance "$aspecto" || echo "    (no se ha podido poner el aspecto $aspecto)"
  xcrun simctl ui "$UDID" content_size "$letra" || echo "    (no se ha podido poner la letra $letra)"
  # Barra de estado limpia.
  xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 \
    || echo "    (no se ha podido limpiar la barra de estado)"

  destino="$raiz/$carpeta-$modo"
  rm -rf "$destino"; mkdir -p "$destino"
  resultado="build/capturas-$carpeta-$modo.xcresult"
  rm -rf "$resultado"
  registro="build/capturas-$carpeta-$modo.log"

  empieza=$(date +%s)
  if ! TEST_RUNNER_TRAJET_CAPTURAS_DIR="$destino" TEST_RUNNER_TRAJET_CAPTURAS_MODO="$modo" \
      xcodebuild test-without-building \
        -project Trajet.xcodeproj -scheme Trajet \
        -destination "id=$UDID" \
        -derivedDataPath build/sim \
        -only-testing:TrajetUITests/CapturasUITests \
        -resultBundlePath "$resultado" > "$registro" 2>&1; then
    fallo=1
    echo "    algun paso ha fallado (se sigue con las capturas que haya):"
    grep -E "error:|failed|Failing tests|\*\* TEST" "$registro" | head -40 || true
  fi
  # Si el test no pudo escribir en la carpeta, se sacan los adjuntos del .xcresult.
  if [ -z "$(ls -A "$destino" 2>/dev/null)" ] && [ -d "$resultado" ]; then
    echo "    la carpeta esta vacia: se exportan los adjuntos del .xcresult"
    xcrun xcresulttool export attachments --path "$resultado" --output-path "$destino" >/dev/null 2>&1 || true
  fi
  echo "    $(find "$destino" -name '*.png' | wc -l | tr -d ' ') capturas en $destino ($(( ($(date +%s) - empieza) / 60 )) min)"
  # Cuanto ha tardado cada test, para saber donde se va el tiempo.
  grep -E "Test Case '.*' (passed|failed)" "$registro" | sed -E "s/.*CapturasUITests (test[A-Za-z0-9]+)\]' (passed|failed) \(([0-9.]+) seconds\)\./      \1: \2, \3 s/" || true
  xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
done

echo "--- resumen"
find "$raiz" -name '*.png' | sed "s|$raiz/||" | sort | awk -F/ '{n[$1]++} END {for (d in n) print "  " d ": " n[d] " png"}' | sort
exit $fallo
