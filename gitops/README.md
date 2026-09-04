# GitOps (Argo CD)

Монорепозиторій для розгортання riverrise в Kubernetes через **Argo CD** (prod).

## Структура

```text
gitops/
├── bootstrap/           # Root Application (app-of-apps) — застосувати один раз
├── projects/            # AppProject (політики Argo CD)
├── apps/prod/           # Application (infra / databases / observability / services)
├── environments/prod/
│   ├── values/          # Helm valueFiles (root їх НЕ синкає як ресурси)
│   └── secrets/         # SealedSecret для sync
└── charts/
    ├── basic-chart/       # Спільний Helm для продуктових сервісів
    ├── network-policies/  # NetworkPolicy (зараз Application disabled)
    └── wrappers/          # Umbrella над офіційними чартами
```

| Каталог | Що це | Чи синкає root |
|---------|--------|----------------|
| `projects/` | `AppProject` | так |
| `apps/prod/…` | `Application` | так |
| `environments/prod/secrets/` | SealedSecret | так |
| `environments/prod/values/` | Helm values | **ні** (лише `helm.valueFiles`) |
| `charts/` | Helm charts | **ні** |
| `bootstrap/` | Root Application | вручну `kubectl apply` |

## Модель

- Один prod-кластер, Argo CD у кластері.
- Root: `apps/prod/…` + `environments/prod/secrets/…`.
- Сервіси → NS **`default`**.
- Інфра / БД / моніторинг → `gateway`, `sealed-secrets`, `databases`, `monitoring`.
- Ingress: **Cilium Gateway API**.

## Bootstrap

```bash
kubectl apply -n argocd -f gitops/bootstrap/root-application-prod.yaml
```

## Sync-wave

| Wave | Що |
|------|----|
| **-10** | `AppProject` |
| **-5** | Sealed Secrets key + Cilium (`gatewayAPI`) |
| **-4** | Sealed Secrets controller |
| **-1** | NetworkPolicies — **вимкнено** (`*.yaml.disabled`) |
| **0** | Cilium Gateway |
| **1** | Redis, RabbitMQ |
| **2** | Monitoring |
| **3** | Services (api, frontend, admin) |

## AppProject ↔ apps/

| Project | Каталог | Namespace |
|---------|---------|-----------|
| `services` | `apps/prod/services/` | `default` |
| `databases` | `apps/prod/databases/` | `databases` |
| `infra` | `apps/prod/infra/` | `gateway`, `sealed-secrets`, … |
| `observability` | `apps/prod/observability/` | `monitoring` |

## Charts

### `charts/basic-chart`

```yaml
path: gitops/charts/basic-chart
helm:
  valueFiles:
    - ../../environments/prod/values/services/<name>.yaml
```

Підтримує `env` / `envFrom`, HTTPRoute, HPA.

### `charts/network-policies`

`workloads` → NetworkPolicy (+ Cilium toFQDNs). Values: `environments/prod/values/network-policies.yaml`.

### `charts/wrappers/`

| Wrapper | Призначення |
|---------|-------------|
| `cilium-gateway` | Gateway entrypoint |
| `sealed-secrets` | Controller |
| `redis` / `rabbitmq` | Cache / broker |
| `monitoring` | Prometheus / Grafana / Loki / Alloy |

## Secrets

1. SealedSecret у `environments/prod/secrets/*.sealed.yaml`.
2. Tooling: `../sealed-secrets-keys/` → git@github.com:n0n3m4s/riverrise-secrets.git  
   (`clusters/prod/sealed-secrets/sealed-secrets-key.yaml`).

```bash
cd ../sealed-secrets-keys
./decrypt.sh prod all
./encrypt.sh prod all

# GHCR image pull (PAT: read:packages)
./make-ghcr-pull.sh <github-user> <PAT>
```

Секрети: `api`, `grafana-admin`, `redis-auth`, `rabbitmq-auth`, `ghcr-pull` (NS `default`, imagePullSecret).

## Gateway / HTTPRoute (Cilium)

| Host / path | Backend |
|-------------|---------|
| `riverrise.net/` | frontend |
| `riverrise.net/api` | api (strip `/api`) |
| `admin.riverrise.net/` | admin |

## NetworkPolicy

Підготовлено, Argo Application вимкнено (`application-network-policies.yaml.disabled`).

## Чеклист нового сервісу

1. `environments/prod/values/services/<name>.yaml`
2. `apps/prod/services/application-<name>.yaml`
3. (опційно) NetworkPolicy + SealedSecret

## Корисні команди

```bash
helm template api gitops/charts/basic-chart \
  -f gitops/environments/prod/values/services/api.yaml

helm template network-policies gitops/charts/network-policies \
  -f gitops/environments/prod/values/network-policies.yaml

cd gitops/charts/wrappers/<name> && helm dependency update
```
