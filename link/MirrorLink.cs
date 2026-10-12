// MirrorLink: what Melty starts when you press Play (steps in sheets/link.json).
// - Takes the newest picture in your Pictures\Mirror Portraits folder (you, your dog, a screenshot from another
//   game) and writes it into the add-on as Portrait.tga, the only image format WoW add-ons can load.
// - Starts WoW Forever, and while it runs, picks up any newer picture you drop into the folder.
// - During a Melty test run, hands the run to the add-on and reports its checks to Melty.
// It never opens, reads or touches the WoW process (except closing it with a Melty test run).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Media;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;

static class MirrorLink
{
    const string Version = "1.0.4";
    const string Slug = "mirror-portraits"; // the mashup's slug on Melty (its test file is named after it)
    static readonly string[] PictureTypes = { ".png", ".jpg", ".jpeg", ".bmp", ".gif" };
    static string own, logPath, wow, pictures;
    static FlavorRow flavor;
    static List<string> genDirs = new List<string>();
    static bool picture;
    static string pictureName = "";
    static DateTime pictureTime = DateTime.MinValue;
    static Dictionary<string, object> test;

    static bool Testing { get { return test != null && test.ContainsKey("testId"); } }

    static void Log(string msg)
    {
        string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + msg;
        try { File.AppendAllText(logPath, line + Environment.NewLine); } catch { }
    }

    static string Arg(string[] args, string name, string env)
    {
        for (int i = 0; i + 1 < args.Length; i++) if (args[i] == name) return args[i + 1];
        string v = Environment.GetEnvironmentVariable(env);
        return string.IsNullOrEmpty(v) ? null : v.Replace('/', '\\');
    }

    static MediaRow Media(string id) { foreach (var m in LinkData.Media) if (m.id == id) return m; return null; }

    [STAThread]
    static int Main(string[] args)
    {
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        own = Path.Combine(local, "MirrorPortraits");
        Directory.CreateDirectory(own);
        logPath = Path.Combine(own, "link.log");
        try { if (File.Exists(logPath) && new FileInfo(logPath).Length > 512 * 1024) File.Delete(logPath); } catch { }

        wow = Arg(args, "--wow", "MP_WOW");
        Log("MirrorLink " + Version + "  wow=" + wow);
        if (wow == null || !Directory.Exists(wow)) { Log("World of Warcraft folder not found"); return 2; }
        flavor = LinkData.Flavors[0];
        string addon = Path.Combine(wow, flavor.folder + @"\Interface\AddOns\MirrorPortraits");
        if (!File.Exists(Path.Combine(addon, "MirrorPortraits.toc"))) { Log("Mirror Portraits is not installed in " + flavor.label); return 3; }
        genDirs.Add(Path.Combine(addon, "Generated"));
        foreach (string g in genDirs) Directory.CreateDirectory(g);
        pictures = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), Media("portrait").from);
        Directory.CreateDirectory(pictures);

        string testFile = Path.Combine(local, @"Melty\test\" + Slug + ".json");
        if (File.Exists(testFile))
        {
            try { test = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(testFile)); }
            catch (Exception e) { Log("test file unreadable: " + e.Message); }
        }

        // One MirrorLink per WoW session; a Melty test run always goes ahead (it starts its own fresh WoW).
        bool firstInstance;
        var mutex = new Mutex(true, "MirrorPortraits.Link", out firstInstance);
        if (!firstInstance && !Testing) { Log("already running; waiting for WoW Forever"); WaitWow(); return 0; }

        foreach (LinkRow s in LinkData.Steps)
        {
            try { Step(s); }
            catch (Exception e) { Log("step " + s.id + " failed: " + e.Message); }
        }
        GC.KeepAlive(mutex);
        return 0;
    }

    static void Step(LinkRow s)
    {
        switch (s.id)
        {
            case "write-picture":
            {
                string newest = NewestPicture(DateTime.MinValue);
                if (newest == null || !Convert(newest))
                {
                    MediaRow m = Media("portrait");
                    using (var b = new Bitmap(m.width, m.height, PixelFormat.Format32bppArgb)) WriteAll(b, m.file);
                    Log("no picture yet in " + pictures);
                }
                break;
            }
            case "write-info":
                WriteInfo();
                break;
            case "test-bridge":
            {
                string lua = "MirrorPortraits_Test = nil\n";
                if (Testing)
                {
                    lua = string.Format("MirrorPortraits_Test = {{ testId = \"{0}\", run = {1}, runs = {2}, seed = {3} }}\n",
                        LuaEsc(System.Convert.ToString(test["testId"])), Num(test, "run"), Num(test, "runs"), Num(test, "seed"));
                    Log("Melty test run " + Num(test, "run") + "/" + Num(test, "runs") + " testId=" + test["testId"]);
                }
                foreach (string g in genDirs) WriteText(Path.Combine(g, "Test.lua"), lua);
                break;
            }
            case "show-folder":
                if (!picture && !Testing)
                {
                    OpenFolder();
                    Log("opened " + pictures + " for your first picture");
                }
                break;
            case "open-wow":
            {
                string exe = Path.Combine(wow, flavor.folder + "\\" + flavor.exe);
                // A Melty test run starts from a fresh WoW: one left open by the previous run is closed normally first,
                // so it loads this run's test file.
                if (Testing)
                    foreach (Process old in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(flavor.exe)))
                    {
                        // WoW logs out first (up to 20 s outside a rested area), so give it time.
                        try { old.CloseMainWindow(); if (!old.WaitForExit(90000)) Log("previous WoW did not close"); else Log("closed the previous run's WoW"); }
                        catch (Exception e) { Log("closing previous WoW: " + e.Message); }
                    }
                if (Process.GetProcessesByName(Path.GetFileNameWithoutExtension(flavor.exe)).Length > 0) { Log(flavor.label + " already running"); break; }
                if (!File.Exists(exe)) { Log(flavor.label + " not installed: " + exe); break; }
                // Through the Battle.net app when it's installed, so WoW signs in by itself: launching the version's
                // family code (WoWF for WoW Forever) makes Battle.net start it with -launcherlogin.
                string bnet = BattleNet();
                if (bnet != null)
                {
                    Process.Start(new ProcessStartInfo(bnet, "--exec=\"launch " + flavor.family + "\"") { UseShellExecute = false });
                    Log("asked Battle.net to start " + flavor.label + " (" + flavor.uid + ")");
                    if (WaitForStart(TimeSpan.FromSeconds(90))) break;
                    Log("Battle.net did not start it; starting " + flavor.exe + " directly");
                }
                Process wp = Process.Start(new ProcessStartInfo(exe) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(exe) });
                Log("started " + exe);
                // In a Melty test run, WoW closes when Melty ends the run (it closes MirrorLink), so every run starts fresh.
                if (Testing) TieToThisProcess(wp);
                break;
            }
            case "watch-pictures":
                new Thread(WatchPictures) { IsBackground = true, Name = "watch-pictures" }.Start();
                break;
            case "tray-icon":
            {
                var t = new Thread(TrayIcon) { IsBackground = true, Name = "tray-icon" };
                t.SetApartmentState(ApartmentState.STA);
                t.Start();
                break;
            }
            case "report":
                if (Testing && test.ContainsKey("checks"))
                    new Thread(() => Report(System.Convert.ToString(test["testId"]), Num(test, "run"), System.Convert.ToString(test["checks"]))) { IsBackground = true }.Start();
                break;
            case "wait-wow":
                WaitWow();
                // A Melty test run ends when Melty closes MirrorLink, never by itself.
                if (Testing) { Log("test run: staying open until Melty ends the run"); Thread.Sleep(Timeout.Infinite); }
                break;
        }
    }

    // An icon by the Windows clock while you play: click it to open the picture folder (WoW add-ons can't open folders).
    static System.Windows.Forms.NotifyIcon tray;
    static void TrayIcon()
    {
        try
        {
            tray = new System.Windows.Forms.NotifyIcon();
            tray.Icon = Icon.ExtractAssociatedIcon(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? SystemIcons.Application;
            tray.Text = "Mirror Portraits: click to add a picture";
            tray.MouseClick += (s, e) => OpenFolder();
            var menu = new System.Windows.Forms.ContextMenu();
            menu.MenuItems.Add("Open picture folder", (s, e) => OpenFolder());
            tray.ContextMenu = menu;
            tray.Visible = true;
            AppDomain.CurrentDomain.ProcessExit += (s, e) => { try { tray.Visible = false; tray.Dispose(); } catch { } };
            System.Windows.Forms.Application.Run();
        }
        catch (Exception e) { Log("tray icon: " + e.Message); }
    }

    static void OpenFolder()
    {
        try { Directory.CreateDirectory(pictures); Process.Start(new ProcessStartInfo("explorer.exe", "\"" + pictures + "\"") { UseShellExecute = true }); }
        catch (Exception e) { Log("open folder: " + e.Message); }
    }

    static string BattleNet()
    {
        var places = new List<string>();
        foreach (string key in new[] { @"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Battle.net",
                                       @"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Battle.net" })
        {
            try { string dir = System.Convert.ToString(Microsoft.Win32.Registry.GetValue(key, "InstallLocation", null)); if (!string.IsNullOrEmpty(dir)) places.Add(dir); } catch { }
        }
        places.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Battle.net"));
        places.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Battle.net"));
        foreach (string dir in places)
        {
            string exe = Path.Combine(dir, "Battle.net.exe");
            if (File.Exists(exe)) return exe;
        }
        return null;
    }

    static bool WaitForStart(TimeSpan max)
    {
        string name = Path.GetFileNameWithoutExtension(flavor.exe);
        DateTime until = DateTime.Now + max;
        while (DateTime.Now < until)
        {
            if (Process.GetProcessesByName(name).Length > 0) { Log(flavor.label + " started through Battle.net"); return true; }
            Thread.Sleep(1000);
        }
        return false;
    }

    static string NewestPicture(DateTime after)
    {
        string newest = null;
        DateTime t0 = after;
        foreach (string f in Directory.GetFiles(pictures))
        {
            if (Array.IndexOf(PictureTypes, Path.GetExtension(f).ToLowerInvariant()) < 0) continue;
            DateTime t = Added(f);
            if (t > t0) { t0 = t; newest = f; }
        }
        return newest;
    }

    // When a picture landed in the folder: a copied photo keeps its old modified date but gets a new creation date.
    static DateTime Added(string f)
    {
        DateTime w = File.GetLastWriteTimeUtc(f), c = File.GetCreationTimeUtc(f);
        return c > w ? c : w;
    }

    static bool Convert(string file)
    {
        try
        {
            Bitmap src;
            using (var ms = new MemoryStream(File.ReadAllBytes(file))) using (var tmp = new Bitmap(ms)) src = new Bitmap(tmp);
            MediaRow m = Media("portrait");
            using (src) using (var fit = Cover(src, m.width, m.height)) WriteAll(fit, m.file);
            picture = true;
            pictureName = Path.GetFileName(file);
            pictureTime = Added(file);
            Log("picture: " + file);
            return true;
        }
        catch (Exception e) { Log("could not read " + file + ": " + e.Message); return false; }
    }

    static void WatchPictures()
    {
        string pending = null; long pendingSize = -1;
        while (true)
        {
            Thread.Sleep(1500);
            try
            {
                string newest = NewestPicture(pictureTime);
                if (newest == null) continue;
                long size = new FileInfo(newest).Length;
                if (newest != pending || size != pendingSize) { pending = newest; pendingSize = size; continue; }
                pending = null;
                if (Convert(newest)) { WriteInfo(); SystemSounds.Asterisk.Play(); }
                else pictureTime = Added(newest);
            }
            catch (Exception e) { Log("picture watch: " + e.Message); }
        }
    }

    static void WaitWow()
    {
        string name = Path.GetFileNameWithoutExtension(flavor.exe);
        DateTime started = DateTime.Now;
        DateTime lastSeen = DateTime.Now;
        // WoW restarts itself sometimes (after logging in or patching), so it counts as closed only once it has
        // been gone for a while.
        while (true)
        {
            bool running = Process.GetProcessesByName(name).Length > 0;
            if (running) lastSeen = DateTime.Now;
            if (!running && DateTime.Now - lastSeen > TimeSpan.FromSeconds(45)) break;
            Thread.Sleep(2000);
        }
        Log(flavor.label + " closed (" + (int)(DateTime.Now - started).TotalSeconds + " s)");
    }

    static void WriteInfo()
    {
        string lua = string.Format(
            "-- Written by MirrorLink at {0:u}\nMirrorPortraits_Info = {{ link = \"{1}\", picture = {2}, file = \"{3}\", folder = \"{4}\" }}\n",
            DateTime.UtcNow, Version, picture ? "true" : "false", LuaEsc(pictureName), LuaEsc(pictures));
        foreach (string g in genDirs) WriteText(Path.Combine(g, "Info.lua"), lua);
    }

    // ---- Melty test runs: the add-on's check lines, from its SavedVariables, to Melty's checks file ----
    static void Report(string testId, string run, string checksPath)
    {
        DateTime until = DateTime.Now.AddMinutes(15);
        var idRx = new Regex("\\[\"testId\"\\]\\s*=\\s*\"([^\"]*)\"");
        var runRx = new Regex("\\[\"run\"\\]\\s*=\\s*(\\d+)");
        var lineRx = new Regex("\"((?:pass|fail) [a-z0-9-]+[^\"]*)\"");
        string acct = Path.Combine(wow, flavor.folder + @"\WTF\Account");
        while (DateTime.Now < until)
        {
            if (Directory.Exists(acct))
            {
                foreach (string sv in Directory.GetFiles(acct, "MirrorPortraits.lua", SearchOption.AllDirectories))
                {
                    string text = SafeRead(sv);
                    Match id = idRx.Match(text), r = runRx.Match(text);
                    if (!id.Success || id.Groups[1].Value != testId || !r.Success || r.Groups[1].Value != run) continue;
                    var lines = new List<string>();
                    foreach (Match m in lineRx.Matches(text)) lines.Add(m.Groups[1].Value.Replace("\\\"", "\""));
                    if (lines.Count == 0) continue;
                    Directory.CreateDirectory(Path.GetDirectoryName(checksPath));
                    File.AppendAllText(checksPath, string.Join(Environment.NewLine, lines) + Environment.NewLine);
                    Log("reported to Melty: " + string.Join(" | ", lines));
                    return;
                }
            }
            Thread.Sleep(2000);
        }
        Log("no test result from the add-on within 15 minutes");
    }

    // ---- helpers ----
    static string SafeRead(string p) { try { return File.ReadAllText(p); } catch { return ""; } }
    static string LuaEsc(string s) { return s.Replace("\\", "\\\\").Replace("\"", "\\\""); }
    static string Num(Dictionary<string, object> d, string k)
    {
        object v;
        if (!d.TryGetValue(k, out v) || v == null) return "0";
        long n;
        return long.TryParse(System.Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture), out n) ? n.ToString() : "0";
    }
    static void WriteText(string path, string text)
    {
        try { File.WriteAllText(path, text, new UTF8Encoding(false)); }
        catch (Exception e) { Log("could not write " + path + ": " + e.Message); }
    }
    static void WriteAll(Bitmap b, string file) { foreach (string g in genDirs) WriteTga(b, Path.Combine(g, file)); }

    // Scale to fill (w x h), cutting the overflow evenly.
    static Bitmap Cover(Bitmap src, int w, int h)
    {
        var dst = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        double s = Math.Max((double)w / src.Width, (double)h / src.Height);
        int dw = (int)Math.Ceiling(src.Width * s), dh = (int)Math.Ceiling(src.Height * s);
        using (var g = Graphics.FromImage(dst))
        {
            g.Clear(Color.Transparent);
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.DrawImage(src, new Rectangle((w - dw) / 2, (h - dh) / 2, dw, dh));
        }
        return dst;
    }

    // Uncompressed 32-bit TGA, bottom-left origin. Written beside, then swapped in, so WoW never reads half a file.
    static void WriteTga(Bitmap bmp, string path)
    {
        int w = bmp.Width, h = bmp.Height;
        var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        byte[] px = new byte[w * h * 4];
        try { for (int y = 0; y < h; y++) Marshal.Copy(data.Scan0 + y * data.Stride, px, (h - 1 - y) * w * 4, w * 4); }
        finally { bmp.UnlockBits(data); }
        byte[] head = new byte[18];
        head[2] = 2;
        head[12] = (byte)(w & 255); head[13] = (byte)(w >> 8);
        head[14] = (byte)(h & 255); head[15] = (byte)(h >> 8);
        head[16] = 32; head[17] = 8;
        string tmp = path + ".tmp";
        using (var fs = File.Create(tmp)) { fs.Write(head, 0, 18); fs.Write(px, 0, px.Length); }
        for (int i = 0; ; i++)
        {
            try { if (File.Exists(path)) File.Delete(path); File.Move(tmp, path); return; }
            catch (IOException) { if (i > 20) throw; Thread.Sleep(100); }
        }
    }

    static IntPtr job;
    static void TieToThisProcess(Process p)
    {
        try
        {
            job = CreateJobObject(IntPtr.Zero, null);
            var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            info.BasicLimitInformation.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            int len = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
            IntPtr ptr = Marshal.AllocHGlobal(len);
            Marshal.StructureToPtr(info, ptr, false);
            SetInformationJobObject(job, 9, ptr, (uint)len);
            Marshal.FreeHGlobal(ptr);
            if (!AssignProcessToJobObject(job, p.Handle)) Log("could not tie WoW to the test run");
        }
        catch (Exception e) { Log("job: " + e.Message); }
    }
    [StructLayout(LayoutKind.Sequential)] struct JOBOBJECT_BASIC_LIMIT_INFORMATION { public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags; public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass, SchedulingClass; }
    [StructLayout(LayoutKind.Sequential)] struct IO_COUNTERS { public ulong a, b, c, d, e, f; }
    [StructLayout(LayoutKind.Sequential)] struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION { public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation; public IO_COUNTERS IoInfo; public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr a, string name);
    [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int cls, IntPtr info, uint len);
    [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
}
