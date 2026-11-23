# Azure AI Gateway vs. API Management AI gateway capabilities

Beat 5: manual steps only (nothing in this repo deploys Azure AI Gateway).

Foundry can consume models through **Azure AI Gateway** or **Azure API Management**. They are distinct resource types with separate management experiences, so "AI gateway" in APIM (the `llm-*` policies, MCP servers) is not the same product as the Azure AI Gateway resource. Source: <https://learn.microsoft.com/azure/foundry/configuration/enable-ai-api-management-gateway-portal> (the Foundry UI integration is rolling out gradually; the Azure AI Gateway portal and `az aigateway` (Azure CLI 2.75+) are the fallback).

## Side by side

| Topic | APIM (this demo) | Azure AI Gateway |
| --- | --- | --- |
| What you manage | APIM instance, policies as XML/Bicep | Azure AI Gateway portal / `az aigateway` |
| Model access | Model API + `llm-*` policies | Gateway **model aliases** (apps don't couple to backend model names) |
| MCP | REST-to-MCP and existing-MCP servers, with policies | Publish MCP tools via the gateway/catalog |
| Foundry link | Foundry **API Management connection** (`<connection>/<model>`) | Foundry gateway connection with aliases |
| Control depth | Arbitrary policy logic | Managed controls |

Re-verify this table against Learn before presenting; the feature set is moving.

## Manual steps (portal)

1. Open the Azure AI Gateway portal and create a gateway (or `az aigateway` per Learn).
2. Add the Foundry chat deployment as a backend and expose it as a **model alias** (e.g. `santa-chat`).
3. Publish an MCP tool/server (the Naughty-or-Nice MCP URL) to the gateway's catalog.
4. In Foundry, project > connections > add the gateway as a connection, selecting the alias; select the alias as the agent model.
5. Hit the alias from the console agent (`AGENT_MODEL=<gateway-connection>/santa-chat`) and show gateway traces in Foundry.

## Talking points
- Use APIM when you need bespoke policy logic, existing APIM estate, and per-API/per-product governance (the demo).
- Consider Azure AI Gateway for a centrally governed hub for models/tools shared across teams, with stable aliases.
- Both can sit in a hub-and-spoke pattern with Foundry projects as spokes.
