# Tycho Indexer Deployment

This directory contains the GraphOps deployment packaging for Tycho Indexer.
It is centered on the Helm chart in `deploy/tycho-indexer` and the
`Dockerfile.graphops` image at the repository root.

## What This Ships

- A Helm chart for running `tycho-indexer` as either a `Deployment` or a
  `StatefulSet`.
- A GraphOps image contract based on `Dockerfile.graphops`.
- An embedded migration helper binary, `tycho-migration-runner`, used by the
  chart before the application starts.
- A preflight SQL step that applies desired pg_partman settings at deployment
  time and bootstraps required partitions.
- A bundled Grafana dashboard for Tycho Indexer SRE visibility.
- Optional Prometheus `ServiceMonitor` and Grafana dashboard resources.
- Optional ConfigMap-mounted `extractors.yaml` support.

## Image Contract

`Dockerfile.graphops` builds on top of an upstream Tycho Indexer image:

```sh
docker build \
  -f Dockerfile.graphops \
  --build-arg BASE_IMAGE=<upstream-tycho-indexer-image> \
  -t <registry>/tycho-indexer:<tag> \
  .
```

The image adds two deployment-critical assets:

- `/usr/local/bin/tycho-migration-runner`, compiled from
  `graphops/migration-runner`.
- `/opt/tycho-indexer/substreams`, copied from the repository `substreams/`
  directory.

The `substreams/` directory must exist before building the image. Its `.spkg`
files are bundled into the runtime image and are expected to match the
extractor configuration deployed with the chart.

## Helm Chart

The chart lives at `deploy/tycho-indexer`.

Install or upgrade with:

```sh
helm upgrade --install tycho-indexer ./deploy/tycho-indexer \
  --namespace tycho-indexer \
  --create-namespace \
  -f values.yaml
```

At minimum, deployment values must provide:

- `image.repository` and usually `image.tag`, pointing at the image built from
  `Dockerfile.graphops`.
- Database connection material, either through `database.url` or
  `database.fragments`.
- Runtime secrets such as `SUBSTREAMS_API_TOKEN` and `AUTH_API_KEY`.
- Chain/RPC and extractor-specific configuration required by the selected
  indexer args.

The default command is:

```yaml
command:
  - /opt/tycho-indexer/tycho-indexer
  - index
```

Arguments can be supplied as an ordered list, a map, or a map plus
`argsOrder`. The chart defaults to rendering `--endpoint`.

## Startup Flow

When enabled, the chart starts init containers before the main indexer
container:

1. `run-db-migrations`
   Runs `/usr/local/bin/tycho-migration-runner` from the application image.
   The binary uses `DATABASE_URL` and applies the embedded Diesel migrations
   from `crates/tycho-storage/migrations`.

2. `run-preflight-sql`
   Runs `psql` from the configured Postgres image and applies the configured
   preflight SQL after the database is reachable.

3. `tycho-indexer`
   Starts the application container once migrations and preflight work have
   completed successfully.

Both init containers share the application environment by default
(`shareAppEnv: true`) so they can use the same `DATABASE_URL` assembly and
secret sources as the main container.

## Database Configuration

The chart can assemble `DATABASE_URL` from fragments:

```yaml
database:
  fragments:
    host:
      secretKeyRef:
        name: tycho-db
        key: host
    port:
      value: "5432"
    name:
      value: tycho
    user:
      secretKeyRef:
        name: tycho-db
        key: user
    password:
      secretKeyRef:
        name: tycho-db
        key: password
```

Alternatively, provide `database.url` directly from a secret or value.

## Migrations

Database migrations are controlled by `dbMigrations`.

```yaml
dbMigrations:
  enabled: true
  retrySeconds: 5
```

The migration init container waits for the database endpoint, then executes
`tycho-migration-runner`. This requires the GraphOps image because the upstream
image does not contain that helper binary.

## pg_partman Preflight SQL

`preflightSql` declaratively aligns pg_partman settings for the partitioned
Tycho tables used by storage:

- `public.protocol_state`
- `public.contract_storage`
- `public.component_balance`

The default SQL updates `partman.part_config`, creates requested backfill and
future partitions, clears temporary pg_partman staging tables, and runs
partition data movement/maintenance.

The repository-level `preflight.sql` is the standalone form of this maintenance
workflow. The chart can run SQL inline from values, or consume an externally
managed ConfigMap if the script is managed outside the chart.

Primary knobs:

```yaml
preflightSql:
  enabled: true
  env:
    TYCHO_PARTMAN_PARTITION_INTERVAL: "1 day"
    TYCHO_PARTMAN_PREMAKE: "7"
    TYCHO_PARTMAN_RETENTION: "1 month"
    TYCHO_PARTMAN_BACKFILL_START: "2020-05-05T20:10:37Z"
    TYCHO_PARTMAN_BOOTSTRAP_FUTURE_DAYS: "0"
```

The SQL can be supplied inline through `preflightSql.sql.statements`, or by
referencing an existing ConfigMap with `preflightSql.sql.configMapName` and
`preflightSql.sql.configMapKey`.

## Extractors and Substreams

The runtime image contains `.spkg` files under `/opt/tycho-indexer/substreams`.
The chart can also mount an extractor configuration file:

```yaml
extractors:
  enabled: true
  fileName: extractors.yaml
  mountPath: /opt/tycho-indexer
  data: |
    # extractor configuration
```

Keep the extractor configuration, chart values, and bundled `.spkg` files in
sync. A chart deployment can succeed while the indexer later fails if the image
does not contain the referenced substream package.

## Observability

The chart exposes:

- HTTP service port `4242`.
- Metrics service port `9898`.
- Optional Prometheus `ServiceMonitor`.
- A bundled Grafana dashboard:
  `deploy/tycho-indexer/dashboards/tycho-indexer-sre-overview.json`.

The included dashboard is `Tycho Indexer SRE Overview`. It is packaged with the
chart under `dashboards/` and can be deployed either as a plain ConfigMap for a
Grafana dashboard sidecar or as Grafana Operator `GrafanaDashboard` resources.
It assumes Prometheus is scraping the indexer metrics endpoint and uses the
chart's metrics service port by default.

Enable Prometheus scraping:

```yaml
serviceMonitor:
  enabled: true
```

Enable dashboard ConfigMap sidecar support:

```yaml
grafana:
  dashboards:
    enabled: true
```

Enable Grafana Operator `GrafanaDashboard` resources:

```yaml
grafana:
  dashboards:
    enabled: true
  operatorDashboards:
    enabled: true
    instanceSelector:
      matchLabels:
        dashboards: grafana
```

## Operational Notes

- `preflightSql` assumes pg_partman is installed and the relevant parent tables
  already exist.
- `dbMigrations.enabled` requires `image.repository` to be set.
- The default probes use `/v1/health` on the `http` port.
- ConfigMaps and init scripts are rendered one sync wave before the workload for
  Argo CD users.
- The default workload kind is `Deployment`; set `workload.kind: StatefulSet`
  when stable pod identity is required.
