namespace SantaWorkshop.Functions.Data;

public sealed record Kid(
    string Id,
    string Name,
    string FirstName,
    int Age,
    string City,
    string Region,
    string Status,
    int NiceScore,
    string Notes);

public sealed record PagedResult<T>(int Page, int PageSize, int Total, IReadOnlyList<T> Items);

public sealed record DeliverySlot(
    string SlotId,
    string Region,
    string Date,
    string Window,
    int Capacity);

public sealed record ReviewResult(
    string ReviewId,
    string KidId,
    string Decision,
    bool Accepted,
    string Message,
    bool Simulated);

public sealed record DeliveryResult(
    string DeliveryId,
    string KidId,
    string KidName,
    string SlotId,
    string Date,
    string Window,
    string Status,
    bool Simulated);

public static class KidStatuses
{
    public const string Nice = "Nice";
    public const string Naughty = "Naughty";
    public const string Undecided = "Undecided";

    public static bool IsValid(string? value) =>
        value is Nice or Naughty or Undecided;
}
