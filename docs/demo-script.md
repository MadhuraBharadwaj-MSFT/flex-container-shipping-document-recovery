# Five-minute demo script

## 1. Set the story

Open the **Architecture** tab.

> A partner sends shipment records through Service Bus. The .NET worker is the
> deterministic authority: it validates data, builds safe HTML, runs Chromium,
> and stores the packing slip. AI is used only when a partner's record has a
> known formatting mismatch.

Point out that the .NET worker image contains Chromium and fonts but not the
Functions host. Azure continues to provide triggers, routing, and scaling.

## 2. Run the valid path

1. Open **Try it**.
1. Select **Load valid record**.
1. Call out the canonical field names and typed numbers.
1. Select **Generate packing slip**.
1. Follow the confirmed Service Bus, worker, and Blob stages.
1. Inspect the generated HTML.
1. Open the PDF.

## 3. Run the recovery path

1. Select **Load repairable record**.
1. Point out `shipmentId`, string quantities, `MM/DD/YYYY`, and `countryCode:
   "us"`.
1. Generate the packing slip.
1. Explain that the same .NET worker rejects the record.
1. Follow it through the DLQ and Hosted Skill.
1. Compare submitted and canonical JSON.
1. Show the **Recovered by Hosted Skill** badge.
1. Open the generated PDF.

## 4. Close with the boundary

> The model can normalize only documented formatting differences. It cannot
> invent addresses, items, quantities, or weights. A repaired message returns
> to the same queue and must pass the same deterministic validator.

Open Application Insights to show the Function, model, and connector spans if
time permits.
