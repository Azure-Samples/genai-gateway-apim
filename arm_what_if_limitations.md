# ARM `what-if` / `azd provision --preview` — limitations

`what-if` (what `azd provision --preview` runs under the hood) is
**best-effort, not authoritative**. Microsoft documents this explicitly:
<https://learn.microsoft.com/azure/azure-resource-manager/templates/deploy-what-if#limitations>.

Some resources you declare will not show up in the preview output, and some
"Modify" entries will appear on every run even when nothing actually changes.
A clean preview is not proof that a deploy is a no-op, and an item missing
from the preview is not proof it won't be created.

If you ever need to confirm whether a specific resource is in the deployment,
compile the template and grep the JSON:

```bash
az bicep build --file infra/main.bicep --stdout \
  | jq '..|.type? // empty' \
  | grep -i diagnosticSettings    # or whatever resource type you're checking
```

## Things `what-if` handles poorly or misses entirely

- **Extension resources** — anything declared with `scope:` onto another
  resource. Diagnostic settings, role assignments, locks, policy assignments.
  This is the single most common miss. (Example in this repo: the
  `apim-to-log-analytics` diagnostic setting added in
  [apim_diagnostic.md](apim_diagnostic.md) does not appear in
  `azd provision --preview`, but is in the compiled template and is created
  on `azd up`.)
- **Child resources of services with custom RPs** — APIM sub-resources
  (`apis`, `policies`, `backends`, `loggers`, `diagnostics`,
  `subscriptions`, `products`), Cognitive Services model deployments, some
  Logic Apps internals. Coverage varies by RP.
- **Resources behind `existing` references** when the engine can't resolve
  them at preview time.

## Noise it generates even when nothing changed

These show up as `Modify` on every preview, regardless of whether you
touched the template. They're properties the RP defaults or normalizes
server-side that weren't in your declared template:

- `Flow_Type`, `Request_Source` on Application Insights
- Casing of `customSubDomainName` on Cognitive Services
  (`cog-...-aoai1` vs. `cog-...-AOAI1`)
- `publicNetworkAccess`, `developerPortalStatus`, `legacyPortalStatus`,
  `natGatewayState` on APIM
- `versionUpgradeOption` on AOAI model deployments
- Properties marked read-only by the RP — shown as removals (`-` lines)
- Some `null` vs. unset distinctions

Redeploying does not change any of these. They are cosmetic drift between
"what you wrote" and "what the RP filled in", not real changes.

## Things it genuinely cannot predict

- Anything decided by deployment-time logic outside ARM
  (`Microsoft.Resources/deploymentScripts`, conditional logic that depends
  on runtime outputs from other resources).
- Cross-subscription / cross-tenant resources where the caller lacks read
  access at preview time.
- Failures that only surface during the actual provisioning — quota,
  region capability, Azure Policy denials at apply time, soft-delete name
  collisions (see CLAUDE.md's `azd down --purge` notes), capacity errors.

## Practical rule for this repo

**Trust `what-if` for:**
- Net-new top-level resources (new APIM, new AOAI account, new Log Analytics
  workspace, new App Insights component).
- Shape changes on existing top-level resources — SKU swap, location
  change, capacity (e.g. APIM `skuCount`), AOAI deployment `capacity`.

**Don't trust it for:**
- Diagnostic settings (`Microsoft.Insights/diagnosticSettings`).
- Role assignments (`Microsoft.Authorization/roleAssignments`) — the
  `openAi*RoleApim` modules in `infra/main.bicep` fall here.
- APIM sub-resources — APIs, products, policies, backends, loggers,
  diagnostics, subscriptions. **Policy XML edits never show up** in the
  preview even though they're a frequent thing to change in this repo
  (`infra/app/apim-api-policy.xml`, `infra/app/apim-global-policy.xml`).
- AOAI model deployments past the initial create (TPM bumps, version
  upgrades).

For those, verify after `azd up` with targeted `az` queries:

```bash
# Diagnostic settings on APIM
az monitor diagnostic-settings list \
  --resource $(az apim show -n <apim-name> -g <rg> --query id -o tsv) -o table

# Role assignments APIM holds on the AOAI accounts
az role assignment list \
  --assignee $(az apim show -n <apim-name> -g <rg> --query identity.principalId -o tsv) \
  --all -o table

# APIM policy actually deployed (compare to apim-api-policy.xml on disk)
az apim api policy show \
  --service-name <apim-name> -g <rg> --api-id <api-id> --query value -o tsv
```

Or — for runtime behavior — just `curl` the gateway. The repo's CLAUDE.md
already promotes "verify APIM behavior with curl before hypothesizing"; the
same logic applies here. `what-if` is a sanity check, not a substitute for
hitting the live endpoint after you deploy.
