using Azure.Identity;
using Azure.Storage.Blobs;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

FunctionsApplicationBuilder builder = FunctionsApplication.CreateBuilder(args);
builder.ConfigureFunctionsWebApplication();

builder.Services.AddSingleton(_ =>
{
    var serviceUri = Environment.GetEnvironmentVariable("DATA_STORAGE_BLOB_URL");
    if (!Uri.TryCreate(serviceUri, UriKind.Absolute, out var uri))
    {
        throw new InvalidOperationException("DATA_STORAGE_BLOB_URL is required.");
    }

    var clientId = Environment.GetEnvironmentVariable("AZURE_CLIENT_ID");
    var credential = new DefaultAzureCredential(
        new DefaultAzureCredentialOptions
        {
            ManagedIdentityClientId = string.IsNullOrWhiteSpace(clientId)
                ? null
                : clientId,
        });
    return new BlobServiceClient(uri, credential);
});
builder.Services.AddSingleton<PdfRenderer>();
builder.Services.AddSingleton<BlobDocumentStore>();
builder.Services.AddSingleton<DemoTracking>();

await builder.Build().RunAsync();
