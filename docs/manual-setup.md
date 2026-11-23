# Manual setup (portal steps)

Everything the Bicep in `infra/` does, as portal steps, so you can build the demo by hand or repair a broken environment on stage. Nothing here was deployed by the authors of this repo; follow **Vertical-slice verification** after your first deployment.

> Learn is the source of truth for Azure behavior. Links are inline; re-check them before the talk, several features here are in preview.

## 0. Prerequisites

| Tool | Version used |
| --- | --- |
| .NET SDK | 11.0.100 (`global.json`) |
| Azure Functions Core Tools | 4.x (tested 4.9.0) |
| Azure Developer CLI | 1.23+ |
| Azure CLI | 2.75+ (Bicep 0.49+ via `az bicep upgrade`) |

.NET 11 is supported on Flex Consumption with the isolated worker: <https://learn.microsoft.com/azure/azure-functions/flex-consumption-plan>, <https://learn.microsoft.com/azure/azure-functions/dotnet-isolated-process-guide#net-11>.
Verify the runtime string in your region: `az functionapp list-flexconsumption-runtimes --location <region> --runtime dotnet-isolated`.

## 1. Deploy with azd (automated path)

```powershell
azd auth login
azd env new santa-demo
azd env set AZURE_LOCATION <region>
azd env set APIM_PUBLISHER_EMAIL you@example.com
# azd env set MCP_AUTH_MODE key            # fallback: subscription key instead of JWT
# azd env set ENABLE_SEMANTIC_CACHE true   # optional semantic cache (adds Managed Redis + embeddings)
azd up
```

`azd up` provisions `infra/main.bicep`, deploys the Function App, then runs `scripts/set-function-keys.ps1` (postdeploy), which copies the Function host key and `mcp_extension` system key into APIM secret named values. Keys never touch the repo.

## 2. Manual equivalents

### 2.1 Function App
Create a **Flex Consumption** Function App (Linux, .NET 11 isolated) with a system-assigned identity and identity-based storage. Deploy: `azd deploy` or `func azure functionapp publish <name>`.
- Endpoints: `https://<func>.azurewebsites.net/api/...` (function key) and the native MCP endpoint `https://<func>.azurewebsites.net/runtime/webhooks/mcp` (`x-functions-key` = `mcp_extension` system key). <https://learn.microsoft.com/azure/azure-functions/functions-bindings-mcp-tool-trigger>

### 2.2 APIM (Standard v2) and telemetry
1. Create an **API Management** instance, tier **Standard v2**, system-assigned managed identity on.
2. **Application Insights logger** (APIs > Application Insights), then **All APIs > Settings > Diagnostic Logs > Application Insights**: set **Frontend Response > Number of payload bytes to log = 0** (and the other three body settings to 0). Logging MCP response bodies buffers the stream and breaks MCP. <https://learn.microsoft.com/azure/api-management/export-rest-mcp-server>
3. **Named values**: `tenantId`, `jwtAudience` (App ID URI of the gateway app registration), `jwtRequiredRole` (`Workshop.Invoke`), and secret `functionKey` / `mcpExtensionKey`.
4. **Backends**: `santa-functions-backend` (`https://<func>.azurewebsites.net/api`), `foundry-backend` (`https://<foundry>.openai.azure.com/openai`), `content-safety-backend` (`https://<cs>.cognitiveservices.azure.com`, authorization credentials = **Managed identity**, resource ID `https://cognitiveservices.azure.com`).
5. **Role assignments** for the APIM managed identity: *Cognitive Services User* on Content Safety; *Cognitive Services User* and *Cognitive Services OpenAI User* on the Foundry resource.
6. **Policy fragments** (APIs > Policy fragments): create `santa-auth`, `santa-model-base` from `infra/apim/policies/fragments/*.xml` (use `auth-jwt.xml`, or `auth-key.xml` in key mode).

### 2.3 REST API to MCP server
1. APIs > **Add API > OpenAPI**: import `openapi/naughty-nice.yaml` (id `santa-naughty-nice`) and `openapi/sleigh-logistics.yaml` (id `santa-sleigh`). Set the backend/service URL to the Function App `/api`.
2. APIs > **MCP Servers > Create MCP server > Expose an API as an MCP server**, pick the API, select operations as tools. Operation IDs become tool names. Select all of `getKidByName`, `listKids`, `submitReview`; and `listSlots`, `scheduleDelivery`, `getDelivery`.
3. MCP server > Policies: paste `infra/apim/policies/mcp-baseline.xml` (replace `__KEY_NV__` with `functionKey`).
4. MCP URL: `https://<apim>.azure-api.net/<mcp-path>/mcp`.

Reference: <https://learn.microsoft.com/azure/api-management/export-rest-mcp-server>

### 2.4 Existing MCP server (Functions native MCP)
APIs > MCP Servers > **Expose an existing MCP server**: base URL `https://<func>.azurewebsites.net/runtime/webhooks`, transport **streamable**, endpoint `/mcp`. Policy: `mcp-baseline.xml` with `__KEY_NV__` = `mcpExtensionKey` (the Functions MCP endpoint needs the `mcp_extension` system key, not the host key).
Reference: <https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server>

### 2.5 Model API (Foundry through APIM)
1. Add a blank HTTP API `santa-model`, URL suffix `santa-model`, service URL `https://<foundry>.openai.azure.com/openai`, subscription required, header `api-key`.
2. Operations: `POST /deployments/{deployment-id}/chat/completions` and `POST /deployments/{deployment-id}/embeddings`.
3. Policy: `model-baseline.xml`.
4. Product `santa-elves` containing the model API and the MCP servers; subscription `elf-agent`.

### 2.6 Optional semantic cache
Create **Azure Managed Redis** (Balanced B0 or larger) with the **RediSearch** module, clustering policy *Enterprise*, eviction *NoEviction*. Register it as an APIM external cache (location `default`). Deploy an embeddings model, add the `embeddings-backend` (`.../openai/deployments/<embedding>/embeddings`), and give APIM *Cognitive Services OpenAI User* on it. Reference: <https://learn.microsoft.com/azure/api-management/azure-openai-enable-semantic-caching>. When disabled, the Bicep emits no cache resources and `toggle-policy.ps1 -Beat semanticcache` will fail, by design.

## 3. Foundry: agent through APIM

### 3.1 APIM model connection (required for governance)
Without this, agent inference bypasses APIM and `llm-token-limit`, content safety, the cache, and token metrics never see agent traffic.
1. Foundry portal > your project > **Management center / Connected resources > New connection > API Management** (AI gateway).
2. Base URL: `https://<apim>.azure-api.net/santa-model` (Azure OpenAI deployment-based style; Foundry appends `/deployments/<name>/chat/completions`). Auth: APIM subscription key of `elf-agent`, or project managed identity if you configured APIM for it. Add model `gpt-4.1-mini` (static list), deployment-in-path on, `api-version` e.g. `2024-10-21`.
3. The agent's model becomes `<connection-name>/<model>`.

Reference: <https://learn.microsoft.com/azure/foundry/agents/how-to/ai-gateway> and <https://learn.microsoft.com/azure/foundry/configuration/enable-ai-api-management-gateway-portal>

### 3.2 MCP tool connection (identity)
**Primary:** a project connection of type *Custom keys / MCP* using **project managed identity** (audience = `jwtAudience`). In Entra, create an app registration whose App ID URI is `jwtAudience`, define the app role `Workshop.Invoke`, and assign that role to the Foundry **project** managed identity (service principal). APIM's `validate-jwt` then enforces audience and role.
**Fallback:** set `MCP_AUTH_MODE=key` and store the `elf-agent` subscription key (header `Ocp-Apim-Subscription-Key`) in the connection. Never configure both; the API's *subscription required* flag follows the mode so only one applies.
Reference: <https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol>

### 3.3 Create the Elf agent in the portal
1. Agents > **New agent** `santa-elf`, model `<connection>/<model>`.
2. Instructions: *"You are an elf in Santa's workshop. Use the tools to check the nice list and schedule deliveries. Never guess; always call a tool. Never mark more than one child at a time."*
3. Add **two** MCP tools: the Naughty-Nice APIM MCP URL and the Sleigh APIM MCP URL (`mcpSleighUrl` output), each with its connection from 3.2. Set **require approval = always** for write tools (`submitReview`, `scheduleDelivery`); never for reads.
4. Beat 1 only (ungoverned): add an **OpenAPI tool** pointing at the Function's OpenAPI (direct Function URL + function key). <https://learn.microsoft.com/azure/foundry/agents/how-to/tools/openapi> The console app's `direct` mode does the same via the Function's native MCP URL instead.

### 3.4 Console agent (code path)
Set env vars, then `dotnet run --project src/SantaWorkshop.Agent -- <mode> ["prompt"]`:

| Variable | Used by |
| --- | --- |
| `FOUNDRY_PROJECT_ENDPOINT` | all agent modes |
| `AGENT_MODEL` | `mcp`, `injection` (`<apim-connection>/<model>`) |
| `DIRECT_MODEL`, `DIRECT_MCP_URL`, `DIRECT_MCP_KEY` | `direct` |
| `APIM_MCP_URL`, `APIM_MCP_CONNECTION` | `mcp`, `injection` (Naughty-Nice MCP server) |
| `APIM_SLEIGH_MCP_URL`, `APIM_SLEIGH_MCP_CONNECTION` (defaults to `APIM_MCP_CONNECTION`) | `mcp`, `injection`: optional second MCP server, needed for the lookup-and-schedule prompt. Leave unset for the existing-MCP beat |
| `APIM_SUBSCRIPTION_KEY` *or* `APIM_AUDIENCE` | `flood` (bounded burst; key or bearer token) |
| `FLOOD_COUNT` | `flood` (default 30) |

## 4. Vertical-slice verification (run after the first deployment)

1. `curl "https://<func>.azurewebsites.net/api/kids/Timmy%20Thompson?code=<key>"` returns Timmy (Nice, 92).
2. `curl` the APIM MCP URL with `initialize` + `tools/list` (bearer token or subscription key): three tools listed.
3. `dotnet run --project src/SantaWorkshop.Agent -- mcp "Is Timmy Thompson on the nice list?"` returns a tool-grounded answer.
4. **Agent inference goes through APIM:** run the agent once, then in Application Insights (`docs/kql/mcp-and-model-calls.kql`) confirm a `santa-model` request exists for that turn. If not, the connection or model selection in 3.1 is wrong; fix this before demoing any LLM policy.
5. Apply each beat with `scripts/toggle-policy.ps1` and confirm the expected status (see `docs/demo-script.md`).
6. Pin versions that worked: Functions worker/extension packages are pinned in `src/SantaWorkshop.Functions/*.csproj`; Bicep API versions in `infra/modules/*.bicep` (MCP APIs use `2025-09-01-preview`).

## 5. Known unverified items

Not deployed by the authors: Bicep deployment end-to-end, `type: 'mcp'` APIs and `apis/tools` in Bicep, backend `credentials.managedIdentity`, Responses-vs-chat-completions routing of the Foundry APIM connection, and a live `func start` run (local Core Tools launched the worker with the machine's .NET runtime, which lacked .NET 11).
