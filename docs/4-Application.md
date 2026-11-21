# 4. Application

## El fork `demo-wp`

[`enrique-jose/demo-wp`](https://github.com/enrique-jose/demo-wp) es un **fork manual de [`WordPress/WordPress`](https://github.com/WordPress/WordPress)**, el mirror ya compilado de WordPress core.

| Remoto | URL | Uso |
|---|---|---|
| `origin` | `github.com/enrique-jose/demo-wp` | Nuestro repo, donde están los triggers de Cloud Build |
| `upstream` | `github.com/WordPress/WordPress` | Para traer releases nuevas |

- `main` parte de una **release** de WordPress (ahora **7.1.4**), no de `master`.
- Archivos propios del fork: `Dockerfile`, `.dockerignore`, `cloudbuild.yaml` y `README-FORK.md`.
- El código propio (temas, plugins y mu-plugins) se versiona en `wp-content/`.

## Imagen

```dockerfile
FROM wordpress:php8.3-apache
# 1. conserva wp-config-docker.php de la imagen oficial
# 2. sustituye /usr/src/wordpress por el código del fork
# 3. añade el plugin Redis Object Cache 3.0.0 y el drop-in object-cache.php
```

- **Base:** `wordpress:php8.3-apache`, para reutilizar su `docker-entrypoint.sh`. Al arrancar, el entrypoint copia `/usr/src/wordpress` a `/var/www/html` y genera `wp-config.php` a partir de las variables de entorno.
- **Object cache:** al copiar `object-cache.php` a `wp-content/`, el cache funciona desde el primer arranque, sin activar nada en wp-admin. El plugin solo hace falta para ver el estado o hacer flush.
- **Tags en Artifact Registry:** `:<SHORT_SHA>`, inmutable por commit, y `:main`, la última y usada como caché. Cloud Run se despliega **por digest** (`@sha256:…`).

## Configuración en tiempo de ejecución

Las variables de entorno las inyecta Terraform desde `modules/cloudrun`:

| Variable | Valor |
|---|---|
| `WORDPRESS_DB_HOST` | IP privada de Cloud SQL |
| `WORDPRESS_DB_NAME` / `WORDPRESS_DB_USER` | `wordpressdb` / `wpuser` |
| `WORDPRESS_DB_PASSWORD` | Secret Manager `wp-cicd-db-password` (`latest`) |
| `WORDPRESS_CONFIG_EXTRA` | Ver el bloque siguiente |

```php
define('WP_MEMORY_LIMIT', '256M');
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') { $_SERVER['HTTPS'] = 'on'; }
define('WP_REDIS_HOST', '<IP PSC de Valkey>');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_PREFIX', 'wp-cicd:');
```

Cambiar una de estas variables es un cambio de **infra**, que se hace con un PR en `iac-wp-gcp-cicd`. El `apply` crea una revisión nueva de Cloud Run con la imagen que esté desplegada en ese momento.

## Primera instalación

Después del primer `infra-apply` y del primer `app-deploy`:

1. Obtén la IP:
   ```bash
   gcloud compute addresses describe wp-cicd-lb-ip --global --format='value(address)'
   ```
2. Abre `http://<IP>` y completa el asistente: idioma, título del sitio, usuario admin y email.
3. En *wp-admin → Settings → Redis*, comprueba que el estado es **Connected**.

## Desarrollo

```bash
git clone https://github.com/enrique-jose/demo-wp.git && cd demo-wp
git remote add upstream https://github.com/WordPress/WordPress.git
git checkout -b feat/mi-cambio
# … cambios en wp-content/themes, wp-content/plugins …
docker build -t demo-wp . && docker run --rm -p 8080:80 \
  -e WORDPRESS_DB_HOST=host.docker.internal -e WORDPRESS_DB_USER=wp \
  -e WORDPRESS_DB_PASSWORD=wp -e WORDPRESS_DB_NAME=wp demo-wp
git push -u origin feat/mi-cambio   # abrir PR → wp-cicd-app-pr
```

Al hacer merge a `main`, `wp-cicd-app-deploy` despliega el cambio ([CI/CD](3-Ci-cd.md#pipeline-de-la-aplicación-demo-wpcloudbuildyaml)).

> Los plugins que se instalan desde wp-admin se escriben en el sistema de archivos del contenedor, que es efímero, y **se pierden** en el siguiente deploy o reinicio. Para conservar un plugin, añádelo al repo en `wp-content/plugins/` o descárgalo en el `Dockerfile`.

## Actualizar WordPress

```bash
git fetch upstream --tags
git checkout -b upgrade/7.1.5 main
git merge 7.1.5
git push -u origin upgrade/7.1.5     # PR → app-pr valida el build
```

Tras el merge, `app-deploy` despliega la versión nueva. Si la versión trae migraciones de base de datos, WordPress las pide en `wp-admin/upgrade.php` la primera vez que entra un admin. Antes de actualizar a una versión mayor, haz un backup manual ([Data](5-Data.md#backups-y-restauración)).

## Limitaciones conocidas

| Limitación | Alternativa |
|---|---|
| `wp-content/uploads` es efímero, así que los medios se pierden al reiniciar | Montar un bucket GCS como volumen de Cloud Run, o usar un plugin de offload a GCS |
| Solo HTTP (puerto 80) | Añadir un certificado gestionado y un proxy HTTPS al LB (ver [Security](6-Security.md#limitaciones-y-mejoras-recomendadas)) |
| Con varias instancias, los cambios en archivos (plugins o temas desde wp-admin) no se comparten entre ellas | Gestionar plugins y temas solo desde el repo |
