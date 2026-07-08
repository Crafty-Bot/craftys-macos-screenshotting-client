using System.Text.Json;
using System.Text.Json.Serialization;

namespace CraftyCannon.Core;

public static class JsonOptions
{
    public static JsonSerializerOptions Default { get; } = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new UploadBackendJsonConverter(), new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };
}

public sealed class UploadBackendJsonConverter : JsonConverter<UploadBackend>
{
    public override UploadBackend Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType != JsonTokenType.String)
        {
            throw new JsonException("Upload backend must be a string.");
        }

        return reader.GetString() switch
        {
            "s3Compatible" => UploadBackend.S3Compatible,
            "ziplineV4" => UploadBackend.ZiplineV4,
            _ => UploadBackend.ZiplineV4
        };
    }

    public override void Write(Utf8JsonWriter writer, UploadBackend value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value switch
        {
            UploadBackend.S3Compatible => "s3Compatible",
            _ => "ziplineV4"
        });
}
