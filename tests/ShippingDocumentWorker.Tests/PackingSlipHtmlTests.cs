using System.Text;

namespace ShippingDocumentWorker.Tests;

public sealed class PackingSlipHtmlTests
{
    [Fact]
    public void EncodesCustomerControlledText()
    {
        ShipmentRecord shipment = ShipmentParser.Parse(
            Encoding.UTF8.GetBytes(
                ShipmentParserTests.ValidJson.Replace(
                    "Blue widget",
                    "<script>alert(1)</script>",
                    StringComparison.Ordinal)));

        string html = PackingSlipHtml.Render(shipment, false);

        Assert.DoesNotContain("<script>", html, StringComparison.Ordinal);
        Assert.Contains(
            "&lt;script&gt;alert(1)&lt;/script&gt;",
            html,
            StringComparison.Ordinal);
    }

    [Fact]
    public void MarksRecoveredInput()
    {
        ShipmentRecord shipment = ShipmentParser.Parse(
            Encoding.UTF8.GetBytes(ShipmentParserTests.ValidJson));

        string html = PackingSlipHtml.Render(shipment, true);

        Assert.Contains("normalized by the Azure Functions Hosted Skill", html);
    }
}
