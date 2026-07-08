using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using CraftyCannon.Core;

namespace CraftyCannon.Security;

public sealed class WindowsCredentialStore : ISecretStore
{
    private const int CredTypeGeneric = 1;
    private const int CredPersistLocalMachine = 2;
    private const int ErrorNotFound = 1168;

    public string? GetSecret(string service, string account)
    {
        var targetName = TargetName(service, account);
        if (!CredRead(targetName, CredTypeGeneric, 0, out var credentialPointer))
        {
            var error = Marshal.GetLastWin32Error();
            if (error == ErrorNotFound)
            {
                return null;
            }

            throw new Win32Exception(error);
        }

        try
        {
            var credential = Marshal.PtrToStructure<Credential>(credentialPointer);
            if (credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize == 0)
            {
                return string.Empty;
            }

            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            return Encoding.Unicode.GetString(bytes).TrimEnd('\0');
        }
        finally
        {
            CredFree(credentialPointer);
        }
    }

    public void SetSecret(string service, string account, string secret)
    {
        ArgumentNullException.ThrowIfNull(secret);

        var bytes = Encoding.Unicode.GetBytes(secret);
        var blob = Marshal.AllocCoTaskMem(bytes.Length);
        Marshal.Copy(bytes, 0, blob, bytes.Length);

        var credential = new Credential
        {
            Type = CredTypeGeneric,
            TargetName = TargetName(service, account),
            CredentialBlobSize = bytes.Length,
            CredentialBlob = blob,
            Persist = CredPersistLocalMachine,
            UserName = account
        };

        try
        {
            if (!CredWrite(ref credential, 0))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }
        finally
        {
            var zeros = new byte[bytes.Length];
            Marshal.Copy(zeros, 0, blob, zeros.Length);
            Marshal.FreeCoTaskMem(blob);
        }
    }

    public void DeleteSecret(string service, string account)
    {
        if (CredDelete(TargetName(service, account), CredTypeGeneric, 0))
        {
            return;
        }

        var error = Marshal.GetLastWin32Error();
        if (error != ErrorNotFound)
        {
            throw new Win32Exception(error);
        }
    }

    private static string TargetName(string service, string account)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(service);
        ArgumentException.ThrowIfNullOrWhiteSpace(account);
        return $"CraftyCannon/{service}/{account}";
    }

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPointer);

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite(ref Credential credential, int flags);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, int type, int flags);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern void CredFree(IntPtr buffer);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public int Flags;
        public int Type;
        public string TargetName;
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string? UserName;
    }
}
