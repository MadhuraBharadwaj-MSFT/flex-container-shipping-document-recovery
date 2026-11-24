using System.Text;

namespace ShippingDocumentWorker.Tests;

public sealed class ShipmentParserTests
{
    [Fact]
    public void ParsesCanonicalShipment()
    {
        ShipmentRecord result = ShipmentParser.Parse(
            Encoding.UTF8.GetBytes(ValidJson));

        Assert.Equal("demo-shipment", result.ShipmentId);
        Assert.Equal("Contoso Logistics", result.Partner);
        Assert.Equal("US", result.ShipTo.CountryCode);
        Assert.Equal(2, result.Items.Count);
        Assert.Equal(3, result.Items.Sum(item => item.Quantity));
    }

    [Theory]
    [InlineData("\"shipmentId\":\"demo-shipment\"", "shipment_id")]
    [InlineData("\"ship_date\":\"11/25/2026\"", "YYYY-MM-DD")]
    [InlineData("\"country_code\":\"us\"", "uppercase")]
    [InlineData("\"quantity\":\"2\"", "integer")]
    [InlineData("\"unit_weight_kg\":\"1.25\"", "number")]
    public void RejectsRepairableFormattingErrors(
        string replacement,
        string expectedMessage)
    {
        string invalid = replacement.StartsWith("\"shipmentId\"", StringComparison.Ordinal)
            ? ValidJson.Replace(
                "\"shipment_id\":\"demo-shipment\"",
                replacement,
                StringComparison.Ordinal)
            : replacement.StartsWith("\"ship_date\"", StringComparison.Ordinal)
                ? ValidJson.Replace(
                    "\"ship_date\":\"2026-11-25\"",
                    replacement,
                    StringComparison.Ordinal)
                : replacement.StartsWith("\"country_code\"", StringComparison.Ordinal)
                    ? ValidJson.Replace(
                        "\"country_code\":\"US\"",
                        replacement,
                        StringComparison.Ordinal)
                    : replacement.StartsWith("\"quantity\"", StringComparison.Ordinal)
                        ? ValidJson.Replace(
                            "\"quantity\":2",
                            replacement,
                            StringComparison.Ordinal)
                        : ValidJson.Replace(
                            "\"unit_weight_kg\":1.25",
                            replacement,
                            StringComparison.Ordinal);

        var exception = Assert.Throws<ShipmentValidationException>(() =>
            ShipmentParser.Parse(Encoding.UTF8.GetBytes(invalid)));

        Assert.Contains(expectedMessage, exception.Message);
    }

    internal const string ValidJson =
        """
        {
          "shipment_id":"demo-shipment",
          "partner":"Contoso Logistics",
          "ship_date":"2026-11-25",
          "service_level":"priority",
          "ship_to":{
            "name":"A. Customer",
            "address_line1":"1 Main Street",
            "city":"Seattle",
            "state_or_province":"WA",
            "postal_code":"98101",
            "country_code":"US"
          },
          "items":[
            {"sku":"SKU-100","description":"Blue widget","quantity":2,"unit_weight_kg":1.25},
            {"sku":"SKU-200","description":"Packing insert","quantity":1,"unit_weight_kg":0.10}
          ]
        }
        """;
}
