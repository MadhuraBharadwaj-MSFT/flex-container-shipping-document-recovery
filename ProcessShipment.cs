using System.Text;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

public sealed class ProcessShipment(
    PdfRenderer renderer,
    BlobDocumentStore store,
    DemoTracking tracking,
    ILogger<ProcessShipment> logger)
{
    [Function(nameof(ProcessShipment))]
    public async Task Run(
        [ServiceBusTrigger(
            "%SHIPMENT_QUEUE%",
            Connection = "ServiceBusConnection")]
        ServiceBusReceivedMessage message,
        CancellationToken cancellationToken)
    {
        var recovered = message.MessageId?.StartsWith(
            "repair-",
            StringComparison.Ordinal) == true ||
            message.ApplicationProperties.TryGetValue(
                "repaired",
                out object? repairedValue) &&
            repairedValue is true;

        await tracking.RecordAsync(
            message,
            recovered ? "requeued" : "received",
            null,
            cancellationToken);

        ShipmentRecord shipment;
        try
        {
            shipment = ShipmentParser.Parse(message.Body.ToMemory());
        }
        catch (ShipmentValidationException exception)
        {
            await tracking.RecordAsync(
                message,
                recovered ? "requeue_rejected" : "rejected",
                exception.Message,
                cancellationToken);
            logger.LogWarning(
                exception,
                "Shipment validation failed for message {MessageId}.",
                message.MessageId);
            throw;
        }

        string html = PackingSlipHtml.Render(shipment, recovered);
        byte[] pdf = await renderer.RenderAsync(html, cancellationToken);
        StoredShipmentResult result = await store.StoreAsync(
            shipment,
            html,
            pdf,
            recovered,
            cancellationToken);
        await tracking.RecordAsync(
            message,
            "output_saved",
            result.PdfBlob,
            cancellationToken);

        logger.LogInformation(
            "shipment_document_completed shipment_id={ShipmentId} recovered={Recovered} pdf_bytes={PdfBytes}",
            shipment.ShipmentId,
            recovered,
            pdf.Length);
    }
}
