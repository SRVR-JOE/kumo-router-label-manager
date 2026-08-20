// Helix launcher — wraps the PowerShell WinForms GUI in a single double-clickable
// exe so it can sit alongside the other standalone tools in D3 Apps.
//
// Helix-Label-Manager.ps1 is embedded as a resource. At startup it is unpacked to
// a stable per-user directory (not %TEMP%) so that the error-log.txt the script
// writes next to itself stays in one findable place across runs.

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Windows.Forms;

internal static class HelixLauncher
{
    private const string ResourceName = "Helix-Label-Manager.ps1";
    private const string ProductVersion = "5.2.0";

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            string appDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Helix",
                ProductVersion);
            Directory.CreateDirectory(appDir);

            string scriptPath = Path.Combine(appDir, ResourceName);
            byte[] payload = ReadEmbeddedScript();
            WriteIfChanged(scriptPath, payload);

            string powershell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(powershell))
            {
                Fail("Windows PowerShell 5.1 was not found at:\n" + powershell +
                     "\n\nHelix needs Windows PowerShell to run.");
                return 2;
            }

            var psi = new ProcessStartInfo
            {
                FileName = powershell,
                Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + scriptPath + "\"",
                WorkingDirectory = appDir,
                UseShellExecute = false,
                CreateNoWindow = true,
            };

            using (Process child = Process.Start(psi))
            {
                child.WaitForExit();
                if (child.ExitCode != 0)
                {
                    Fail("Helix exited with code " + child.ExitCode + ".\n\n" +
                         TailOfLog(Path.Combine(appDir, "error-log.txt")));
                }
                return child.ExitCode;
            }
        }
        catch (Exception ex)
        {
            Fail("Helix could not start.\n\n" + ex.Message);
            return 1;
        }
    }

    private static byte[] ReadEmbeddedScript()
    {
        Assembly self = Assembly.GetExecutingAssembly();
        using (Stream stream = self.GetManifestResourceStream(ResourceName))
        {
            if (stream == null)
                throw new InvalidOperationException(
                    "The embedded resource '" + ResourceName + "' is missing from this build.");
            var buffer = new byte[stream.Length];
            int read = 0;
            while (read < buffer.Length)
            {
                int n = stream.Read(buffer, read, buffer.Length - read);
                if (n == 0) break;
                read += n;
            }
            return buffer;
        }
    }

    // Rewrite only when the contents differ, so an upgrade replaces the script but
    // an ordinary launch does not churn the file the previous run may still hold.
    private static void WriteIfChanged(string path, byte[] payload)
    {
        if (File.Exists(path) && Hash(File.ReadAllBytes(path)) == Hash(payload))
            return;
        File.WriteAllBytes(path, payload);
    }

    private static string Hash(byte[] data)
    {
        using (var sha = SHA256.Create())
            return BitConverter.ToString(sha.ComputeHash(data));
    }

    private static string TailOfLog(string logPath)
    {
        try
        {
            if (!File.Exists(logPath)) return "No error log was written to:\n" + logPath;
            string[] lines = File.ReadAllLines(logPath);
            int start = Math.Max(0, lines.Length - 15);
            return "Last lines of " + logPath + ":\n\n" +
                   string.Join(Environment.NewLine, lines, start, lines.Length - start);
        }
        catch (Exception ex)
        {
            return "Could not read the error log: " + ex.Message;
        }
    }

    private static void Fail(string message)
    {
        MessageBox.Show(message, "Helix v" + ProductVersion,
            MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
}
