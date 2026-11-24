using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace DeployHelper;

public static class DeploymentOperations
{
    private static readonly string[] StaticHashInputs =
    [
        ".dockerignore",
        "dotnet10.Dockerfile",
        "ShippingDocumentWorker.csproj",
        "host.json",
        "NuGet.config",
        Path.Combine(
            "tests",
            "ShippingDocumentWorker.Tests",
            "ShippingDocumentWorker.Tests.csproj"),
        Path.Combine("tests", "RenderCheck", "Program.cs"),
        Path.Combine("tests", "RenderCheck", "RenderCheck.csproj"),
    ];

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    public static void Run(string[] arguments)
    {
        switch (arguments)
        {
            case ["stage-context", var destination, var publishRoot]:
                Console.Write(PrepareImageContext(
                    Directory.GetCurrentDirectory(),
                    destination,
                    publishRoot));
                return;
            case ["source-hash"]:
                Console.Write(HashBuildInputs(Directory.GetCurrentDirectory()));
                return;
            case ["write-parameters", var path]:
                WriteParameters(path);
                return;
            default:
                throw new InvalidOperationException(
                    "Usage: DeployHelper stage-context <destination> <publish-root> | source-hash | write-parameters <path>");
        }
    }

    internal static string PrepareImageContext(
        string repositoryRoot,
        string destinationRoot,
        string publishRoot)
    {
        string destination = Path.GetFullPath(destinationRoot);
        string publish = Path.GetFullPath(publishRoot);
        Directory.CreateDirectory(destination);
        if (Directory.EnumerateFileSystemEntries(destination).Any())
        {
            throw new InvalidOperationException(
                $"Image-context destination must be empty: {destination}");
        }

        CopyFile(
            Path.Combine(repositoryRoot, ".dockerignore"),
            Path.Combine(destination, ".dockerignore"));
        CopyFile(
            Path.Combine(repositoryRoot, "dotnet10.Dockerfile"),
            Path.Combine(destination, "dotnet10.Dockerfile"));

        foreach (var required in new[]
        {
            Path.Combine("app", "ShippingDocumentWorker.dll"),
            Path.Combine("rendercheck", "RenderCheck.dll"),
        })
        {
            string path = Path.Combine(publish, required);
            if (!File.Exists(path))
            {
                throw new FileNotFoundException(
                    $"Required published output is missing: {path}",
                    path);
            }
        }

        foreach (string file in Directory
                     .EnumerateFiles(publish, "*", SearchOption.AllDirectories)
                     .Order(StringComparer.Ordinal))
        {
            string relative = Path.GetRelativePath(publish, file);
            CopyFile(file, Path.Combine(destination, "publish", relative));
        }

        return HashBuildInputs(repositoryRoot);
    }

    internal static string HashBuildInputs(string repositoryRoot)
    {
        using var digest = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        Append(digest, "shipping-document-worker-context-v1\0");
        foreach ((string source, string relative) in BuildInputs(repositoryRoot))
        {
            byte[] content = File.ReadAllBytes(source);
            Append(
                digest,
                $"file\0{relative.Replace(Path.DirectorySeparatorChar, '/')}\0{content.Length}\0");
            digest.AppendData(content);
            digest.AppendData([0]);
        }
        return Convert.ToHexString(digest.GetHashAndReset()).ToLowerInvariant();
    }

    internal static IReadOnlyList<(string Source, string Relative)> BuildInputs(
        string repositoryRoot)
    {
        var files = new List<(string Source, string Relative)>();
        foreach (string relative in StaticHashInputs)
        {
            string source = Path.Combine(repositoryRoot, relative);
            if (!File.Exists(source))
            {
                throw new FileNotFoundException(
                    $"Required build input is missing: {source}",
                    source);
            }
            files.Add((source, relative));
        }

        foreach (string source in Directory
                     .EnumerateFiles(repositoryRoot, "*.cs", SearchOption.TopDirectoryOnly)
                     .Order(StringComparer.Ordinal))
        {
            files.Add((source, Path.GetRelativePath(repositoryRoot, source)));
        }

        string tests = Path.Combine(
            repositoryRoot,
            "tests",
            "ShippingDocumentWorker.Tests");
        foreach (string source in Directory
                     .EnumerateFiles(tests, "*.cs", SearchOption.TopDirectoryOnly)
                     .Order(StringComparer.Ordinal))
        {
            files.Add((source, Path.GetRelativePath(repositoryRoot, source)));
        }

        return files
            .OrderBy(item => item.Relative, StringComparer.Ordinal)
            .ToArray();
    }

    internal static void WriteParameters(string path)
    {
        var mappings = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["environmentName"] = "AZURE_ENV_NAME",
            ["functionAppName"] = "AZURE_DOCUMENT_FUNCTION_NAME",
            ["functionLocation"] = "AZURE_FUNCTION_LOCATION",
            ["appServicePlanId"] = "AZURE_DOCUMENT_PLAN_ID",
            ["applicationInsightsConnectionString"] =
                "AZURE_APPLICATION_INSIGHTS_CONNECTION_STRING",
            ["storageAccountName"] = "AZURE_STORAGE_ACCOUNT_NAME",
            ["serviceBusNamespace"] = "AZURE_SERVICE_BUS_NAMESPACE_FQDN",
            ["queueName"] = "AZURE_SHIPMENT_QUEUE",
            ["userAssignedIdentityId"] =
                "AZURE_USER_ASSIGNED_IDENTITY_ID",
            ["userAssignedIdentityClientId"] =
                "AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID",
            ["registryImage"] = "REGISTRY_IMAGE",
            ["registryUsername"] = "AZURE_ACR_TOKEN_NAME",
            ["registryPassword"] = "REGISTRY_PASSWORD",
        };
        var parameters = mappings.ToDictionary(
            entry => entry.Key,
            entry => new ParameterValue(RequiredEnvironmentValue(entry.Value)),
            StringComparer.Ordinal);
        var file = new ParameterFile(
            "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
            "1.0.0.0",
            parameters);
        File.WriteAllText(
            path,
            JsonSerializer.Serialize(file, JsonOptions) + Environment.NewLine,
            new UTF8Encoding(false));
    }

    private static string RequiredEnvironmentValue(string name)
    {
        string? value = Environment.GetEnvironmentVariable(name);
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOperationException(
                $"Required environment value '{name}' is missing.");
        }
        return value;
    }

    private static void CopyFile(string source, string destination)
    {
        if (!File.Exists(source))
        {
            throw new FileNotFoundException(
                $"Required file is missing: {source}",
                source);
        }
        Directory.CreateDirectory(
            Path.GetDirectoryName(destination) ??
            throw new InvalidOperationException("Destination has no parent."));
        File.Copy(source, destination, overwrite: false);
    }

    private static void Append(IncrementalHash digest, string value) =>
        digest.AppendData(Encoding.UTF8.GetBytes(value));

    private sealed record ParameterFile(
        [property: JsonPropertyName("$schema")] string Schema,
        string ContentVersion,
        IReadOnlyDictionary<string, ParameterValue> Parameters);

    private sealed record ParameterValue(string Value);
}
