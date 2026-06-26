# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A fork of `Azure-Samples/genai-gateway-apim` repurposed as a **recon test
target** — a deployed Azure API Management (APIM) + Azure OpenAI (AOAI) gateway
that the `recon` AI compliance test runner (in the sibling repo
`../agenticaifrmwk_recon/`) probes. It deploys **CS-integration pattern (a)**:
AOAI built-in RAI filter (`raiPolicyName: 'Microsoft.Default'`), **no** APIM
`llm-content-safety` policy, **no** Content Safety resource, **no** middleware
function. There is no content-safety layer beyond the model's default filter —
that absence is intentional and is the point of this target.

Two parts live here:
- **Infrastructure** (`infra/`): Bicep deployed via `azd`. The actual product.
- **Sample chat app** (`src/`): a small Node.js/Express + static-HTML demo that
  exercises the gateway. Useful as a manual smoke test, not the focus.

> **Shared-APIM model.** APIM (StandardV2) is the dominant fixed cost, so a
> single APIM instance is shared across the recon patterns (a/b/d) instead of
> one per repo. This repo no longer creates an APIM — it deploys a **shared
> platform stack** (`platform/`, deployed once) that owns the APIM + monitoring,
> then `infra/` attaches **this pattern's** API/backends/policy to it by name.
> See "Two-stack deployment" below.

> The top "Fork notes" section of `README.md` is authoritative. The lower half
> (regions like `koreacentral`, `gpt-35-turbo`, `api-version 2024-02-01`) is
> upstream and **stale** — do not trust it for this fork.

## Current deployment shape (pattern a)

- Model: `gpt-4.1-mini` version `2025-04-14`, deployment name `conversation-model`
- **APIM is shared, not deployed here.** It lives in the platform stack
  (`platform/`), default SKU **Basic v2** (`PLATFORM_APIM_SKU`, override to
  `StandardV2` if Basic v2 rejects the load-balancer pool). This pattern's AOAI
  region is `westeurope`.
- **Location vars** in `infra/main.parameters.json`: `AZURE_LOCATION` (this
  pattern's RG only) and `AZURE_OPENAI_LOCATION` (AOAI — defaults to
  `westeurope`). The APIM region now lives in the platform stack
  (`PLATFORM_APIM_LOCATION`), not here.
- `patternSuffix` (`PATTERN_SUFFIX`, default `a`) disambiguates this pattern's
  resources on the shared APIM (API name, backends, product, subscription) and
  tags spend with `cs-integration-pattern`. **Must be unique per pattern**
  (a/b/d).
- AOAI API version: `2024-10-21`
- TPM cap: 20,000 (formatted into the `azure-openai-token-limit` policy at
  `infra/app/apim-api.bicep`, in `headerPolicyXml`)
- Backend count is parameterized: `deployTwoBackends` in `infra/main.bicep`
  (default `false` in `main.parameters.json` → one AOAI account; `true` → two
  load-balanced). The `LoadBalancer` pool resource exists either way; the policy
  always routes to it.

## Commands

### Two-stack deployment

The shared APIM lives in `platform/` and is deployed **once**, ahead of any
pattern. Each pattern repo then attaches via `azd up` after the platform
outputs are set into its env.

```bash
# 1. ONCE, ever — deploy the shared APIM + monitoring (plain `az`, not azd):
./platform/deploy.sh         # prints the `azd env set` commands below

# 2. Per pattern — paste what deploy.sh printed, then `azd up`:
azd env set SHARED_APIM_NAME <name>
azd env set SHARED_APIM_RESOURCE_GROUP <rg>
azd env set SHARED_APIM_PRINCIPAL_ID <principal>
azd env set SHARED_APPLICATION_INSIGHTS_NAME <appi>
azd env set PATTERN_SUFFIX a   # a/b/d — unique per pattern
azd up
```

`azd provision --preview` / `azd up` **fail fast with "required inputs are
missing"** until those four `SHARED_*` vars are set — that's expected, it means
the platform hasn't been deployed/wired yet, not a bug.

<!-- 25e1acfc - 25062026 -->
> **Deploy in progress (KLEAR, pattern a).** The shared platform stack is
> **already deployed** into KLEAR sub `01b46d81-…` / RG `rg-shared-platform`
> (Basic v2 APIM `apim-ckelj5onvh22y-SHARED`). The azd env `pl-apimaoai-dev-03`
> is fully wired (all `SHARED_*` + `AZURE_RESOURCE_GROUP=rg-pl-apimaoai-dev-01` +
> `PATTERN_SUFFIX=a`). **Only the workload remains:** run
> `azd auth login --tenant-id 4efadd80-569e-4303-9fe0-eaa91841d112`
> (interactive — azd auth is separate from `az`), then `azd up`. `azd up` is the
> first real test of Basic v2 + the load-balancer pool; if it rejects the pool,
> redeploy the platform with `PLATFORM_APIM_SKU=StandardV2`. Remove this note
> once the workload is up.

Deploy / tear down (run from repo root):
```bash
azd up                 # ~3-4 min once the shared platform exists (no APIM to create here)
azd provision --preview  # dry run (needs SHARED_* vars set first)
azd down --purge --force # teardown of THIS pattern's own RG (AOAI). See orphan note below.
```

**Teardown gotcha (shared-APIM model):** `azd down` deletes this pattern's own
resource group (its AOAI accounts), but the API, backends, `LoadBalancer-<sfx>`,
product, user and subscription this pattern created live as children of the
**shared** APIM in `SHARED_APIM_RESOURCE_GROUP` — a different RG that this azd
env does not own. Those are **not** removed by `azd down` and must be cleaned
manually if you want them gone, e.g.:
```bash
az apim api delete         -g <shared-rg> -n <apim> --api-id myAPI-a --yes
az apim product delete      -g <shared-rg> --service-name <apim> --product-id APIM-AI_APIS-a --delete-subscriptions --yes
# backends: az rest DELETE on .../service/<apim>/backends/backend1-a, backend2-a, LoadBalancer-a
```
Tear down the shared APIM itself separately by deleting its resource group —
only after all patterns are down.

If a prior teardown skipped `--purge`, the next `azd up` fails with
`InvalidTemplateDeployment` / `FlagMustBeSetForRestore` because the AOAI
account names are still held by soft-deleted entries (default retention
7–90 days). Recover by purging them manually, then redeploy:
```bash
# 1. find the soft-deleted AOAI accounts (look for cog-*-APIM*-AOAI* in the target region/RG)
az cognitiveservices account list-deleted \
  --query "[?location=='westeurope'].{name:name, location:location, rg:resourceGroup}" -o table

# 2. purge each one (name + location + the RG it was in)
az cognitiveservices account purge \
  --name <account-name> --location westeurope --resource-group <rg>
# success = exit 0 with empty output

# 3. confirm it's gone, then re-run azd up
az cognitiveservices account list-deleted \
  --query "[?contains(name, '<account-name-fragment>')].name" -o tsv
```
Same shape applies to soft-deleted Key Vaults (`az keyvault purge --name … --location …`).

APIM has its own soft-delete pool (default 48 h retention). If the next
`azd up` fails because the APIM service name is still held:
```bash
# 1. find soft-deleted APIM services in the target region
az apim deletedservice list \
  --query "[?location=='West Europe'].{name:name, location:location, scheduledPurgeDate:scheduledPurgeDate}" -o table

# 2. purge by name + location (no --resource-group flag on this command)
az apim deletedservice purge \
  --service-name <apim-name> --location westeurope

# 3. confirm it's gone, then re-run azd up
az apim deletedservice list \
  --query "[?contains(name, '<apim-name-fragment>')].name" -o tsv
```

Sample app (from `src/`):
```bash
npm install
npm start        # concurrently runs web (http-server :3000) + api (express :1337)
npm run start:api
npm run start:web
```

Extract values recon needs (after `azd up`):
```bash
APIM_ENDPOINT=$(azd env get-value APIM_ENDPOINT)
API_SUFFIX=$(azd env get-value API_SUFFIX)        # = "myAPI-<patternSuffix>/openai", e.g. "myAPI-a/openai"
DEPLOYMENT_ID=$(azd env get-value DEPLOYMENT_ID)  # = "conversation-model"
API_VERSION=$(azd env get-value API_VERSION)
SUBSCRIPTION_KEY=$(azd env get-value SUBSCRIPTION_KEY)
```

Live smoke test (the canonical request shape — note `api-key` header):
```bash
curl -sS -X POST \
  "$APIM_ENDPOINT/$API_SUFFIX/deployments/$DEPLOYMENT_ID/chat/completions?api-version=$API_VERSION" \
  -H "api-key: $SUBSCRIPTION_KEY" -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"ping"}],"max_tokens":10}'
```

There is no build/lint/test in this repo. Verify infra changes empirically
against the live endpoint (curl) before reasoning about Bicep. Cost and
traffic-stat recipes (Azure Monitor metrics + KQL against `AppRequests` /
`AppMetrics`, consumption API) live in `costs_analysis.md`; the README has
the original recon-run + Log Analytics cross-check walkthroughs.

## Architecture & request flow

Client → shared APIM (one instance, many patterns) → this pattern's load
balancer pool → one or two AOAI backends.

- **Two stacks:** `platform/` (deployed once via `az deployment sub create`)
  owns the APIM, monitoring, and the service-level api-version policy. `infra/`
  (deployed per pattern via `azd`) attaches this pattern's API/backends/policy
  to that APIM by name, across resource groups (the `api` module is
  `scope: platformResourceGroup`). AOAI lives in the pattern's own RG; the API
  children live in the shared RG.
- **Auth in:** clients send the APIM subscription key in the **`api-key`**
  header (not `Ocp-Apim-Subscription-Key`). This is set by
  `subscriptionKeyParameterNames.header: 'api-key'` in
  `infra/app/apim-api.bicep`.
- **Auth out (APIM→AOAI):** the **shared** APIM's system-assigned managed
  identity gets a Bearer token via the `authentication-managed-identity` policy
  and sets the `Authorization` header. AOAI has `disableLocalAuth: true` (no key
  auth). Each pattern's `infra/main.bicep` grants that shared MID
  (`SHARED_APIM_PRINCIPAL_ID`) the **Cognitive Services OpenAI User** role
  (`5e0bd9bd-7b93-4f28-af87-19fc36ad61bd`) over its own RG — one RG-scoped grant
  covers both AOAI accounts.
- **Load balancing:** `backend1-<sfx>` + `backend2-<sfx>` (each with a 500-599
  circuit breaker) are pooled into a `LoadBalancer-<sfx>` backend; the inbound
  policy routes to that pool. Names are pattern-suffixed so patterns don't
  collide on the shared APIM.
- **Inbound policy** (`infra/app/apim-api-policy.xml`): defaults the
  `api-version` query param, sets backend to the pool, injects the MI token,
  applies `azure-openai-token-limit` (per-subscription, tokens-per-minute
  formatted in via `apim-api.bicep`), and emits token metrics.

### Key files
- `platform/main.bicep` — the **shared platform stack** (subscription scope):
  shared RG + monitoring + APIM (Basic v2 default) + the service-level
  api-version policy. Deployed once via `platform/deploy.sh`
  (`az deployment sub create`). Outputs the `SHARED_*` values each pattern wires
  into its azd env.
- `platform/apim-service-policy.bicep` — applies the service-level global policy
  to the shared APIM, sourcing `infra/app/apim-global-policy.xml` (single source
  of truth — the XML still lives under `infra/app/`).
- `platform/deploy.sh` — deploy wrapper; prints the `azd env set` commands.
- `infra/main.bicep` — per-pattern orchestration; AOAI deployments + role grant
  in this pattern's RG, and the `api` module deployed into the **shared** RG
  (`scope: platformResourceGroup`). Takes the `SHARED_*` params + `patternSuffix`.
  Outputs (`APIM_ENDPOINT`, `API_SUFFIX`, `DEPLOYMENT_ID`, `API_VERSION`,
  `SUBSCRIPTION_KEY`) at the bottom feed recon. No longer creates APIM/monitoring.
- `infra/main.parameters.json` — env defaults via `${AZURE_*=default}` plus the
  `${SHARED_*}` platform-output wiring and `${PATTERN_SUFFIX=a}`.
- `infra/app/apim-api.bicep` — the API, backends, load balancer, policy wiring,
  product, subscription, **all pattern-suffixed** via `patternSuffix`. Imports
  the OpenAPI spec from a **remote** GitHub URL (`format: 'openapi+json-link'`),
  then re-declares a fixed set of data-plane operations (`deploymentOps` /
  `deploymentOpOverrides`) to drop the required `?api-version=…` query param from
  the imported URL templates — this is what makes the api-version default work.
  Without those overrides, callers omitting `api-version` get a 404 before any
  policy runs. **Does not** apply the service-level global policy anymore (moved
  to the platform stack, so patterns don't clobber each other).
- `infra/app/apim-api-policy.xml` — inbound/backend/outbound policy applied
  per-API (token-limit, MI auth, token-metric emit).
- `infra/app/apim-global-policy.xml` — service-level all-APIs policy (api-version
  default); now **applied by `platform/apim-service-policy.bicep`**, not per-API.
- `infra/core/**` — reusable modules (`ai/cognitiveservices`, `gateway/apim`,
  `monitor/*`, `security/role`); shared by both stacks (platform references them
  via `../infra/core/...`).
- `src/api/apiService.js` — how a client calls the gateway (chat completions,
  `api-key` header). `src/api/api.js` is the Express server.

### Gotchas
- **Deploy order:** the platform stack must exist and its `SHARED_*` outputs
  must be set in the pattern's azd env before `azd up`/`azd provision`. Without
  them, azd fails fast with "4 required inputs are missing" — expected, not a bug.
- **`PATTERN_SUFFIX` must be unique per pattern** (a/b/d). Two patterns sharing a
  suffix collide on the shared APIM (same API name, backend names, subscription).
- **Basic v2 + load-balancer pool** is the cheaper default but its support for
  backend pools is not doc-confirmed. If `platform/deploy.sh` fails on the pool,
  set `PLATFORM_APIM_SKU=StandardV2` and redeploy; consolidation still saves vs
  one APIM per pattern. `deployTwoBackends=false` (default) is the gentlest test.
- **Cross-RG teardown:** see the teardown gotcha under Commands — `azd down`
  leaves this pattern's API children on the shared APIM as orphans.
- `DEPLOYMENT_ID` is the **deployment name** `conversation-model`, not the model
  name `gpt-4.1-mini`.
- `infra/app/openai.bicep` is empty/unused — AOAI is deployed through
  `infra/core/ai/cognitiveservices.bicep`, not this file.
- `test/*.bicep` (numbered `1-`…`5-`) is a step-by-step tutorial variant for
  deploying the pieces incrementally; it is **not** the deployment path `azd`
  uses (`infra/main.bicep` is).
- `src/.env` is generated by the `azd` `postprovision` hook
  (`azd env get-values > src/.env`); do not hand-edit it as the source of truth.
