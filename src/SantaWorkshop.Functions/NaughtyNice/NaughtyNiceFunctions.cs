using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using SantaWorkshop.Functions.Data;

namespace SantaWorkshop.Functions.NaughtyNice;

public sealed record ReviewRequest(string? Decision, string? Reason);

/// <summary>Naughty-or-Nice API. Contract: openapi/naughty-nice.yaml.</summary>
public sealed class NaughtyNiceFunctions(WorkshopStore store)
{
    [Function("GetKidByName")]
    public IActionResult GetKidByName(
        [HttpTrigger(AuthorizationLevel.Function, "get", Route = "kids/{name}")] HttpRequest req,
        string name)
    {
        var kid = store.FindKidByName(name);
        return kid is null
            ? new NotFoundObjectResult(new { error = "kid_not_found", message = $"No child named '{name}'." })
            : new OkObjectResult(kid);
    }

    [Function("ListKids")]
    public IActionResult ListKids(
        [HttpTrigger(AuthorizationLevel.Function, "get", Route = "kids")] HttpRequest req)
    {
        var status = req.Query["status"].ToString();
        if (!string.IsNullOrEmpty(status) && !KidStatuses.IsValid(
                status.Length > 0 ? char.ToUpperInvariant(status[0]) + status[1..].ToLowerInvariant() : status))
        {
            return new BadRequestObjectResult(new { error = "invalid_status", message = "status must be Nice, Naughty or Undecided." });
        }

        _ = int.TryParse(req.Query["page"], out var page);
        _ = int.TryParse(req.Query["pageSize"], out var pageSize);
        return new OkObjectResult(store.ListKids(status, page, pageSize));
    }

    [Function("SubmitReview")]
    public IActionResult SubmitReview(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "kids/{id}/review")] HttpRequest req,
        string id,
        [FromBody] ReviewRequest? body)
    {
        var kid = store.GetKidById(id);
        if (kid is null)
        {
            return new NotFoundObjectResult(new { error = "kid_not_found", message = $"No child with id '{id}'." });
        }

        if (body is null || !KidStatuses.IsValid(body.Decision) || body.Decision == KidStatuses.Undecided)
        {
            return new BadRequestObjectResult(new { error = "invalid_decision", message = "decision must be Nice or Naughty." });
        }

        if (string.IsNullOrWhiteSpace(body.Reason) || body.Reason.Trim().Length < 10)
        {
            return new BadRequestObjectResult(new { error = "reason_required", message = "reason must be at least 10 characters." });
        }

        var result = store.SubmitReview(kid, body.Decision!, body.Reason.Trim());
        return result.Accepted
            ? new OkObjectResult(result)
            : new ObjectResult(result) { StatusCode = StatusCodes.Status409Conflict };
    }
}
