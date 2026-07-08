using System.Text.RegularExpressions;

namespace CraftyCannon.Ocr;

public sealed record RedactionDetectorSettings
{
    public bool TextOcr { get; init; } = true;
    public bool Face { get; init; } = true;
    public bool Barcode { get; init; } = true;
    public bool Email { get; init; } = true;
    public bool PhoneNumber { get; init; } = true;
    public bool CreditCard { get; init; } = true;
    public bool Ipv4Address { get; init; } = true;
    public bool Ipv6Address { get; init; }
    public bool MacAddress { get; init; }
    public bool UrlOrDomain { get; init; } = true;
    public bool ApiKey { get; init; } = true;
    public bool AwsAccessKey { get; init; } = true;
    public bool GitHubToken { get; init; } = true;
    public bool OpenAiKey { get; init; } = true;
    public bool BearerToken { get; init; } = true;
    public bool Jwt { get; init; } = true;
    public bool PrivateKey { get; init; } = true;
    public bool SessionCookie { get; init; } = true;
    public bool PasswordField { get; init; } = true;
    public bool EnvironmentVariable { get; init; } = true;
    public bool FilePath { get; init; }
    public bool UsernameOrHostname { get; init; }
    public double MinimumConfidence { get; init; } = 0.20;
    public bool UseFastTextRecognition { get; init; }
    public bool AllowSensitiveTextPreviews { get; init; }

    public static RedactionDetectorSettings Default { get; } = new();

    public bool IsEnabled(RedactionDetectorType type) => type switch
    {
        RedactionDetectorType.TextOcr => TextOcr,
        RedactionDetectorType.Face => Face,
        RedactionDetectorType.Barcode => Barcode,
        RedactionDetectorType.Email => Email,
        RedactionDetectorType.PhoneNumber => PhoneNumber,
        RedactionDetectorType.CreditCard => CreditCard,
        RedactionDetectorType.Ipv4Address => Ipv4Address,
        RedactionDetectorType.Ipv6Address => Ipv6Address,
        RedactionDetectorType.MacAddress => MacAddress,
        RedactionDetectorType.UrlOrDomain => UrlOrDomain,
        RedactionDetectorType.ApiKey => ApiKey,
        RedactionDetectorType.AwsAccessKey => AwsAccessKey,
        RedactionDetectorType.GitHubToken => GitHubToken,
        RedactionDetectorType.OpenAiKey => OpenAiKey,
        RedactionDetectorType.BearerToken => BearerToken,
        RedactionDetectorType.Jwt => Jwt,
        RedactionDetectorType.PrivateKey => PrivateKey,
        RedactionDetectorType.SessionCookie => SessionCookie,
        RedactionDetectorType.PasswordField => PasswordField,
        RedactionDetectorType.EnvironmentVariable => EnvironmentVariable,
        RedactionDetectorType.FilePath => FilePath,
        RedactionDetectorType.UsernameOrHostname => UsernameOrHostname,
        _ => false
    };
}

public sealed record RegexRedactionMatch(
    RedactionDetectorType Type,
    int Index,
    int Length,
    string Text);

public sealed class SmartRedactionPatternClassifier
{
    private readonly IReadOnlyList<RegexRedactionRule> rules;

    public SmartRedactionPatternClassifier(IReadOnlyList<RegexRedactionRule>? rules = null)
    {
        this.rules = rules ?? DefaultRules;
    }

    public IReadOnlyList<RegexRedactionMatch> Matches(string text, RedactionDetectorSettings? settings = null)
    {
        settings ??= RedactionDetectorSettings.Default;
        if (!settings.TextOcr)
        {
            return [];
        }

        var enabledRules = rules.Where(rule => settings.IsEnabled(rule.Type)).ToArray();
        var found = new List<RegexRedactionMatch>();
        foreach (var rule in enabledRules)
        {
            found.AddRange(rule.Matches(text));
        }

        if (found.Count == 0)
        {
            var compacted = OcrCompacted(text);
            if (!string.Equals(compacted, text, StringComparison.Ordinal))
            {
                foreach (var rule in enabledRules)
                {
                    found.AddRange(rule.Matches(compacted));
                }
            }
        }

        return NonOverlapping(found);
    }

    public bool ContainsSensitiveText(string text, RedactionDetectorSettings? settings = null) =>
        Matches(text, settings).Count > 0;

    public static bool IsLikelyCreditCard(string value)
    {
        var digits = value.Where(char.IsDigit).Select(ch => ch - '0').ToArray();
        if (digits.Length is < 13 or > 19)
        {
            return false;
        }

        var sum = 0;
        var doubleDigit = false;
        for (var i = digits.Length - 1; i >= 0; i--)
        {
            var digit = digits[i];
            if (doubleDigit)
            {
                digit *= 2;
                if (digit > 9)
                {
                    digit -= 9;
                }
            }

            sum += digit;
            doubleDigit = !doubleDigit;
        }

        return sum % 10 == 0;
    }

    public static IReadOnlyList<RegexRedactionRule> DefaultRules { get; } =
    [
        new(RedactionDetectorType.PrivateKey, """-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----""", RegexOptions.IgnoreCase | RegexOptions.Singleline),
        new(RedactionDetectorType.BearerToken, """\bBearer\s+[A-Za-z0-9._~+/=-]{20,}\b"""),
        new(RedactionDetectorType.Jwt, """\beyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"""),
        new(RedactionDetectorType.AwsAccessKey, """\bAKIA[0-9A-Z]{16}\b"""),
        new(RedactionDetectorType.GitHubToken, """\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{30,255}\b"""),
        new(RedactionDetectorType.OpenAiKey, """\bsk-[A-Za-z0-9_-]{20,}\b"""),
        new(RedactionDetectorType.ApiKey, """\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|secret[_-]?key)\b\s*[:=]\s*["']?[A-Za-z0-9._~+/=-]{12,}["']?"""),
        new(RedactionDetectorType.SessionCookie, """\b(?:Set-Cookie:\s*)?(?:sessionid|session_id|sid|connect\.sid|JSESSIONID|PHPSESSID|csrftoken|xsrf-token|auth_token)\s*=\s*[^;\s]{8,}"""),
        new(RedactionDetectorType.PasswordField, """\b(?:password|passwd|pwd|secret|token|api[_-]?key|auth|credential)\b\s*[:=]\s*["']?[^"'\s]{4,}["']?"""),
        new(RedactionDetectorType.EnvironmentVariable, """\b[A-Z][A-Z0-9_]{2,}\s*=\s*["']?[^"'\s]{4,}["']?""", RegexOptions.None),
        new(RedactionDetectorType.Email, """[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"""),
        new(RedactionDetectorType.UrlOrDomain, """\b(?:(?:https?://|www\.)[^\s<>"']+|(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+(?:com|net|org|io|dev|app|cloud|co|us|edu|gov|local)\b[^\s<>"']*)"""),
        new(RedactionDetectorType.Ipv4Address, """\b(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}\b""", RegexOptions.None),
        new(RedactionDetectorType.Ipv6Address, """\b(?:(?:[A-F0-9]{1,4}:){7}[A-F0-9]{1,4}|(?:[A-F0-9]{1,4}:){1,7}:|:(?::[A-F0-9]{1,4}){1,7}|(?:[A-F0-9]{1,4}:){1,6}:[A-F0-9]{1,4})\b""", RegexOptions.IgnoreCase),
        new(RedactionDetectorType.MacAddress, """\b(?:[A-F0-9]{2}[:-]){5}[A-F0-9]{2}\b"""),
        new(RedactionDetectorType.PhoneNumber, """(?<!\w)(?:\+?1[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?)\d{3}[\s.-]?\d{4}(?!\w)""", RegexOptions.None),
        new(RedactionDetectorType.CreditCard, """\b(?:\d[ -]?){13,19}\b""", RegexOptions.None, IsLikelyCreditCard),
        new(RedactionDetectorType.FilePath, """(?:(?:/[A-Za-z0-9._ -]+){2,}|(?:[A-Z]:\\(?:[^\\/:*?"<>|\r\n]+\\?){2,}|~/(?:[^\s:]+/?){1,}))"""),
        new(RedactionDetectorType.UsernameOrHostname, """\b(?:user(?:name)?|host(?:name)?|login)\s*[:=]\s*[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?"""),
    ];

    private static string OcrCompacted(string text)
    {
        var compacted = Regex.Replace(text, """\s*([@._:/?&=#%+-])\s*""", "$1", RegexOptions.CultureInvariant);
        compacted = Regex.Replace(compacted, """\s{2,}""", " ", RegexOptions.CultureInvariant);
        return compacted.Trim();
    }

    private static IReadOnlyList<RegexRedactionMatch> NonOverlapping(IEnumerable<RegexRedactionMatch> matches)
    {
        var sorted = matches
            .OrderBy(match => match.Index)
            .ThenBy(match => DetectorPriority(match.Type))
            .ToArray();
        var accepted = new List<RegexRedactionMatch>();
        foreach (var match in sorted)
        {
            var overlaps = accepted.Any(candidate => RangesOverlap(candidate.Index, candidate.Length, match.Index, match.Length));
            if (!overlaps)
            {
                accepted.Add(match);
            }
        }

        return accepted.OrderBy(match => match.Index).ToArray();
    }

    private static bool RangesOverlap(int firstIndex, int firstLength, int secondIndex, int secondLength) =>
        Math.Max(firstIndex, secondIndex) < Math.Min(firstIndex + firstLength, secondIndex + secondLength);

    private static int DetectorPriority(RedactionDetectorType type) => type switch
    {
        RedactionDetectorType.PrivateKey => 0,
        RedactionDetectorType.BearerToken => 1,
        RedactionDetectorType.Jwt => 2,
        RedactionDetectorType.AwsAccessKey or RedactionDetectorType.GitHubToken or RedactionDetectorType.OpenAiKey => 3,
        RedactionDetectorType.ApiKey or RedactionDetectorType.SessionCookie or RedactionDetectorType.PasswordField or RedactionDetectorType.EnvironmentVariable => 4,
        _ => 10
    };
}

public sealed class RegexRedactionRule
{
    private readonly Regex regex;
    private readonly Func<string, bool>? validator;

    public RegexRedactionRule(
        RedactionDetectorType type,
        string pattern,
        RegexOptions options = RegexOptions.IgnoreCase,
        Func<string, bool>? validator = null,
        RedactionDetectorType? settingsType = null)
    {
        Type = settingsType ?? type;
        regex = new Regex(pattern, options | RegexOptions.CultureInvariant);
        this.validator = validator;
        OutputType = type;
    }

    public RedactionDetectorType Type { get; }
    public RedactionDetectorType OutputType { get; }

    public IEnumerable<RegexRedactionMatch> Matches(string text)
    {
        foreach (Match match in regex.Matches(text))
        {
            var raw = match.Value;
            if (validator is not null && !validator(raw))
            {
                continue;
            }

            yield return new RegexRedactionMatch(OutputType, match.Index, match.Length, raw);
        }
    }
}