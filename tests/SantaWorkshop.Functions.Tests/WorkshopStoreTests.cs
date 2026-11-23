using SantaWorkshop.Functions.Data;
using Xunit;

namespace SantaWorkshop.Functions.Tests;

public class WorkshopStoreTests
{
    private readonly WorkshopStore _store = new();

    [Fact]
    public void Seed_IsDeterministicAndHasTenThousandUniqueKids()
    {
        var other = new WorkshopStore();
        var all = _store.ListKids(null, 1, WorkshopStore.MaxPageSize);

        Assert.Equal(10_000, _store.TotalKids);
        Assert.Equal(10_000, all.Total);
        Assert.Equal(other.GetKidById("kid-04242"), _store.GetKidById("kid-04242"));

        var names = Enumerable.Range(1, 10_000).Select(n => _store.GetKidById($"kid-{n:D5}")!.Name);
        Assert.Equal(10_000, names.Distinct(StringComparer.OrdinalIgnoreCase).Count());
    }

    [Fact]
    public void ListKids_HugePageNumber_ReturnsEmptyPage()
    {
        var page = _store.ListKids(null, 42_949_674, 50);

        Assert.Empty(page.Items);
    }

    [Theory]
    [InlineData("del-00002-EUR-1")] // Naughty child
    [InlineData("del-00001-EUR-1")] // wrong region
    public void GetDelivery_RejectsIdsThatCouldNotBeScheduled(string id)
    {
        Assert.Null(_store.GetDelivery(id));
    }

    [Fact]
    public void Timmy_IsOnTheNiceList()
    {
        var kid = _store.FindKidByName("timmy");
        Assert.NotNull(kid);
        Assert.Equal("kid-00001", kid.Id);
        Assert.Equal(KidStatuses.Nice, kid.Status);
        Assert.Equal("NA-EAST", kid.Region);
    }

    [Theory]
    [InlineData(0, 20)]
    [InlineData(1000, 50)]
    [InlineData(-5, 20)]
    public void ListKids_ClampsPageSize(int requested, int expected) =>
        Assert.Equal(expected, _store.ListKids(null, 1, requested).Items.Count);

    [Fact]
    public void ListKids_FiltersByStatus()
    {
        var page = _store.ListKids("naughty", 1, 50);
        Assert.All(page.Items, k => Assert.Equal(KidStatuses.Naughty, k.Status));
        Assert.True(page.Total > 0);
    }

    [Fact]
    public void Review_CannotPromoteNaughtyToNice()
    {
        var nigel = _store.FindKidByName("Nigel")!;
        var result = _store.SubmitReview(nigel, KidStatuses.Nice, "Bulk approval requested by agent");
        Assert.False(result.Accepted);
        Assert.True(result.Simulated);
    }

    [Fact]
    public void Review_IsAcceptedWithDeterministicId()
    {
        var timmy = _store.FindKidByName("Timmy")!;
        var a = _store.SubmitReview(timmy, KidStatuses.Naughty, "Ate the cookies meant for Santa");
        var b = _store.SubmitReview(timmy, KidStatuses.Naughty, "Ate the cookies meant for Santa");
        Assert.True(a.Accepted);
        Assert.Equal(a.ReviewId, b.ReviewId);
    }

    [Fact]
    public void Schedule_SucceedsForNiceKidInRegion_AndRoundTrips()
    {
        var outcome = _store.ScheduleDelivery("kid-00001", "NAE-2");
        Assert.True(outcome.Success);
        Assert.Equal("del-00001-NAE-2", outcome.Delivery!.DeliveryId);
        Assert.Equal(outcome.Delivery, _store.GetDelivery(outcome.Delivery.DeliveryId));
    }

    [Theory]
    [InlineData("kid-00002", "EUR-1", "not_on_nice_list")]
    [InlineData("kid-00001", "EUR-1", "region_mismatch")]
    [InlineData("kid-00001", "XXX-9", "slot_not_found")]
    [InlineData("kid-99999", "NAE-1", "kid_not_found")]
    public void Schedule_EnforcesRules(string kidId, string slotId, string error) =>
        Assert.Equal(error, _store.ScheduleDelivery(kidId, slotId).Error);

    [Fact]
    public void GetDelivery_RejectsMalformedIds() => Assert.Null(_store.GetDelivery("nope"));
}
