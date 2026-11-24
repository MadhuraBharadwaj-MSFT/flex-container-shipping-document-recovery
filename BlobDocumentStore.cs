using System.Text;
using System.Text.Json;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;

public sealed class BlobDocumentStore(BlobServiceClient serviceClient)
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
    };

    private readonly string containerName =
        Environment.GetEnvironmentVariable("DOCUMENT_CONTAINER") ??
        "generated-documents";

    public async Task<StoredShipmentResult> StoreAsync(
        ShipmentRecord shipment,
        string html,
        byte[] pdf,
        bool recoveredByHostedSkill,
        CancellationToken cancellationToken)
    {
        BlobContainerClient container =
            serviceClient.GetBlobContainerClient(containerName);
        var prefix = shipment.ShipmentId;
        var canonicalName = $"{prefix}/shipment.json";
        var htmlName = $"{prefix}/packing-slip.html";
        var pdfName = $"{prefix}/packing-slip.pdf";
        var resultName = $"{prefix}/result.json";

        await UploadAsync(
            container,
            canonicalName,
            JsonSerializer.SerializeToUtf8Bytes(shipment, JsonOptions),
            "application/json",
            cancellationToken);
        await UploadAsync(
            container,
            htmlName,
            Encoding.UTF8.GetBytes(html),
            "text/html; charset=utf-8",
            cancellationToken);
        await UploadAsync(
            container,
            pdfName,
            pdf,
            "application/pdf",
            cancellationToken);

        var result = new StoredShipmentResult(
            shipment.ShipmentId,
            recoveredByHostedSkill,
            DateTimeOffset.UtcNow.ToString("O"),
            pdf.Length,
            canonicalName,
            htmlName,
            pdfName,
            shipment);
        await UploadAsync(
            container,
            resultName,
            JsonSerializer.SerializeToUtf8Bytes(result, JsonOptions),
            "application/json",
            cancellationToken);
        return result;
    }

    private static Task UploadAsync(
        BlobContainerClient container,
        string name,
        byte[] content,
        string contentType,
        CancellationToken cancellationToken) =>
        container.GetBlobClient(name).UploadAsync(
            BinaryData.FromBytes(content),
            new BlobUploadOptions
            {
                HttpHeaders = new BlobHttpHeaders
                {
                    ContentType = contentType,
                    CacheControl = "no-store",
                },
            },
            cancellationToken);
}
