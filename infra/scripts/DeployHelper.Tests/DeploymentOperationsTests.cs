using System.Text.Json;
using DeployHelper;

namespace DeployHelper.Tests;

public sealed class DeploymentOperationsTests
{
    [Fact]
    public void SourceHashChangesWhenSourceChanges()
    {
        using var repository = TestDirectory.Create();
        SeedRepository(repository.Path);
        string first = DeploymentOperations.HashBuildInputs(repository.Path);

        File.AppendAllText(
            Path.Combine(repository.Path, "ProcessShipment.cs"),
            Environment.NewLine);
        string second = DeploymentOperations.HashBuildInputs(repository.Path);

        Assert.Matches("^[0-9a-f]{64}$", first);
        Assert.NotEqual(first, second);
    }

    [Fact]
    public void StagesOnlyRuntimeInputsAndPublishedOutput()
    {
        using var repository = TestDirectory.Create();
        using var publish = TestDirectory.Create();
        using var destination = TestDirectory.Create();
        SeedRepository(repository.Path);
        Directory.CreateDirectory(Path.Combine(publish.Path, "app"));
        Directory.CreateDirectory(Path.Combine(publish.Path, "rendercheck"));
        File.WriteAllText(
            Path.Combine(publish.Path, "app", "ShippingDocumentWorker.dll"),
            "app");
        File.WriteAllText(
            Path.Combine(publish.Path, "rendercheck", "RenderCheck.dll"),
            "check");

        string hash = DeploymentOperations.PrepareImageContext(
            repository.Path,
            destination.Path,
            publish.Path);

        Assert.Matches("^[0-9a-f]{64}$", hash);
        Assert.True(File.Exists(
            Path.Combine(destination.Path, "dotnet10.Dockerfile")));
        Assert.True(File.Exists(
            Path.Combine(
                destination.Path,
                "publish",
                "app",
                "ShippingDocumentWorker.dll")));
        Assert.False(File.Exists(
            Path.Combine(destination.Path, "ProcessShipment.cs")));
    }

    [Fact]
    public void WritesArmParametersWithoutLoggingSecrets()
    {
        using var output = TestDirectory.Create();
        var values = new Dictionary<string, string>
        {
            ["AZURE_ENV_NAME"] = "demo",
            ["AZURE_DOCUMENT_FUNCTION_NAME"] = "func-demo",
            ["AZURE_FUNCTION_LOCATION"] = "eastus2euap",
            ["AZURE_DOCUMENT_PLAN_ID"] = "/subscriptions/test/plan",
            ["AZURE_APPLICATION_INSIGHTS_CONNECTION_STRING"] = "InstrumentationKey=test",
            ["AZURE_STORAGE_ACCOUNT_NAME"] = "stdemo",
            ["AZURE_SERVICE_BUS_NAMESPACE_FQDN"] = "demo.servicebus.windows.net",
            ["AZURE_SHIPMENT_QUEUE"] = "shipment-submissions",
            ["AZURE_USER_ASSIGNED_IDENTITY_ID"] = "/subscriptions/test/identity",
            ["AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID"] = "client",
            ["REGISTRY_IMAGE"] = "example.azurecr.io/image@sha256:test",
            ["AZURE_ACR_TOKEN_NAME"] = "pull-token",
            ["REGISTRY_PASSWORD"] = "secret-value",
        };
        try
        {
            foreach ((string key, string value) in values)
            {
                Environment.SetEnvironmentVariable(key, value);
            }
            string path = Path.Combine(output.Path, "parameters.json");

            DeploymentOperations.WriteParameters(path);

            using JsonDocument document = JsonDocument.Parse(
                File.ReadAllText(path));
            Assert.Equal(
                "secret-value",
                document.RootElement
                    .GetProperty("parameters")
                    .GetProperty("registryPassword")
                    .GetProperty("value")
                    .GetString());
        }
        finally
        {
            foreach (string key in values.Keys)
            {
                Environment.SetEnvironmentVariable(key, null);
            }
        }
    }

    private static void SeedRepository(string root)
    {
        foreach (string relative in new[]
        {
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
            "ProcessShipment.cs",
            Path.Combine(
                "tests",
                "ShippingDocumentWorker.Tests",
                "ShipmentParserTests.cs"),
        })
        {
            string path = Path.Combine(root, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(path) ?? root);
            File.WriteAllText(path, relative);
        }
    }

    private sealed class TestDirectory : IDisposable
    {
        private TestDirectory(string path)
        {
            Path = path;
        }

        public string Path { get; }

        public static TestDirectory Create()
        {
            string path = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(),
                $"shipping-doc-tests-{Guid.NewGuid():N}");
            Directory.CreateDirectory(path);
            return new TestDirectory(path);
        }

        public void Dispose()
        {
            if (Directory.Exists(Path))
            {
                Directory.Delete(Path, recursive: true);
            }
        }
    }
}
