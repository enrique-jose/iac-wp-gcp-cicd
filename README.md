# WordPress en GCP con CI/CD (Terraform + Cloud Build)

WordPress en **Cloud Run**, con **Cloud SQL MySQL**, **Memorystore for Valkey** y un **HTTP Load Balancer**, desplegado con **Terraform** desde **Cloud Build**. Incluye un dashboard y alertas de Backend y Bases de datos como código.

| | |
|---|---|
| Proyecto | `cool-academy-489503-f3` |
| Región | `us-east1` |
| Prefijo de recursos | `wp-cicd` |
| Aplicación | [`enrique-jose/demo-wp`](https://github.com/enrique-jose/demo-wp), fork de WordPress |

## Documentación

| # | Documento | Contenido |
|---|---|---|
| 1 | [Architecture](docs/1-Architecture.md) | Visión general, componentes, flujo de una petición y decisiones de diseño |
| 2 | [Infrastructure](docs/2-Infrastructure.md) | Módulos de Terraform, red, recursos, variables y cómo cambiar la infra |
| 3 | [CI/CD](docs/3-Ci-cd.md) | Bootstrap, triggers, pipelines, aprobaciones y rollback |
| 4 | [Application](docs/4-Application.md) | Fork `demo-wp`, imagen, configuración de WordPress y actualizaciones |
| 5 | [Data](docs/5-Data.md) | Cloud SQL, Valkey, backups y restauración, estado de Terraform |
| 6 | [Security](docs/6-Security.md) | Service accounts, IAM, secretos, red, org policies y mejoras pendientes |
| 7 | [Observability](docs/7-Observability.md) | Dashboard, alertas, uptime check, logs y runbooks |

## Estructura del repo

```
bootstrap/        # se aplica UNA vez en local: bucket de estado, AR, secret, SAs, repos y triggers
infra/            # stack de WordPress, aplicado por Cloud Build
  cloudbuild/     # infra-plan · infra-apply · infra-destroy
  env/            # prod.tfvars (sin secretos)
  modules/        # networking · database · cache · cloudrun · monitoring
docs/             # documentación
```

## Inicio rápido

| Quiero… | Hago… |
|---|---|
| Cambiar la infraestructura | PR que toque `infra/` → `wp-cicd-infra-plan` → merge → aprobar `wp-cicd-infra-apply` ([CI/CD](docs/3-Ci-cd.md#aprobar-un-build)) |
| Desplegar WordPress, temas o plugins | PR en `demo-wp` → merge → `wp-cicd-app-deploy` ([Application](docs/4-Application.md#desarrollo)) |
| Hacer rollback de la app | `gcloud run services update-traffic wp-cicd-service --region us-east1 --to-revisions=<REV>=100` ([CI/CD](docs/3-Ci-cd.md#rollback-manual)) |
| Ver el estado del sitio | Dashboard `wp-cicd · WordPress` ([Observability](docs/7-Observability.md)) |
| Montarlo desde cero | [CI/CD → Puesta en marcha desde cero](docs/3-Ci-cd.md#puesta-en-marcha-desde-cero) |
