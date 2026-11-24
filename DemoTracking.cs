using System.Text.Json;
using System.Text.RegularExpressions;
using Azure;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Logging;

public sealed partial class DemoTracking(
    BlobServiceClient serviceClient,
    ILogger<DemoTracking> logger)
{
    private readonly string containerName =
        Environment.GetEnvironmentVariable("DEMO_RUNS_CONTAINER") ??
        "demo-runs";

    public async Task RecordAsync(
        ServiceBusReceivedMessage message,
        string stage,
        string? detail,
        CancellationToken cancellationToken)
    {
        var runId = RunId(message);
        if (runId is null)
        {
            return;
        }

        var body = JsonSerializer.SerializeToUtf8Bytes(new
        {
            stage,
            observed_at = DateTimeOffset.UtcNow.ToString("O"),
            message_id = message.MessageId,
            delivery_count = message.DeliveryCount,
            detail,
        });
        var blobName =
            $"flow/{runId}/{stage}/{Guid.NewGuid():N}.json";
        try
        {
            await serviceClient
                .GetBlobContainerClient(containerName)
                .GetBlobClient(blobName)
                .UploadAsync(
                    BinaryData.FromBytes(body),
                    new BlobUploadOptions
                    {
                        HttpHeaders = new BlobHttpHeaders
                        {
                            ContentType = "application/json",
                            CacheControl = "no-store",
                        },
                    },
                    cancellationToken);
        }
        catch (RequestFailedException exception)
        {
            logger.LogWarning(
                exception,
                "Demo tracking failed for stage {Stage} and message {MessageId}.",
                stage,
                message.MessageId);
        }
    }

    private static string? RunId(ServiceBusReceivedMessage message)
    {
        var messageId = message.MessageId ?? string.Empty;
        var runId = messageId.StartsWith(
            "repair-",
            StringComparison.Ordinal)
            ? messageId["repair-".Length..]
            : messageId;
        return RunIdPattern().IsMatch(runId) ? runId : null;
    }

    [GeneratedRegex("^[a-f0-9]{32}$", RegexOptions.CultureInvariant)]
    private static partial Regex RunIdPattern();
}
