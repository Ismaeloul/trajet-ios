# Pendiente

Lo que no he podido cerrar yo solo, con el detalle para retomarlo.

## ~~Copia de la base de datos de producción (`trajet.db`)~~ — descartado

Dijiste (24-09-2026) que da igual y que prefieres **empezar de cero**. La
migración de una BD 0.3.0 está probada con una BD sintética del esquema exacto
(y sigue ahí por si algún día instalas encima); el test contra la copia real
simplemente se salta.

## ⚠️ Rotar la clave PRIM de pruebas (incidente)

- **Qué pasó**: al validar el `docker-compose.yml` del store con
  `docker compose config`, Docker Compose sustituyó `${PRIM_API_KEY:-}` por la
  variable de entorno de la sesión y **el valor de la clave salió en la salida
  de esa orden**, dentro de la transcripción de la sesión. No está en ningún
  fichero, log, commit ni imagen (comprobado con `grep -rF` en los tres repos
  y en la carpeta temporal).
- **Qué hacer**: como es la clave de pruebas que ibas a destruir al terminar,
  basta con **destruirla / regenerarla en PRIM** en cuanto leas esto.
- **Cómo lo evito desde entonces**: las órdenes de Docker y de pytest se
  lanzan con `env -u PRIM_API_KEY`, y las pruebas reales solo leen la clave
  del entorno dentro de `tests/real`.

## Publicar la 0.4.0 en el Umbrel (lo haces tú)

> **Orden importante**: primero instala y empareja la app nueva del iPhone (FASE 3). Con la 0.4.0 la web desaparece y `/api/*` queda detrás del login de Umbrel: hasta tener el iPhone emparejado no verías el tablero en ningún sitio. Mientras tanto puedes dejar el stack de `~/trajet` (0.3.0) como está.

1. `trajet-server/README.md` → «Desplegar en el Umbrel»: `git pull` en el NAS
   y `bash scripts/publish.sh 0.4.0` (construye y publica en el registro
   local `localhost:5000`).
2. **Push del store**: la 0.4.0 está preparada en un commit **local**
   (`umbrel-app-store`, rama `rewrite-v2`) con el push bloqueado a propósito.
   Revísalo, fusiónalo en `main` y haz push tú.
3. Actualizar la app desde la tienda de Umbrel, abrir el panel, pegar la
   clave PRIM y emparejar el iPhone.
- Sin probar en tu NAS: las órdenes `umbreld client apps.stop/start` del
  README y que el `data/.gitkeep` del store haga que la carpeta de datos
  exista con dueño 1000 al instalar.
