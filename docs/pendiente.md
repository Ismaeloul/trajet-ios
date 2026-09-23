# Pendiente

Lo que no he podido cerrar yo solo, con el detalle para retomarlo.

## Copia de la base de datos de producción (`trajet.db`)

- **Qué**: el encargo pide una copia de `/data/trajet.db` (solo lectura) para
  probar las migraciones contra datos reales.
- **Qué pasó**: la base de datos que usa el servidor en marcha está en el NAS
  en `~/trajet/data/trajet.db` (el servidor que responde en el 7796 es el stack
  de `~/trajet`, no la app del store). Intenté copiarla por SSH en modo
  lectura y el control de permisos de la sesión lo **denegó** («lectura de
  datos de producción»). No lo he intentado esquivar.
- **Qué he hecho en su lugar**: los tests de migración usan una base de
  datos sintética con el **esquema exacto de producción 0.3.0** (sacado de
  `app/db.py`) y datos con la forma real. El test contra la copia real existe
  y se **salta solo** si no encuentra el fichero.
- **Qué tienes que hacer tú** (un minuto), desde PowerShell en `Trajet v2`:

  ```powershell
  scp umbrel@192.168.1.188:trajet/data/trajet.db trajet-server/.local/trajet-prod.db
  ```

  `trajet-server/.local/` está en `.gitignore`: la copia nunca sube a git.
  Luego: `cd trajet-server; python -m pytest tests/test_migraciones.py -k real`.
