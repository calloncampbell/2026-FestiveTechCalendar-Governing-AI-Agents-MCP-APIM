using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using SantaWorkshop.Functions.Data;

namespace SantaWorkshop.Functions.SleighLogistics;

public sealed record DeliveryRequest(string? KidId, string? SlotId);

/// <summary>Sleigh Logistics API. Contract: openapi/sleigh-logistics.yaml.</summary>
public sealed class SleighLogisticsFunctions(WorkshopStore store)
{
    [Function("ListSlots")]
    public IActionResult ListSlots(
        [HttpTrigger(AuthorizationLevel.Function, "get", Route = "slots")] HttpRequest req)
    {
        _ = int.TryParse(req.Query["pageSize"], out var pageSize);
        var slots = store.ListSlots(req.Query["region"].ToString(), pageSize == 0 ? 50 : pageSize);
        return new OkObjectResult(new { items = slots });
    }

    [Function("ScheduleDelivery")]
    public IActionResult ScheduleDelivery(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "deliveries")] HttpRequest req,
        [FromBody] DeliveryRequest? body)
    {
        if (body is null || string.IsNullOrWhiteSpace(body.KidId) || string.IsNullOrWhiteSpace(body.SlotId))
        {
            return new BadRequestObjectResult(new { error = "invalid_request", message = "kidId and slotId are required." });
        }

        var outcome = store.ScheduleDelivery(body.KidId, body.SlotId);
        if (outcome.Success)
        {
            return new ObjectResult(outcome.Delivery) { StatusCode = StatusCodes.Status201Created };
        }

        var status = outcome.Error is "kid_not_found" or "slot_not_found"
            ? StatusCodes.Status404NotFound
            : StatusCodes.Status409Conflict;
        return new ObjectResult(new { error = outcome.Error, message = outcome.Message }) { StatusCode = status };
    }

    [Function("GetDelivery")]
    public IActionResult GetDelivery(
        [HttpTrigger(AuthorizationLevel.Function, "get", Route = "deliveries/{id}")] HttpRequest req,
        string id)
    {
        var delivery = store.GetDelivery(id);
        return delivery is null
            ? new NotFoundObjectResult(new { error = "delivery_not_found", message = $"No delivery '{id}'." })
            : new OkObjectResult(delivery);
    }
}
