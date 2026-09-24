export const meta = {
  name: 'trajet-fase3-verificacion',
  description: 'FASE 3 etapa D: verificación independiente de la app iOS (reglas y funcionalidad, seguridad/ATS/concurrencia, diseño en las capturas)',
  phases: [{ title: 'Verificar', detail: '3 verificadores independientes, solo lectura' }],
}

const ROOT = 'C:\\Users\\Isma\\Desktop\\Trajet v2'

const FINDINGS = {
  type: 'object',
  properties: {
    resumen: { type: 'string' },
    comprobado: { type: 'array', items: { type: 'string' } },
    hallazgos: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          gravedad: { type: 'string', enum: ['alta', 'media', 'baja'] },
          area: { type: 'string' },
          fichero: { type: 'string' },
          descripcion: { type: 'string' },
          evidencia: { type: 'string', description: 'Línea de código, captura o test que lo demuestra. Sin evidencia no es hallazgo.' },
          arreglo: { type: 'string' },
        },
        required: ['id', 'gravedad', 'area', 'fichero', 'descripcion', 'evidencia', 'arreglo'],
      },
    },
  },
  required: ['resumen', 'comprobado', 'hallazgos'],
}

const COMUN = `
Eres un VERIFICADOR INDEPENDIENTE y escéptico de la app iOS de Trajet (SwiftUI, Swift 6 estricto, iOS 17+, repo ${ROOT}, rama rewrite-v2). Otros agentes la han escrito; tu trabajo es encontrar lo que está MAL. No hay Mac en este PC: no puedes compilar; lo que sí tienes es el código, los tests, los informes del CI (\`gh run view <id> -R Ismaeloul/trajet-ios --log\`, solo lectura) y las capturas del simulador (artefacto Trajet-capturas-N de la última ejecución en verde en modo capturas: \`gh run list -R Ismaeloul/trajet-ios -L 5\` y \`gh run download <id> -R Ismaeloul/trajet-ios -n <nombre> -D <carpeta temporal del sistema>\`; también hay una selección en ${ROOT}\\docs\\capturas\\app).
Documentación: ${ROOT}\\PROMPT-trajet-v2.md (el encargo: FASE 3 y sección 2), ${ROOT}\\docs\\reglas.md (R1–R62 con el test que las cubre), docs\\inventario-funcional.md (F1–F82 de la v1 que no pueden perderse), docs\\app-v2.md y app-v2-api.md, docs\\decisiones.md, docs\\diseno\\sistema.md (aspecto) y docs\\diseno\\decisiones-la-widgets.md (Live Activity y widgets), docs\\openapi.yaml (contrato).
Reglas duras: NO modifiques ningún fichero del repo (solo lectura). No llames a producción ni a PRIM. Solo cuenta como hallazgo lo que puedas demostrar (línea concreta con el razonamiento, captura, test). Gravedad: alta = regla de la sección 2 rota, funcionalidad de la v1 perdida, fallo de seguridad o algo que impediría usar la app; media = fallo real con impacto limitado; baja = detalle. Devuelve el resultado con la herramienta de salida estructurada, en español.
`

const REGLAS = `${COMUN}
TU ENFOQUE: REGLAS y FUNCIONALIDAD. (1) Recorre docs/reglas.md R1–R62 y para cada una lee el código de la app que la implementa (no solo el test): ¿se cumple de verdad? Presta atención especial a R2/R3/R10 (vía real sólida con «Vía» y latido, probable punteada con «probable», sin hueco en metro/bus/tranvía), R4/R14, R5, R6 (1h46), R7 (bucle solo con la pantalla delante o en trayecto: busca cualquier Timer/Task que refresque en segundo plano), R8, R9 (nunca pantalla en blanco: busca sitios donde el tablero se ponga a nil o se vacíe), R11, R12, R13, R17–R19, R29, R40, R42–R44, R51–R52. (2) Recorre docs/inventario-funcional.md F1–F82 y comprueba en el código que cada funcionalidad existe en la v2 (pantalla, acción, estado, endpoint que se llama y cuándo); lista las perdidas o a medias. (3) Modo trayecto (docs/app-v2.md, PROMPT 3.4): se activa a mano, precisión baja, allowsBackgroundLocationUpdates solo mientras dura, se apaga al llegar / tiempo máximo / a mano / desde la Live Activity, geocercas, permiso denegado no rompe nada. (4) Live Activity y widgets (PROMPT 3.5 y decisiones-la-widgets.md): que lo implementado sea la variante A corregida (cuenta atrás que corre sola, antigüedad siempre visible, siguiente tren, parar con App Intent, deep link, lite sin nada de esto y detección en tiempo de ejecución).`

const SEGURIDAD = `${COMUN}
TU ENFOQUE: SEGURIDAD, RED, CONCURRENCIA y ROBUSTEZ. (1) ATS en Trajet/App/Info.plist e Info-Lite.plist: sin NSAllowsArbitraryLoads; excepciones acotadas (local, 100.64.0.0/10, ts.net); textos de permisos en español y completos; UIBackgroundModes solo location; NSSupportsLiveActivities solo en la full. (2) Token: en el Llavero (Keychain.swift), nunca en UserDefaults ni logs ni en la caché del App Group; se borra al desemparejar; Authorization solo a las direcciones del servidor; qué pasa con un 401 (revocado) — ¿la app vuelve a emparejar sin borrar la pantalla? (3) Datos en el App Group (BoardCache): ¿contienen algo sensible? (4) Concurrencia Swift 6: busca `nonisolated(unsafe)`, `@unchecked Sendable`, `Task.detached`, `DispatchQueue.main`, estado global mutable, closures que capturan estado de MainActor desde un actor, `Timer` sin invalidar, tareas que no se cancelan al desaparecer la vista (fugas del bucle de 30 s), race conditions en BoardStore (refresh y selectRoute a la vez), en TripController (stop mientras start) y en la Live Activity (updates tras end). (5) Decodificación tolerante y errores: ¿algún `try!`, `!` sobre opcionales de red, `fatalError`, `precondition` alcanzable con datos del servidor? ¿Un JSON raro puede tumbar la app? (6) Extensión: nada de Trajet/App en Shared, nada de APIs no disponibles en extensiones, presupuesto de recargas de WidgetKit respetado. (7) Demo/DEBUG: que nada del modo demo (DemoServer, PreviewData, código DEMO-2026) llegue a Release (#if DEBUG) y que el argumento -demo no funcione en Release. (8) CI y scripts (ios.yml, scripts/ci-*.sh): que las IPA se generen bien (full con App Group y extensión; lite sin), que no se filtre nada en artefactos, y que un tag v* cree la Release.`

const DISENO = `${COMUN}
TU ENFOQUE: DISEÑO, ACCESIBILIDAD y las CAPTURAS. Descarga el artefacto de capturas de la última ejecución en verde en modo capturas (o usa docs/capturas/app) y revisa TODAS las capturas con la herramienta Read (iPhone SE, 16, 16 Pro Max; claro, oscuro, letra grande): textos cortados o a mitad de palabra, solapes, elementos fuera de la zona segura, contraste pobre (minutos y vía tienen que leerse a contraluz: opacos, nunca sobre cristal), huecos vacíos, jerarquía (minutos protagonistas, R48), vía real/probable distinguibles por forma y palabra (R10), sin hueco de vía en metro/bus (R3), 1h46 (R6), «En andén» ≠ «ya» (R15), antigüedad siempre visible (R17/R18), tablero apagado con dato viejo (R19), estados vacío/carga/error/sin conexión/servidor sin clave diseñados (R9, R53), letra grande sin romper la maqueta (R47, tipografía con tope), que no queden restos de la estética anterior (oscuro con halos/grano/Archivo) y fidelidad a docs/diseno/sistema.md (paleta, radios, cristal solo en controles, tarjetas opacas, distintivos de línea con contraste). Comprueba en el código lo que las capturas no enseñan: Dynamic Type (fuentes escalables, no tamaños fijos sin escalar), VoiceOver (etiquetas en cada control, R50), objetivos ≥ 44 pt (R52), «Reducir movimiento» (R51: latidos, muelles y numericText con alternativa), «Reducir transparencia» (cristal → opaco), y que las animaciones pedidas existen (numericText en minutos, vía que aparece con háptica, matchedGeometry/zoom tablero→mapa, línea del trayecto dibujándose, symbolEffect, pulso sutil). Icono nuevo «Cristal» con variantes clara/oscura/tintada: ¿existe en Assets (AppIcon con appearances) o sigue el icono viejo? Cada hallazgo con la captura (nombre del fichero) o la línea.`

phase('Verificar')
const r = await parallel([
  () => agent(REGLAS, { label: 'verif: reglas y funcionalidad', phase: 'Verificar', schema: FINDINGS }),
  () => agent(SEGURIDAD, { label: 'verif: seguridad y concurrencia', phase: 'Verificar', schema: FINDINGS }),
  () => agent(DISENO, { label: 'verif: diseño y capturas', phase: 'Verificar', schema: FINDINGS }),
])
return { reglas: r[0], seguridad: r[1], diseno: r[2] }
