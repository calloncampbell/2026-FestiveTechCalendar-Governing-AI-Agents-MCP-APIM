using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace SantaWorkshop.Functions.Data;

public sealed record ScheduleOutcome(DeliveryResult? Delivery, string? Error, string? Message)
{
    public bool Success => Delivery is not null;
}

/// <summary>
/// Deterministic, in-memory seeded data (10,000 kids, 16 delivery slots).
/// Reads are repeatable on stage. Writes (reviews, deliveries) are explicitly simulated and
/// stateless: they validate business rules and return a confirmation with a deterministic ID.
/// </summary>
public sealed partial class WorkshopStore
{
    public const int KidCount = 10_000;
    public const int MaxPageSize = 50;
    public const int DefaultPageSize = 20;
    public const string DeliveryDate = "2026-12-24";

    private static readonly string[] FirstNames =
    [
        "Emma", "Liam", "Olivia", "Noah", "Ava", "Elijah", "Sophia", "Lucas", "Mia", "Mason",
        "Isla", "Ethan", "Zoe", "Logan", "Chloe", "Jack", "Lily", "Owen", "Ruby", "Leo",
        "Ella", "Finn", "Grace", "Henry", "Hazel", "Caleb", "Nora", "Ezra", "Aria", "Theo",
        "Maya", "Jude", "Ivy", "Felix", "Luna", "Oscar", "Alice", "Miles", "Daisy", "Ryan",
        "Freya", "Adam", "Willa", "Sam", "Clara", "Eli", "Piper", "Max", "Rosa", "Kai"
    ];

    private static readonly string[] LastNames =
    [
        "Smith", "Johnson", "Brown", "Taylor", "Wilson", "Davies", "Evans", "Walker", "White", "Roberts",
        "Green", "Hall", "Wood", "Clarke", "Hughes", "Edwards", "Turner", "Parker", "Cooper", "Morgan",
        "Bell", "Murphy", "Bailey", "Rivera", "Cook", "Kelly", "Ward", "Fox", "Gray", "James",
        "Reid", "Price", "Barnes", "Ross", "Henry", "Hayes", "Bryant", "Ford", "Hamilton", "Grant",
        "Wells", "Webb", "Fisher", "Simpson", "Stone", "Lane", "Marsh", "Nash", "Holt", "Frost"
    ];

    private static readonly (string Code, string Region, string[] Cities)[] Regions =
    [
        ("NAE", "NA-EAST", ["Toronto", "New York", "Boston", "Montreal"]),
        ("NAW", "NA-WEST", ["Vancouver", "Seattle", "San Francisco", "Los Angeles"]),
        ("EUR", "EUROPE", ["London", "Berlin", "Oslo", "Madrid"]),
        ("APAC", "APAC", ["Sydney", "Tokyo", "Auckland", "Singapore"])
    ];

    private static readonly string[] Windows =
    [
        "20:00-22:00 local", "22:00-00:00 local", "00:00-02:00 local", "02:00-04:00 local"
    ];

    private static readonly Regex DeliveryIdPattern = DeliveryIdRegex();

    private readonly Kid[] _kids;
    private readonly DeliverySlot[] _slots;

    public WorkshopStore()
    {
        _kids = new Kid[KidCount];
        for (var i = 0; i < KidCount; i++)
        {
            _kids[i] = BuildKid(i);
        }

        _slots = Regions
            .SelectMany(r => Windows.Select((w, i) =>
                new DeliverySlot($"{r.Code}-{i + 1}", r.Region, DeliveryDate, w, (4 - i) * 250)))
            .ToArray();
    }

    public int TotalKids => _kids.Length;

    // Hand-picked cast for the demo; all other kids are generated.
    private static Kid? Featured(int i) => i switch
    {
        0 => new Kid(KidId(i), "Timmy Thompson", "Timmy", 8, "Toronto", "NA-EAST",
            KidStatuses.Nice, 92, "Shared his lunch, helped with snow shovelling."),
        1 => new Kid(KidId(i), "Nigel Grumble", "Nigel", 9, "London", "EUROPE",
            KidStatuses.Naughty, 12, "Replaced the cookies with sprouts. Twice."),
        2 => new Kid(KidId(i), "Maria Santos", "Maria", 7, "Madrid", "EUROPE",
            KidStatuses.Undecided, 51, "Review pending; evidence is mixed."),
        _ => null
    };

    private static Kid BuildKid(int i)
    {
        if (Featured(i) is { } featured)
        {
            return featured;
        }

        var first = FirstNames[i % 50];
        var last = LastNames[i / 50 % 50];
        var initial = (char)('A' + i / 2500 % 4);
        var region = Regions[(i * 7 + 3) % 4];
        var city = region.Cities[(i / 4) % 4];
        var bucket = (i * 7919 + 13) % 100;
        var jitter = (i * 104729 + 7) % 1000;

        var (status, score, notes) = bucket switch
        {
            < 70 => (KidStatuses.Nice, 60 + jitter % 41, "Consistently kind."),
            < 85 => (KidStatuses.Naughty, jitter % 40, "Multiple incidents on file."),
            _ => (KidStatuses.Undecided, 40 + jitter % 20, "Review pending.")
        };

        return new Kid(KidId(i), $"{first} {initial}. {last}", first, 4 + i % 9, city, region.Region,
            status, score, notes);
    }

    private static string KidId(int index) => $"kid-{index + 1:D5}";

    public Kid? GetKidById(string id)
    {
        if (id.Length == 9 && id.StartsWith("kid-", StringComparison.OrdinalIgnoreCase) &&
            int.TryParse(id.AsSpan(4), out var n) && n is >= 1 and <= KidCount)
        {
            return _kids[n - 1];
        }

        return null;
    }

    /// <summary>Matches the full name or the first name (case-insensitive); lowest ID wins.</summary>
    public Kid? FindKidByName(string name)
    {
        var trimmed = name.Trim();
        return _kids.FirstOrDefault(k => k.Name.Equals(trimmed, StringComparison.OrdinalIgnoreCase))
            ?? _kids.FirstOrDefault(k => k.FirstName.Equals(trimmed, StringComparison.OrdinalIgnoreCase));
    }

    public PagedResult<Kid> ListKids(string? status, int page, int pageSize)
    {
        page = Math.Max(page, 1);
        pageSize = pageSize < 1 ? DefaultPageSize : Math.Min(pageSize, MaxPageSize);

        IEnumerable<Kid> query = _kids;
        if (!string.IsNullOrWhiteSpace(status))
        {
            query = query.Where(k => k.Status.Equals(status, StringComparison.OrdinalIgnoreCase));
        }

        var filtered = query.ToArray();
        var offset = ((long)page - 1) * pageSize;
        var items = offset >= filtered.Length
            ? []
            : filtered.Skip((int)offset).Take(pageSize).ToArray();
        return new PagedResult<Kid>(page, pageSize, filtered.Length, items);
    }

    public ReviewResult SubmitReview(Kid kid, string decision, string reason)
    {
        var reviewId = "rev-" + ShortHash($"{kid.Id}|{decision}|{reason}");

        // Business rule enforced in the backend, regardless of what any agent or caller asks for:
        // a Naughty child can never be promoted to Nice through this API.
        if (decision == KidStatuses.Nice && kid.Status == KidStatuses.Naughty)
        {
            return new ReviewResult(reviewId, kid.Id, decision, false,
                "Rejected: moving a child from Naughty to Nice requires Santa's manual approval. " +
                "Bulk or automated promotion is not allowed.", true);
        }

        return new ReviewResult(reviewId, kid.Id, decision, true,
            "Review recorded (simulated; no data was changed).", true);
    }

    public IReadOnlyList<DeliverySlot> ListSlots(string? region, int pageSize = 50)
    {
        IEnumerable<DeliverySlot> query = _slots;
        if (!string.IsNullOrWhiteSpace(region))
        {
            query = query.Where(s => s.Region.Equals(region, StringComparison.OrdinalIgnoreCase));
        }

        return query.Take(Math.Clamp(pageSize, 1, 50)).ToArray();
    }

    public DeliverySlot? GetSlot(string slotId) =>
        _slots.FirstOrDefault(s => s.SlotId.Equals(slotId, StringComparison.OrdinalIgnoreCase));

    public ScheduleOutcome ScheduleDelivery(string kidId, string slotId)
    {
        var kid = GetKidById(kidId);
        if (kid is null)
        {
            return new ScheduleOutcome(null, "kid_not_found", $"No child with id '{kidId}'.");
        }

        var slot = GetSlot(slotId);
        if (slot is null)
        {
            return new ScheduleOutcome(null, "slot_not_found", $"No delivery slot '{slotId}'.");
        }

        if (kid.Status != KidStatuses.Nice)
        {
            return new ScheduleOutcome(null, "not_on_nice_list",
                $"{kid.Name} is {kid.Status}: only children on the Nice list get deliveries. Coal rules apply.");
        }

        if (!kid.Region.Equals(slot.Region, StringComparison.OrdinalIgnoreCase))
        {
            return new ScheduleOutcome(null, "region_mismatch",
                $"{kid.Name} lives in {kid.Region}; slot {slot.SlotId} serves {slot.Region}.");
        }

        return new ScheduleOutcome(ToDelivery(kid, slot), null, null);
    }

    /// <summary>Delivery IDs encode the kid and slot, so lookups work without persisted state.</summary>
    public DeliveryResult? GetDelivery(string deliveryId)
    {
        var m = DeliveryIdPattern.Match(deliveryId);
        if (!m.Success)
        {
            return null;
        }

        var kid = GetKidById($"kid-{m.Groups[1].Value}");
        var slot = GetSlot(m.Groups[2].Value);
        // Only IDs that ScheduleDelivery could have produced are valid.
        return kid is null || slot is null ? null : ScheduleDelivery(kid.Id, slot.SlotId).Delivery;
    }

    private static DeliveryResult ToDelivery(Kid kid, DeliverySlot slot) =>
        new($"del-{kid.Id[4..]}-{slot.SlotId}", kid.Id, kid.Name, slot.SlotId, slot.Date, slot.Window,
            "Scheduled", true);

    private static string ShortHash(string input) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(input)))[..8].ToLowerInvariant();

    [GeneratedRegex(@"^del-(\d{5})-([A-Za-z]+-\d)$")]
    private static partial Regex DeliveryIdRegex();
}
