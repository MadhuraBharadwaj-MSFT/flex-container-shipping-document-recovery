using System.Globalization;
using System.Net;
using System.Text;

public static class PackingSlipHtml
{
    public static string Render(
        ShipmentRecord shipment,
        bool recoveredByHostedSkill)
    {
        static string Encode(string value) => WebUtility.HtmlEncode(value);

        var totalUnits = shipment.Items.Sum(item => item.Quantity);
        var totalWeight = shipment.Items.Sum(
            item => item.Quantity * item.UnitWeightKg);
        var rows = new StringBuilder();
        foreach (ShipmentItem item in shipment.Items)
        {
            rows.Append(
                $"""
                <tr>
                  <td>{Encode(item.Sku)}</td>
                  <td>{Encode(item.Description)}</td>
                  <td class="number">{item.Quantity}</td>
                  <td class="number">{item.UnitWeightKg.ToString("0.00", CultureInfo.InvariantCulture)}</td>
                  <td class="number">{(item.Quantity * item.UnitWeightKg).ToString("0.00", CultureInfo.InvariantCulture)}</td>
                </tr>
                """);
        }

        var recovery = recoveredByHostedSkill
            ? """
              <div class="recovery">
                Input formatting was normalized by the Azure Functions Hosted Skill,
                then revalidated by the deterministic document worker.
              </div>
              """
            : string.Empty;

        return $$"""
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <title>Packing slip {{Encode(shipment.ShipmentId)}}</title>
              <style>
                @page { size: A4; margin: 14mm; }
                * { box-sizing: border-box; }
                body { color: #172033; font: 14px/1.5 Arial, sans-serif; margin: 0; }
                header { align-items: flex-start; border-bottom: 3px solid #2563eb; display: flex; justify-content: space-between; padding-bottom: 16px; }
                h1 { font-size: 30px; margin: 0 0 4px; }
                h2 { font-size: 15px; margin: 0 0 8px; text-transform: uppercase; }
                .muted { color: #667085; }
                .meta { text-align: right; }
                .grid { display: grid; gap: 20px; grid-template-columns: 1fr 1fr; margin: 24px 0; }
                .panel { background: #f7f9fc; border: 1px solid #e1e7ef; border-radius: 8px; padding: 16px; }
                .recovery { background: #f3e8ff; border: 1px solid #d8b4fe; border-radius: 8px; color: #6b21a8; margin: 18px 0; padding: 12px 14px; }
                table { border-collapse: collapse; width: 100%; }
                th { background: #eaf1ff; color: #29436f; font-size: 12px; text-align: left; text-transform: uppercase; }
                th, td { border-bottom: 1px solid #dfe5ed; padding: 10px 8px; }
                .number { text-align: right; }
                .totals { display: flex; gap: 32px; justify-content: flex-end; margin-top: 20px; }
                .total strong { display: block; font-size: 22px; }
                footer { color: #667085; font-size: 11px; margin-top: 36px; text-align: center; }
              </style>
            </head>
            <body>
              <header>
                <div>
                  <h1>Packing slip</h1>
                  <div class="muted">{{Encode(shipment.Partner)}}</div>
                </div>
                <div class="meta">
                  <strong>{{Encode(shipment.ShipmentId)}}</strong><br>
                  Ship date: {{Encode(shipment.ShipDate)}}<br>
                  Service: {{Encode(shipment.ServiceLevel)}}
                </div>
              </header>
              {{recovery}}
              <section class="grid">
                <div class="panel">
                  <h2>Ship to</h2>
                  <strong>{{Encode(shipment.ShipTo.Name)}}</strong><br>
                  {{Encode(shipment.ShipTo.AddressLine1)}}<br>
                  {{Encode(shipment.ShipTo.City)}}, {{Encode(shipment.ShipTo.StateOrProvince)}} {{Encode(shipment.ShipTo.PostalCode)}}<br>
                  {{Encode(shipment.ShipTo.CountryCode)}}
                </div>
                <div class="panel">
                  <h2>Handling</h2>
                  Verify every item before sealing the shipment. Keep this packing
                  slip with the package until delivery.
                </div>
              </section>
              <table>
                <thead>
                  <tr><th>SKU</th><th>Description</th><th class="number">Qty</th><th class="number">Unit kg</th><th class="number">Total kg</th></tr>
                </thead>
                <tbody>{{rows}}</tbody>
              </table>
              <section class="totals">
                <div class="total"><span class="muted">Units</span><strong>{{totalUnits}}</strong></div>
                <div class="total"><span class="muted">Weight</span><strong>{{totalWeight.ToString("0.00", CultureInfo.InvariantCulture)}} kg</strong></div>
              </section>
              <footer>Generated by Azure Functions from a validated shipping record.</footer>
            </body>
            </html>
            """;
    }
}
