using System.Text.Json.Serialization;

public sealed record ShipmentRecord(
    [property: JsonPropertyName("shipment_id")] string ShipmentId,
    [property: JsonPropertyName("partner")] string Partner,
    [property: JsonPropertyName("ship_date")] string ShipDate,
    [property: JsonPropertyName("service_level")] string ServiceLevel,
    [property: JsonPropertyName("ship_to")] ShippingAddress ShipTo,
    [property: JsonPropertyName("items")] IReadOnlyList<ShipmentItem> Items);

public sealed record ShippingAddress(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("address_line1")] string AddressLine1,
    [property: JsonPropertyName("city")] string City,
    [property: JsonPropertyName("state_or_province")] string StateOrProvince,
    [property: JsonPropertyName("postal_code")] string PostalCode,
    [property: JsonPropertyName("country_code")] string CountryCode);

public sealed record ShipmentItem(
    [property: JsonPropertyName("sku")] string Sku,
    [property: JsonPropertyName("description")] string Description,
    [property: JsonPropertyName("quantity")] int Quantity,
    [property: JsonPropertyName("unit_weight_kg")] decimal UnitWeightKg);

public sealed record StoredShipmentResult(
    [property: JsonPropertyName("shipment_id")] string ShipmentId,
    [property: JsonPropertyName("recovered_by_hosted_skill")] bool RecoveredByHostedSkill,
    [property: JsonPropertyName("created_at")] string CreatedAt,
    [property: JsonPropertyName("pdf_bytes")] int PdfBytes,
    [property: JsonPropertyName("canonical_blob")] string CanonicalBlob,
    [property: JsonPropertyName("html_blob")] string HtmlBlob,
    [property: JsonPropertyName("pdf_blob")] string PdfBlob,
    [property: JsonPropertyName("shipment")] ShipmentRecord Shipment);
