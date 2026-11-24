using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

public static partial class ShipmentParser
{
    private static readonly HashSet<string> ServiceLevels =
        new(StringComparer.Ordinal)
        {
            "standard",
            "priority",
            "overnight",
        };

    public static ShipmentRecord Parse(ReadOnlyMemory<byte> body)
    {
        try
        {
            using var document = JsonDocument.Parse(body);
            JsonElement root = document.RootElement;
            RequireObject(root, "shipment");
            RequireExactProperties(
                root,
                "shipment_id",
                "partner",
                "ship_date",
                "service_level",
                "ship_to",
                "items");

            var shipmentId = RequiredString(root, "shipment_id", 1, 80);
            if (!ShipmentIdPattern().IsMatch(shipmentId))
            {
                throw Invalid(
                    "shipment_id must contain only lowercase letters, digits, and hyphens.");
            }

            var partner = RequiredString(root, "partner", 1, 80);
            var shipDate = RequiredString(root, "ship_date", 10, 10);
            if (!DateOnly.TryParseExact(
                    shipDate,
                    "yyyy-MM-dd",
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.None,
                    out _))
            {
                throw Invalid("ship_date must use YYYY-MM-DD.");
            }

            var serviceLevel = RequiredString(root, "service_level", 1, 20);
            if (!ServiceLevels.Contains(serviceLevel))
            {
                throw Invalid(
                    "service_level must be standard, priority, or overnight.");
            }

            ShippingAddress address = ParseAddress(
                root.GetProperty("ship_to"));
            IReadOnlyList<ShipmentItem> items = ParseItems(
                root.GetProperty("items"));

            return new ShipmentRecord(
                shipmentId,
                partner.Trim(),
                shipDate,
                serviceLevel,
                address,
                items);
        }
        catch (ShipmentValidationException)
        {
            throw;
        }
        catch (JsonException exception)
        {
            throw Invalid("The message body must contain valid JSON.", exception);
        }
    }

    private static ShippingAddress ParseAddress(JsonElement value)
    {
        RequireObject(value, "ship_to");
        RequireExactProperties(
            value,
            "name",
            "address_line1",
            "city",
            "state_or_province",
            "postal_code",
            "country_code");

        var countryCode = RequiredString(value, "country_code", 2, 2);
        if (!CountryCodePattern().IsMatch(countryCode))
        {
            throw Invalid("country_code must be two uppercase letters.");
        }

        return new ShippingAddress(
            RequiredString(value, "name", 1, 100).Trim(),
            RequiredString(value, "address_line1", 1, 120).Trim(),
            RequiredString(value, "city", 1, 80).Trim(),
            RequiredString(value, "state_or_province", 1, 80).Trim(),
            RequiredString(value, "postal_code", 1, 20).Trim(),
            countryCode);
    }

    private static IReadOnlyList<ShipmentItem> ParseItems(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Array)
        {
            throw Invalid("items must be an array.");
        }

        var items = new List<ShipmentItem>();
        foreach (JsonElement element in value.EnumerateArray())
        {
            if (items.Count == 20)
            {
                throw Invalid("items cannot contain more than 20 entries.");
            }

            RequireObject(element, "item");
            RequireExactProperties(
                element,
                "sku",
                "description",
                "quantity",
                "unit_weight_kg");

            JsonElement quantityValue = element.GetProperty("quantity");
            if (quantityValue.ValueKind != JsonValueKind.Number ||
                !quantityValue.TryGetInt32(out var quantity) ||
                quantity is < 1 or > 1000)
            {
                throw Invalid("item quantity must be an integer from 1 to 1000.");
            }

            JsonElement weightValue = element.GetProperty("unit_weight_kg");
            if (weightValue.ValueKind != JsonValueKind.Number ||
                !weightValue.TryGetDecimal(out var unitWeight) ||
                unitWeight is < 0.01m or > 1000m)
            {
                throw Invalid(
                    "item unit_weight_kg must be a number from 0.01 to 1000.");
            }

            items.Add(new ShipmentItem(
                RequiredString(element, "sku", 1, 40).Trim(),
                RequiredString(element, "description", 1, 120).Trim(),
                quantity,
                unitWeight));
        }

        if (items.Count == 0)
        {
            throw Invalid("items must contain at least one entry.");
        }

        return items;
    }

    private static string RequiredString(
        JsonElement element,
        string propertyName,
        int minLength,
        int maxLength)
    {
        if (!element.TryGetProperty(propertyName, out JsonElement value) ||
            value.ValueKind != JsonValueKind.String)
        {
            throw Invalid($"{propertyName} must be a string.");
        }

        var result = value.GetString() ?? string.Empty;
        if (result.Length < minLength || result.Length > maxLength)
        {
            throw Invalid(
                $"{propertyName} must contain {minLength}-{maxLength} characters.");
        }

        return result;
    }

    private static void RequireObject(JsonElement element, string name)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            throw Invalid($"{name} must be a JSON object.");
        }
    }

    private static void RequireExactProperties(
        JsonElement element,
        params string[] expected)
    {
        var allowed = expected.ToHashSet(StringComparer.Ordinal);
        var actual = element
            .EnumerateObject()
            .Select(property => property.Name)
            .ToArray();

        foreach (var name in expected)
        {
            if (!actual.Contains(name, StringComparer.Ordinal))
            {
                throw Invalid($"Required field '{name}' is missing.");
            }
        }

        string? extra = actual.FirstOrDefault(name => !allowed.Contains(name));
        if (extra is not null)
        {
            throw Invalid($"Unexpected field '{extra}'.");
        }
    }

    private static ShipmentValidationException Invalid(
        string message,
        Exception? innerException = null) =>
        new(message, innerException);

    [GeneratedRegex("^[a-z0-9-]+$", RegexOptions.CultureInvariant)]
    private static partial Regex ShipmentIdPattern();

    [GeneratedRegex("^[A-Z]{2}$", RegexOptions.CultureInvariant)]
    private static partial Regex CountryCodePattern();
}

public sealed class ShipmentValidationException(
    string message,
    Exception? innerException = null)
    : Exception(message, innerException);
