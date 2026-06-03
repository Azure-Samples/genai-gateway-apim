# Cost & usage analysis for the APIM + AOAI gateway

Recipes for extracting traffic/token stats and estimating cost after a recon
scan (or any traffic) against this gateway. Two data sources:

- **Azure Monitor metrics on the AOAI account** — authoritative token counts,
  no telemetry pipeline. ~1 min latency.
- **App Insights workspace-based tables** in the Log Analytics workspace
  (`AppRequests`, `AppMetrics`) — per-request data + APIM-emitted token
  metrics dimensioned by Client IP and Subscription ID. ~2-5 min latency.
- **Azure Cost Management / consumption** — actual billed amounts. 8-24h lag.

Data does **not** land in `AzureDiagnostics` — APIM is wired to App Insights
via the `app-insights-logger` resource, not a direct diagnostic setting.

## Shell variables

Derive everything from the azd env so the recipes survive redeploys with new
resource names.

```bash
RG=$(azd env get-value AZURE_RESOURCE_GROUP)
SUB=$(az account show --query id -o tsv)
AOAI=$(az resource list --resource-group $RG \
  --resource-type Microsoft.CognitiveServices/accounts --query "[0].name" -o tsv)
# Sanity: with deployTwoBackends=true (infra/main.bicep default) there are 2 AOAI
# accounts and `[0]` silently picks one — per-account queries below would miss
# half the traffic. Sum across all accounts or query each individually.
AOAI_COUNT=$(az resource list --resource-group $RG \
  --resource-type Microsoft.CognitiveServices/accounts --query "length(@)" -o tsv)
[ "$AOAI_COUNT" -gt 1 ] && echo "WARNING: $AOAI_COUNT AOAI accounts in $RG — \$AOAI only references one" >&2
APIM=$(az resource list --resource-group $RG \
  --resource-type Microsoft.ApiManagement/service --query "[0].name" -o tsv)
WS=$(az resource list --resource-group $RG \
  --resource-type Microsoft.OperationalInsights/workspaces --query "[0].name" -o tsv)
WS_ID=$(az monitor log-analytics workspace show \
  --resource-group $RG --workspace-name $WS --query customerId -o tsv)
AOAI_RID="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$AOAI"
APIM_RID="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM"
```

## Token + request totals (Azure Monitor metrics, no KQL)

Quickest path. `ProcessedPromptTokens` and `GeneratedTokens` are the canonical
numbers to use for cost calc.

```bash
az monitor metrics list --resource "$AOAI_RID" \
  --metric "ProcessedPromptTokens,GeneratedTokens,AzureOpenAIRequests,TokenTransaction" \
  --interval PT6H --offset 32h --aggregation Total \
  --query "value[].{metric:name.value, total:timeseries[0].data[0].total}" -o table
```

Adjust window with `--offset 1h` / `--offset 24h`, or use
`--start-time 2026-05-30T14:00:00Z --end-time 2026-05-30T15:30:00Z`
to bracket a specific scan run.

APIM-side view (request count + duration):

qq: why is this APIM-side? Is this related to discussed diagnostic setting?

```bash
az monitor metrics list --resource "$APIM_RID" \
  --metric "Requests,Duration" \
  --interval PT6H --offset 32h \
  --query "value[].{metric:name.value, unit:unit, total:timeseries[0].data[0].total, avg:timeseries[0].data[0].average}" -o table
```

If `APIM.Requests` and `AOAI.AzureOpenAIRequests` disagree, requests were
short-circuited at APIM (e.g., 401 on bad subscription key, 429 from the
`azure-openai-token-limit` policy) — they never reached AOAI.

## Per-client-IP token breakdown (KQL)

APIM's `azure-openai-emit-token-metric` policy lands in `AppMetrics` with
dimensions `Properties['Client IP']` and `Properties['Subscription ID']`.

```bash
az monitor log-analytics query --workspace "$WS_ID" --analytics-query "
AppMetrics
| where TimeGenerated > ago(24h)
| where Name in ('Prompt Tokens', 'Completion Tokens', 'Total Tokens')
| extend ClientIP = tostring(Properties['Client IP'])
| summarize total=sum(Sum) by ClientIP, Name
| evaluate pivot(Name, sum(total))
| order by ['Completion Tokens'] desc
" -o table
```

Available `AppMetrics.Name` values from this policy: `Prompt Tokens`,
`Completion Tokens`, `Total Tokens`, plus sub-counters like
`Prompt Cached Tokens`, `Completion Reasoning Tokens`,
`Completion Audio Tokens`, etc.

## Status code + latency breakdown (KQL)

```bash
az monitor log-analytics query --workspace "$WS_ID" --analytics-query "
AppRequests
| where TimeGenerated > ago(32h)
| summarize requests=count(), avg_ms=round(avg(DurationMs),0), p95_ms=round(percentile(DurationMs,95),0) by ResultCode
| order by requests desc
" -o table
```

For per-operation breakdown (chat/completions, embeddings, etc.):

```bash
az monitor log-analytics query --workspace "$WS_ID" --analytics-query "
AppRequests
| where TimeGenerated > ago(32h)
| summarize requests=count(), errors=countif(Success == false) by Name
| order by requests desc
" -o table
```

<!-- 03e3bed6 - 03062026 -->

## Investigating a specific run window

The recipes above answer "what's the total" and "who hit us." This section
answers "why did *that one run* take so long / cost so much / hit a limit."
Three queries you can't easily get from the totals view: when the burst
actually started/ended, whether the TPM cap engaged at peak, and whether the
client was serial or parallel.

### Window finder (hourly histogram)

Bracket the actual run boundaries before doing anything else — wider windows
pollute averages with idle time, narrower ones miss the tail. Scan a couple of
days around when you think the run happened:

```bash
az monitor log-analytics query --workspace "$WS_ID" --analytics-query "
AppRequests
| where TimeGenerated between (datetime(2026-06-01T00:00:00Z) .. datetime(2026-06-03T12:00:00Z))
| summarize requests=count() by bin(TimeGenerated, 1h)
| order by TimeGenerated asc
" -o table
```

Read as a histogram: contiguous non-zero hours = the run window. Use those
exact bounds as `<start>` / `<end>` below.

### Peak per-minute token throughput (did the TPM cap engage?)

`azure-openai-token-limit` evaluates a **rolling 1-minute** counter. A
window-average TPM is misleading — what matters is the worst minute. Check
peak + percentiles against the cap (20,000 TPM, formatted into
`infra/app/apim-api.bicep:152`):

```bash
az monitor log-analytics query --workspace "$WS_ID" --analytics-query "
AppMetrics
| where TimeGenerated between (datetime(<start>) .. datetime(<end>))
| where Name == 'Total Tokens'
| summarize tpm=sum(Sum) by bin(TimeGenerated, 1m)
| summarize p50=round(percentile(tpm,50),0),
            p95=round(percentile(tpm,95),0),
            p99=round(percentile(tpm,99),0),
            max=max(tpm),
            minutes_observed=count()
" -o table
```

- `max << cap` → policy never engaged; status breakdown should show 0 × 429
- `max ≈ cap` → throttling likely; cross-check status codes
- Cap is enforced per-subscription-key; if multiple keys share the gateway,
  also group by `Subscription ID` from `Properties`

### Concurrency (req/min distribution)

Tells you whether wall-clock duration is driven by serial client pacing or by
genuine backend slowness:

```bash
az monitor log-analytics query --workspace "$WS_ID" --analytics-query "
AppRequests
| where TimeGenerated between (datetime(<start>) .. datetime(<end>))
| summarize requests=count() by bin(TimeGenerated, 1m)
| summarize avg_rpm=round(avg(requests),1),
            p50_rpm=round(percentile(requests,50),1),
            p95_rpm=round(percentile(requests,95),1),
            max_rpm=max(requests)
" -o table
```

Cross-check with avg latency from the per-operation breakdown above:
- `requests × avg_latency ≈ wall_clock` → client is essentially serial;
  parallelism is the lever, not the gateway
- `requests × avg_latency << wall_clock` → client gappy/throttled by itself
- `requests × avg_latency >> wall_clock` → high concurrency; gateway / model
  is the lever

### Diagnostic frame

Answer "why did run X take so long" by walking these six in order:

1. **Window** — from the hourly histogram, exact start/end and total wall-h.
2. **Volume + health** — request count, status-code split (200 / 4xx / 429 / 5xx).
3. **Per-call latency** — avg / p95 / max from the per-operation query.
4. **Throughput vs cap** — peak TPM vs the 20k cap (engaged or headroom?).
5. **Concurrency** — avg / p95 / max req/min (serial or parallel?).
6. **Math check** — `requests × avg_latency` should ≈ wall clock under low
   concurrency; if it does, workload shape (not infra) is the cause.

## Cost estimate (token-based)

gpt-4.1-mini Standard, published rates as of late 2025 — **verify on the
Azure pricing page before invoicing, Azure occasionally lags OpenAI on rate
changes**:

| Tier               | $/1M tokens |
|--------------------|-------------|
| Input              | $0.40       |
| Cached input       | $0.10       |
| Output             | $1.60       |

Formula (using AOAI metrics as the authoritative source):

```
cost ≈ ProcessedPromptTokens / 1_000_000 × 0.40
     + GeneratedTokens       / 1_000_000 × 1.60
```

Costs **not** included in the formula (run the consumption query below to see
them):
- APIM StandardV2 base (~$0.27/hr ≈ $200/month) — fixed, unrelated to traffic.
- Log Analytics ingestion (~$2.30/GB) — negligible at low scan volume, can
  matter at high.
- App Insights data overage, APIM bandwidth — usually small.

## Actual billed cost (Cost Management API)

Run **at least one day after** the activity — Cost Management has 8-24h lag.

Preferred path: query Cost Management directly via `az rest`. The
`az consumption usage list` CLI is not reliable here — on this MPN
subscription every record comes back with `instanceId`, `pretaxCost`, and
`meterDetails` all `null`, so any `[?contains(instanceId, …)]` filter returns
nothing and aggregates always sum to 0. The Cost Management `query` API uses a
different projection that returns real per-resource cost.

```bash
SCOPE="subscriptions/$SUB/resourceGroups/$RG"
# date -v: BSD/macOS. On Linux use: FROM=$(date -d "1 day ago" -u +%Y-%m-%dT00:00:00Z)
FROM="$(date -v-1d +%Y-%m-%dT00:00:00Z)"
TO="$(date +%Y-%m-%dT00:00:00Z)"

BODY=$(cat <<EOF
{
  "type": "ActualCost",
  "timeframe": "Custom",
  "timePeriod": { "from": "$FROM", "to": "$TO" },
  "dataset": {
    "granularity": "None",
    "aggregation": { "totalCost": { "name": "PreTaxCost", "function": "Sum" } },
    "grouping": [ { "type": "Dimension", "name": "ResourceId" } ]
  }
}
EOF
)

# Per-resource breakdown
az rest --method POST \
  --uri "https://management.azure.com/$SCOPE/providers/Microsoft.CostManagement/query?api-version=2023-11-01" \
  --body "$BODY" \
  --query "properties.{cols:columns[].name, rows:rows}" -o json
```

Aggregate to a single total (drop the `grouping` block):

```bash
BODY_TOTAL=$(cat <<EOF
{
  "type": "ActualCost",
  "timeframe": "Custom",
  "timePeriod": { "from": "$FROM", "to": "$TO" },
  "dataset": {
    "granularity": "None",
    "aggregation": { "totalCost": { "name": "PreTaxCost", "function": "Sum" } }
  }
}
EOF
)
az rest --method POST \
  --uri "https://management.azure.com/$SCOPE/providers/Microsoft.CostManagement/query?api-version=2023-11-01" \
  --body "$BODY_TOTAL" \
  --query "properties.rows[0][0]" -o tsv
```

The endpoint is rate-limited — back off on `429 Too Many Requests`, the
throttle window can stretch several minutes under sustained polling.

Caller needs **Cost Management Reader** (or higher: Reader/Contributor) on the
scope. The owner of this subscription does not get cost RBAC implicitly —
without it the call returns `RBACAccessDenied`. Grant with:
```bash
az role assignment create --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --role "Cost Management Reader" --scope "/subscriptions/$SUB/resourceGroups/$RG"
```

Fallback (`az consumption usage list`) — only useful on subscriptions where it
returns populated records. Use a null-safe filter or `contains()` will error
the moment any record has `instanceId: null`:

```bash
az consumption usage list \
  --start-date "$FROM" --end-date "$TO" \
  --query "[?instanceId != null && contains(instanceId, '$RG')].pretaxCost" -o tsv \
  | awk '{ s += $1 } END { printf \"%.4f\\n\", s }'
```

## Standing setup (only if running scans regularly)

- **Budget alert**: Portal → Cost Management → Budgets → scope to the RG,
  e.g., $5/day with email on 80% breach. Costs ~nothing, no code needed.
- **Tag the RG** for filtering when multiple test envs coexist:
  ```bash
  az group update --name $RG --set tags.purpose=recon-target
  ```
  Then in Cost Analysis, group by tag `purpose`.

## When not to bother

For a single ad-hoc scan under a few dollars: the metric-based formula above
is accurate to within cents. The consumption query adds noise (per-meter line
items, 8-24h lag) without changing decisions. Skip it.
