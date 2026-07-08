using System.Security.Cryptography;
using System.Text;

namespace CraftyCannon.Core;

public sealed record HashDigest(string Md5, string Sha1, string Sha256)
{
    public string? MatchExpected(string expectedHash)
    {
        var expected = expectedHash.Trim().ToLowerInvariant();
        if (string.IsNullOrEmpty(expected))
        {
            return null;
        }

        if (expected == Md5.ToLowerInvariant())
        {
            return "Matches MD5";
        }

        if (expected == Sha1.ToLowerInvariant())
        {
            return "Matches SHA-1";
        }

        if (expected == Sha256.ToLowerInvariant())
        {
            return "Matches SHA-256";
        }

        return "No match";
    }
}

public static class HashUtilities
{
    private const int BufferSize = 1024 * 1024;

    public static HashDigest ComputeText(string text) =>
        ComputeData(Encoding.UTF8.GetBytes(text));

    public static HashDigest ComputeData(ReadOnlySpan<byte> data)
    {
        using var md5 = IncrementalHash.CreateHash(HashAlgorithmName.MD5);
        using var sha1 = IncrementalHash.CreateHash(HashAlgorithmName.SHA1);
        using var sha256 = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        md5.AppendData(data);
        sha1.AppendData(data);
        sha256.AppendData(data);
        return new HashDigest(ToHex(md5.GetHashAndReset()), ToHex(sha1.GetHashAndReset()), ToHex(sha256.GetHashAndReset()));
    }

    public static async Task<HashDigest> ComputeFileAsync(string filePath, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        await using var stream = File.OpenRead(filePath);
        using var md5 = IncrementalHash.CreateHash(HashAlgorithmName.MD5);
        using var sha1 = IncrementalHash.CreateHash(HashAlgorithmName.SHA1);
        using var sha256 = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var buffer = new byte[BufferSize];
        while (true)
        {
            var read = await stream.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                break;
            }

            var chunk = buffer.AsSpan(0, read);
            md5.AppendData(chunk);
            sha1.AppendData(chunk);
            sha256.AppendData(chunk);
        }

        return new HashDigest(ToHex(md5.GetHashAndReset()), ToHex(sha1.GetHashAndReset()), ToHex(sha256.GetHashAndReset()));
    }

    private static string ToHex(byte[] bytes) => Convert.ToHexString(bytes).ToLowerInvariant();
}