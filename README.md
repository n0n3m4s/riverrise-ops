# GitOps (Argo CD)

Монорепозиторій для розгортання riverrise в Kubernetes через **Argo CD** (prod).

## Структура

```text
.
├── bootstrap/           # Root Application (app-of-apps) — застосувати один раз
├── projects/            # AppProject (політики Argo CD)
├── apps/prod/           # Application (infra / databases / observability / services)
├── environments/prod/
│   ├── namespaces/      # Namespace (root синкає першими, wave -11)
│   ├── values/          # Helm valueFiles (root їх НЕ синкає як ресурси)
│   └── secrets/         # SealedSecret — Application `secrets`
└── charts/
    ├── basic-chart/       # Спільний Helm для продуктових сервісів
    ├── network-policies/  # NetworkPolicy (зараз Application disabled)
    └── wrappers/          # Umbrella над офіційними чартами
```

| Каталог | Що це | Чи синкає root |
|---------|--------|----------------|
| `environments/prod/namespaces/` | `Namespace` | так |
| `projects/` | `AppProject` | так |
| `apps/prod/…` | `Application` | так |
| `environments/prod/secrets/` | SealedSecret | **ні** (Application `secrets`) |
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
kubectl apply -n argocd -f bootstrap/root-application-prod.yaml
```

## Sync-wave

| Wave | Що |
|------|----|
| **-11** | Namespaces (`databases`, `monitoring`, `gateway`, `sealed-secrets`) |
| **-10** | `AppProject` |
| **-5** | Sealed Secrets key + Cilium (`gatewayAPI`) |
| **-4** | Sealed Secrets controller |
| **-2** | `secrets` (SealedSecrets з `environments/prod/secrets`) |
| **-1** | NetworkPolicies — **вимкнено** (`*.yaml.disabled`) |
| **0** | Cilium Gateway |
| **1** | Redis, RabbitMQ |
| **2** | Monitoring |
| **3** | Services (api, frontend, admin) |

Усі дочірні Applications мають `syncPolicy.automated` — після `kubectl apply` bootstrap синкаються самі.

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
path: charts/basic-chart
helm:
  valueFiles:
    - ../../environments/prod/values/services/<name>.yaml
```

Підтримує `env` / `envFrom`, HTTPRoute, HPA.

### `charts/network-policies`

CiliumNetworkPolicy / NetworkPolicy. Application зараз `*.yaml.disabled`.

### `charts/wrappers/*`

Umbrella Helm над офіційними чартами (Redis, RabbitMQ, sealed-secrets, monitoring, cilium-gateway).

## Secrets

SealedSecrets у `environments/prod/secrets/`. Ключ і tooling — окремий репо `riverrise-secrets`.

```bash
cd ../sealed-secrets-keys
./decrypt.sh prod all
$EDITOR .local/prod/plain/api.secret.yaml
./encrypt.sh prod all
```

## Local helm

```bash
helm template api charts/basic-chart \
  -f environments/prod/values/services/api.yaml

helm template network-policies charts/network-policies \
  -f environments/prod/values/network-policies.yaml

cd charts/wrappers/<name> && helm dependency update
```
