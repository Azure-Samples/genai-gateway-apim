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

> The top "Fork notes" section of `README.md` is authoritative. The lower half
> (regions like `koreacentral`, `gpt-35-turbo`, `api-version 2024-02-01`) is
> upstream and **stale** — do not trust it for this fork.

## Current deployment shape (pattern a)

- Model: `gpt-4.1-mini` version `2025-04-14`, deployment name `conversation-model`
- AOAI + APIM region: `westeurope`; APIM SKU: `StandardV2`
- AOAI API version: `2024-10-21`
- TPM cap: 20,000 (formatted into the `azure-openai-token-limit` policy at
  `infra/app/apim-api.bicep:152`)
- Backend count is parameterized: `deployTwoBackends` in `infra/main.bicep`
  (default `true` → two load-balanced AOAI accounts; `false` → one). Set via
  `infra/main.parameters.json`. The `LoadBalancer` pool resource exists either
  way; the policy always routes to it.

## Commands

Deploy / tear down (run from repo root):
```bash
azd up                 # ~4-5 min on a warm region; first-ever StandardV2 in a cold region can run 25-40 min
azd provision --preview  # dry run
azd down --purge --force # teardown; --purge hard-deletes AOAI/KV soft-delete entries
```

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
API_SUFFIX=$(azd env get-value API_SUFFIX)        # = "myAPI/openai"
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

Client → APIM → (load balancer pool) → one of two AOAI backends.

- **Auth in:** clients send the APIM subscription key in the **`api-key`**
  header (not `Ocp-Apim-Subscription-Key`). This is set by
  `subscriptionKeyParameterNames.header: 'api-key'` in
  `infra/app/apim-api.bicep`.
- **Auth out (APIM→AOAI):** APIM's system-assigned managed identity gets a
  Bearer token via the `authentication-managed-identity` policy and sets the
  `Authorization` header. AOAI has `disableLocalAuth: true` (no key auth), and
  APIM is granted the **Cognitive Services OpenAI User** role
  (`5e0bd9bd-7b93-4f28-af87-19fc36ad61bd`) on both AOAI accounts.
- **Load balancing:** `backend1` + `backend2` (each with a 500-599 circuit
  breaker) are pooled into a `LoadBalancer` backend; the inbound policy routes
  to that pool.
- **Inbound policy** (`infra/app/apim-api-policy.xml`): defaults the
  `api-version` query param, sets backend to the pool, injects the MI token,
  applies `azure-openai-token-limit` (per-subscription, tokens-per-minute
  formatted in via `apim-api.bicep`), and emits token metrics.

### Key files
- `infra/main.bicep` — top-level orchestration; AOAI deployments, APIM, roles,
  monitoring. Outputs (`APIM_ENDPOINT`, `API_SUFFIX`, `DEPLOYMENT_ID`,
  `API_VERSION`, `SUBSCRIPTION_KEY`) at the bottom feed recon.
- `infra/main.parameters.json` — env defaults (regions, model API version) via
  `${AZURE_*=default}` substitution.
- `infra/app/apim-api.bicep` — the API, backends, load balancer, policy wiring,
  product, subscription. The API definition imports the OpenAPI spec from a
  **remote** GitHub URL (`format: 'openapi+json-link'`, line 130-131), then
  re-declares a fixed set of data-plane operations (`deploymentOpOverrides`,
  line 186+) to drop the required `?api-version=…` query param from the
  imported URL templates — this is what makes the api-version default in
  `apim-global-policy.xml` work. Without those overrides, callers omitting
  `api-version` get a 404 before any policy runs.
- `infra/app/apim-api-policy.xml` — inbound/backend/outbound policy applied
  per-API (token-limit, MI auth, token-metric emit).
- `infra/app/apim-global-policy.xml` — service-level all-APIs policy; injects
  a default `api-version` query param when callers omit it.
- `infra/core/**` — reusable modules (`ai/cognitiveservices`, `gateway/apim`,
  `monitor/*`, `security/role`).
- `src/api/apiService.js` — how a client calls the gateway (chat completions,
  `api-key` header). `src/api/api.js` is the Express server.

### Gotchas
- `DEPLOYMENT_ID` is the **deployment name** `conversation-model`, not the model
  name `gpt-4.1-mini`.
- `infra/app/openai.bicep` is empty/unused — AOAI is deployed through
  `infra/core/ai/cognitiveservices.bicep`, not this file.
- `test/*.bicep` (numbered `1-`…`5-`) is a step-by-step tutorial variant for
  deploying the pieces incrementally; it is **not** the deployment path `azd`
  uses (`infra/main.bicep` is).
- `src/.env` is generated by the `azd` `postprovision` hook
  (`azd env get-values > src/.env`); do not hand-edit it as the source of truth.
