using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Extensions.Mcp;
using SantaWorkshop.Functions.Data;

namespace SantaWorkshop.Functions.Mcp;

/// <summary>
/// Native MCP server hosted by the Function App (the "existing MCP server" demo beat that APIM fronts).
/// Read-only tools only. Endpoint: /runtime/webhooks/mcp (requires the mcp_extension system key).
/// https://learn.microsoft.com/azure/azure-functions/functions-bindings-mcp-tool-trigger
/// </summary>
public sealed class WorkshopMcpTools(WorkshopStore store)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    [Function(nameof(GetKidStatus))]
    public string GetKidStatus(
        [McpToolTrigger("get_kid_status",
            "Looks up one child's Nice/Naughty/Undecided status, nice score and region by first name or full name. Read-only.")]
        ToolInvocationContext context,
        [McpToolProperty("name", "The child's first name or full name, e.g. 'Timmy' or 'Timmy Thompson'.", true)]
        string name)
    {
        var kid = store.FindKidByName(name);
        return JsonSerializer.Serialize(
            kid is null ? new { error = "kid_not_found", message = $"No child named '{name}'." } : (object)kid, Json);
    }

    [Function(nameof(ListDeliverySlots))]
    public string ListDeliverySlots(
        [McpToolTrigger("list_delivery_slots",
            "Lists Christmas Eve sleigh delivery slots, optionally filtered by region (NA-EAST, NA-WEST, EUROPE, APAC). Read-only.")]
        ToolInvocationContext context,
        [McpToolProperty("region", "Optional region filter: NA-EAST, NA-WEST, EUROPE or APAC.", false)]
        string? region)
    {
        return JsonSerializer.Serialize(new { items = store.ListSlots(region) }, Json);
    }
}
