namespace CraftyCannon.Ocr;

public enum RedactionDetectorType
{
    TextOcr,
    Face,
    Barcode,
    Email,
    PhoneNumber,
    CreditCard,
    Ipv4Address,
    Ipv6Address,
    MacAddress,
    UrlOrDomain,
    ApiKey,
    AwsAccessKey,
    GitHubToken,
    OpenAiKey,
    BearerToken,
    Jwt,
    PrivateKey,
    SessionCookie,
    PasswordField,
    EnvironmentVariable,
    FilePath,
    UsernameOrHostname
}

public sealed record RedactionFinding(
    RedactionDetectorType Type,
    double Confidence,
    double X,
    double Y,
    double Width,
    double Height,
    string Preview);

public interface ISmartRedactionDetector
{
    Task<IReadOnlyList<RedactionFinding>> DetectAsync(string imagePath, CancellationToken cancellationToken);
}
