using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace SonicTower
{
    // Reads Sonic Mania's Data.rsdk (the player's own, read only).
    sealed class Rsdk : IDisposable
    {
        struct Entry { public long Off; public int Size; public bool Enc; }
        readonly FileStream _fs;
        readonly Dictionary<string, Entry> _e = new Dictionary<string, Entry>();

        public Rsdk(string path)
        {
            _fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            var r = new BinaryReader(_fs);
            r.ReadBytes(6);
            int count = r.ReadUInt16();
            for (int i = 0; i < count; i++)
            {
                byte[] h = r.ReadBytes(16);
                uint off = r.ReadUInt32();
                uint size = r.ReadUInt32();
                _e[BitConverter.ToString(h)] = new Entry { Off = off, Size = (int)(size & 0x7FFFFFFF), Enc = (size & 0x80000000) != 0 };
            }
        }

        static byte[] Md5(string s) { using (var m = MD5.Create()) return m.ComputeHash(Encoding.ASCII.GetBytes(s)); }
        static byte[] Swap(byte[] d)
        {
            var o = new byte[16];
            for (int i = 0; i < 16; i += 4) for (int j = 0; j < 4; j++) o[i + j] = d[i + 3 - j];
            return o;
        }

        public byte[] Read(string name)
        {
            byte[] d = Md5(name.ToLowerInvariant());
            if (!_e.TryGetValue(BitConverter.ToString(d), out Entry e) && !_e.TryGetValue(BitConverter.ToString(Swap(d)), out e))
                return null;
            _fs.Seek(e.Off, SeekOrigin.Begin);
            var data = new byte[e.Size];
            int got = 0;
            while (got < e.Size) { int n = _fs.Read(data, got, e.Size - got); if (n <= 0) break; got += n; }
            if (!e.Enc) return data;
            byte[] a = Swap(Md5(name.ToUpperInvariant()));
            byte[] b = Swap(Md5(e.Size.ToString()));
            int no = (e.Size / 4) & 0x7F, pa = 0, pb = 8, sw = 0;
            for (int i = 0; i < e.Size; i++)
            {
                int c = data[i] ^ no ^ b[pb];
                if (sw != 0) c = ((c & 0xF) << 4) | (c >> 4);
                data[i] = (byte)(c ^ a[pa]);
                pa++; pb++;
                if (pa <= 15)
                {
                    if (pb > 12) { pb = 0; sw ^= 1; }
                }
                else if (pb <= 8)
                {
                    pa = 0; sw ^= 1;
                }
                else
                {
                    no = (no + 2) & 0x7F;
                    if (sw != 0) { sw = 0; pa = no % 7; pb = no % 12 + 2; }
                    else { sw = 1; pa = no % 12 + 3; pb = no % 7; }
                }
            }
            return data;
        }

        public void Dispose() { _fs.Dispose(); }
    }

    // A GIF's indexed pixels and palette: Mania's sheets use index 0 as see-through.
    sealed class Gif
    {
        public int W, H;
        public byte[] Pixels;
        public int[] Palette = new int[256];

        public static Gif Decode(byte[] d)
        {
            var g = new Gif();
            int p = 6;
            g.W = d[p] | d[p + 1] << 8;
            g.H = d[p + 2] | d[p + 3] << 8;
            byte flags = d[p + 4];
            p += 7;
            if ((flags & 0x80) != 0)
            {
                int n = 2 << (flags & 7);
                for (int i = 0; i < n; i++) { g.Palette[i] = 255 << 24 | d[p] << 16 | d[p + 1] << 8 | d[p + 2]; p += 3; }
            }
            while (d[p] != 0x2C)
            {
                if (d[p] == 0x21)
                {
                    p += 2;
                    while (d[p] != 0) p += d[p] + 1;
                    p++;
                }
                else throw new InvalidDataException("GIF block " + d[p]);
            }
            p += 9;
            byte lf = d[p++];
            if ((lf & 0x80) != 0)
            {
                int n = 2 << (lf & 7);
                for (int i = 0; i < n; i++) { g.Palette[i] = 255 << 24 | d[p] << 16 | d[p + 1] << 8 | d[p + 2]; p += 3; }
            }
            int min = d[p++];
            var data = new MemoryStream();
            while (d[p] != 0) { data.Write(d, p + 1, d[p]); p += d[p] + 1; }
            g.Pixels = Lzw(data.ToArray(), min, g.W * g.H);
            if ((lf & 0x40) != 0) g.Pixels = Deinterlace(g.Pixels, g.W, g.H);
            return g;
        }

        static byte[] Deinterlace(byte[] src, int w, int h)
        {
            var o = new byte[src.Length];
            int s = 0;
            int[] start = { 0, 4, 2, 1 }, step = { 8, 8, 4, 2 };
            for (int pass = 0; pass < 4; pass++)
                for (int y = start[pass]; y < h; y += step[pass]) { Array.Copy(src, s, o, y * w, w); s += w; }
            return o;
        }

        static byte[] Lzw(byte[] data, int min, int size)
        {
            var o = new byte[size];
            int clear = 1 << min, end = clear + 1, next = end + 1, bits = min + 1;
            var prefix = new int[4096]; var suffix = new byte[4096]; var stack = new byte[4097];
            int acc = 0, nbits = 0, op = 0, prev = -1, first = 0, ip = 0;
            for (int i = 0; i < clear; i++) suffix[i] = (byte)i;
            while (op < size)
            {
                while (nbits < bits)
                {
                    if (ip >= data.Length) return o;
                    acc |= data[ip++] << nbits; nbits += 8;
                }
                int code = acc & ((1 << bits) - 1);
                acc >>= bits; nbits -= bits;
                if (code == clear) { bits = min + 1; next = end + 1; prev = -1; continue; }
                if (code == end) break;
                if (prev == -1) { o[op++] = suffix[code]; prev = first = code; continue; }
                int sp = 0, cur = code;
                if (code >= next) { stack[sp++] = (byte)first; cur = prev; }
                while (cur >= clear) { stack[sp++] = suffix[cur]; cur = prefix[cur]; }
                first = suffix[cur];
                stack[sp++] = (byte)first;
                if (next < 4096)
                {
                    prefix[next] = prev; suffix[next] = (byte)first; next++;
                    if (next == (1 << bits) && bits < 12) bits++;
                }
                while (sp > 0 && op < size) o[op++] = stack[--sp];
                prev = code;
            }
            return o;
        }
    }

    sealed class Frame { public int Sheet, Dur, X, Y, W, H, Px, Py; }
    sealed class AnimDef { public string Name; public int Speed, Loop; public List<Frame> Frames = new List<Frame>(); }
    sealed class SpriteBin
    {
        public List<string> Sheets = new List<string>();
        public List<AnimDef> Anims = new List<AnimDef>();

        public static SpriteBin Parse(byte[] r)
        {
            var s = new SpriteBin();
            int p = 8;
            string Str() { int n = r[p++]; string v = Encoding.ASCII.GetString(r, p, n).TrimEnd('\0'); p += n; return v; }
            int sheets = r[p++];
            for (int i = 0; i < sheets; i++) s.Sheets.Add(Str());
            int boxes = r[p++];
            for (int i = 0; i < boxes; i++) Str();
            int anims = BitConverter.ToUInt16(r, p); p += 2;
            for (int i = 0; i < anims; i++)
            {
                var a = new AnimDef { Name = Str() };
                int fc = BitConverter.ToUInt16(r, p); a.Speed = BitConverter.ToInt16(r, p + 2); a.Loop = r[p + 4]; p += 6;
                for (int f = 0; f < fc; f++)
                {
                    a.Frames.Add(new Frame
                    {
                        Sheet = r[p], Dur = BitConverter.ToUInt16(r, p + 1),
                        X = BitConverter.ToUInt16(r, p + 5), Y = BitConverter.ToUInt16(r, p + 7),
                        W = BitConverter.ToUInt16(r, p + 9), H = BitConverter.ToUInt16(r, p + 11),
                        Px = BitConverter.ToInt16(r, p + 13), Py = BitConverter.ToInt16(r, p + 15),
                    });
                    p += 17 + 8 * boxes;
                }
                s.Anims.Add(a);
            }
            return s;
        }
    }

    static class Extract
    {
        const int Scale = 2;

        static string Safe(string s) => s.Replace(' ', '_').Replace("@", "").Replace('|', '_');

        // One horizontal strip per animation: frames padded to one cell, each frame's pivot at the cell's origin.
        static object WriteAnim(Rsdk rsdk, Dictionary<string, Gif> cache, AnimDef a, string dir, string outName)
        {
            int minX = 0, minY = 0, maxX = 0, maxY = 0;
            foreach (var f in a.Frames)
            {
                minX = Math.Min(minX, f.Px); minY = Math.Min(minY, f.Py);
                maxX = Math.Max(maxX, f.Px + f.W); maxY = Math.Max(maxY, f.Py + f.H);
            }
            int cw = (maxX - minX) * Scale, ch = (maxY - minY) * Scale;
            string file = Safe(outName) + ".png";
            using (var bmp = new Bitmap(Math.Max(1, cw * a.Frames.Count), Math.Max(1, ch), PixelFormat.Format32bppArgb))
            {
                var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                unsafe_blit(a, cache, minX, minY, cw, bd);
                bmp.UnlockBits(bd);
                bmp.Save(Path.Combine(dir, file), ImageFormat.Png);
            }
            return new Dictionary<string, object>
            {
                { "file", file }, { "frames", a.Frames.Count }, { "cx", -minX * Scale }, { "cy", -minY * Scale },
                { "speed", a.Speed }, { "loop", a.Loop }, { "dur", a.Frames.Select(f => f.Dur).ToArray() },
            };
        }

        static void unsafe_blit(AnimDef a, Dictionary<string, Gif> cache, int minX, int minY, int cw, BitmapData bd)
        {
            var row = new int[bd.Width];
            for (int y = 0; y < bd.Height; y++)
            {
                Array.Clear(row, 0, row.Length);
                for (int fi = 0; fi < a.Frames.Count; fi++)
                {
                    var f = a.Frames[fi];
                    Gif g = cache[f.Sheet + "|" + a.Name];
                    int sy = y / Scale + minY - f.Py;
                    if (sy < 0 || sy >= f.H) continue;
                    for (int x = 0; x < cw; x++)
                    {
                        int sx = x / Scale + minX - f.Px;
                        if (sx < 0 || sx >= f.W) continue;
                        int px = f.X + sx, py = f.Y + sy;
                        if (px >= g.W || py >= g.H) continue;
                        byte idx = g.Pixels[py * g.W + px];
                        if (idx != 0) row[fi * cw + x] = g.Palette[idx];
                    }
                }
                Marshal.Copy(row, 0, bd.Scan0 + y * bd.Stride, bd.Width);
            }
        }

        public static void All(string rsdkPath, string outDir)
        {
            var js = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
            string text;
            using (var st = typeof(Extract).Assembly.GetManifestResourceStream("assets.json"))
            using (var rd = new StreamReader(st)) text = rd.ReadToEnd();
            var manifest = js.Deserialize<Dictionary<string, object>>(text);
            string sprDir = Path.Combine(outDir, "spr"), sfxDir = Path.Combine(outDir, "sfx");
            Directory.CreateDirectory(sprDir);
            Directory.CreateDirectory(sfxDir);
            using (var rsdk = new Rsdk(rsdkPath))
            {
                var meta = new Dictionary<string, object>();
                byte[] bin = rsdk.Read("Data/Sprites/Players/Sonic.bin");
                if (bin == null) throw new InvalidDataException("Sonic's sprites were not found in Sonic Mania's Data.rsdk.");
                var def = SpriteBin.Parse(bin);
                var sheets = new Gif[def.Sheets.Count];
                for (int i = 0; i < sheets.Length; i++)
                    sheets[i] = Gif.Decode(rsdk.Read("Data/Sprites/" + def.Sheets[i]));
                var want = new HashSet<string>(((System.Collections.ArrayList)manifest["sprites"]).Cast<string>());
                foreach (var a in def.Anims)
                {
                    if (!want.Contains(a.Name) || a.Frames.Count == 0) continue;
                    var cache = new Dictionary<string, Gif>();
                    foreach (var f in a.Frames) cache[f.Sheet + "|" + a.Name] = sheets[f.Sheet];
                    meta[a.Name] = WriteAnim(rsdk, cache, a, sprDir, a.Name);
                }
                foreach (Dictionary<string, object> ex in (System.Collections.ArrayList)manifest["extra"])
                {
                    var d2 = SpriteBin.Parse(rsdk.Read((string)ex["bin"]));
                    var sh2 = d2.Sheets.Select(s => Gif.Decode(rsdk.Read("Data/Sprites/" + s))).ToArray();
                    var a2 = d2.Anims.FirstOrDefault(x => x.Name == (string)ex["anim"]) ?? d2.Anims[0];
                    var cache = new Dictionary<string, Gif>();
                    foreach (var f in a2.Frames) cache[f.Sheet + "|" + a2.Name] = sh2[f.Sheet];
                    meta[(string)ex["name"]] = WriteAnim(rsdk, cache, a2, sprDir, (string)ex["name"]);
                }
                foreach (Dictionary<string, object> c in (System.Collections.ArrayList)manifest["chars"])
                {
                    var d3 = SpriteBin.Parse(rsdk.Read((string)c["bin"]));
                    var sh3 = d3.Sheets.Select(s => Gif.Decode(rsdk.Read("Data/Sprites/" + s))).ToArray();
                    var want3 = new HashSet<string>(want);
                    foreach (string e in (System.Collections.ArrayList)c["extra"]) want3.Add(e);
                    foreach (var a3 in d3.Anims)
                    {
                        if (!want3.Contains(a3.Name) || a3.Frames.Count == 0) continue;
                        var cache = new Dictionary<string, Gif>();
                        foreach (var f in a3.Frames) cache[f.Sheet + "|" + a3.Name] = sh3[f.Sheet];
                        string key = (string)c["prefix"] + a3.Name;
                        meta[key] = WriteAnim(rsdk, cache, a3, sprDir, key);
                    }
                }
                File.WriteAllText(Path.Combine(outDir, "anims.json"), js.Serialize(meta));

                foreach (Dictionary<string, object> sf in (System.Collections.ArrayList)manifest["sfx"])
                {
                    byte[] wav = rsdk.Read((string)sf["file"]);
                    if (wav == null) continue;
                    WritePcm(wav, Path.Combine(sfxDir, ((string)sf["name"]).Replace('/', '_') + ".pcm"));
                }
            }
        }

        // RIFF to [rate u32][channels u32][16-bit samples]
        static void WritePcm(byte[] w, string path)
        {
            int p = 12, rate = 44100, ch = 1, bits = 16, dataOff = -1, dataLen = 0;
            while (p + 8 <= w.Length)
            {
                string id = Encoding.ASCII.GetString(w, p, 4);
                int len = BitConverter.ToInt32(w, p + 4);
                if (id == "fmt ") { ch = BitConverter.ToInt16(w, p + 10); rate = BitConverter.ToInt32(w, p + 12); bits = BitConverter.ToInt16(w, p + 22); }
                else if (id == "data") { dataOff = p + 8; dataLen = Math.Min(len, w.Length - dataOff); break; }
                p += 8 + len + (len & 1);
            }
            if (dataOff < 0) return;
            using (var o = new BinaryWriter(File.Create(path)))
            {
                o.Write(rate);
                o.Write(ch);
                if (bits == 16) o.Write(w, dataOff, dataLen);
                else for (int i = 0; i < dataLen; i++) o.Write((short)((w[dataOff + i] - 128) << 8));
            }
        }
    }

    static class Program
    {
        const string Version = "1.0.10";
        const string ProductFolder = "SonicTower";

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        static extern bool CreateSymbolicLink(string link, string target, int flags);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct STARTUPINFOEX
        {
            public int cb; public string lpReserved, lpDesktop, lpTitle;
            public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
            public short wShowWindow, cbReserved2;
            public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError, lpAttributeList;
        }
        [StructLayout(LayoutKind.Sequential)]
        struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool UpdateProcThreadAttribute(IntPtr list, int flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returned);
        [DllImport("kernel32.dll")]
        static extern void DeleteProcThreadAttributeList(IntPtr list);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CreateProcess(string app, StringBuilder command, IntPtr processAttributes, IntPtr threadAttributes, bool inherit, int flags, IntPtr environment, string directory, ref STARTUPINFOEX info, out PROCESS_INFORMATION process);
        [DllImport("kernel32.dll")]
        static extern bool CloseHandle(IntPtr handle);

        // The program started with Windows' prefer-System32 image load policy, or null if that didn't work.
        static Process StartPreferSystem32(string exe, string arguments, string directory)
        {
            const int ExtendedStartupInfoPresent = 0x80000;
            IntPtr attributeMitigationPolicy = (IntPtr)0x20007;
            const long PreferSystem32AlwaysOn = 1L << 60;
            IntPtr list = IntPtr.Zero, policy = IntPtr.Zero;
            bool listReady = false;
            try
            {
                IntPtr size = IntPtr.Zero;
                InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
                list = Marshal.AllocHGlobal(size);
                if (!InitializeProcThreadAttributeList(list, 1, 0, ref size)) return null;
                listReady = true;
                policy = Marshal.AllocHGlobal(8);
                Marshal.WriteInt64(policy, PreferSystem32AlwaysOn);
                if (!UpdateProcThreadAttribute(list, 0, attributeMitigationPolicy, policy, (IntPtr)8, IntPtr.Zero, IntPtr.Zero)) return null;
                var info = new STARTUPINFOEX { cb = Marshal.SizeOf(typeof(STARTUPINFOEX)), lpAttributeList = list };
                var command = new StringBuilder("\"" + exe + "\" " + arguments);
                PROCESS_INFORMATION started;
                if (!CreateProcess(exe, command, IntPtr.Zero, IntPtr.Zero, false, ExtendedStartupInfoPresent, IntPtr.Zero, directory, ref info, out started)) return null;
                try
                {
                    Process process = Process.GetProcessById(started.dwProcessId);
                    IntPtr keep = process.Handle; // held open so its exit code can be read once it has ended
                    return process;
                }
                finally { CloseHandle(started.hThread); CloseHandle(started.hProcess); }
            }
            catch (Exception e) { Log("prefer-System32 start: " + e.Message); return null; }
            finally
            {
                if (listReady) DeleteProcThreadAttributeList(list);
                if (list != IntPtr.Zero) Marshal.FreeHGlobal(list);
                if (policy != IntPtr.Zero) Marshal.FreeHGlobal(policy);
            }
        }

        static string _log;
        static void Log(string m)
        {
            try
            {
                using (var f = new FileStream(_log, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete))
                using (var w = new StreamWriter(f)) w.WriteLine(DateTime.Now.ToString("HH:mm:ss ") + m);
            }
            catch { }
        }

        static string Arg(string[] a, string name)
        {
            int i = Array.IndexOf(a, name);
            return i >= 0 && i + 1 < a.Length ? a[i + 1] : null;
        }

        static void Junction(string link, string target)
        {
            if (Directory.Exists(link))
            {
                try { if ((File.GetAttributes(link) & FileAttributes.ReparsePoint) != 0) Directory.Delete(link); else return; } catch { return; }
            }
            var psi = new ProcessStartInfo("cmd.exe", "/c mklink /J \"" + link + "\" \"" + target + "\"") { CreateNoWindow = true, UseShellExecute = false };
            using (var p = Process.Start(psi)) p.WaitForExit();
        }

        // Rebuild when either game or anything in the mod's patch folder changed
        static string Stamp(string a, string b, string patchDir)
        {
            var fa = new FileInfo(a); var fb = new FileInfo(b);
            string patch;
            using (var sha = System.Security.Cryptography.SHA256.Create())
            {
                var all = new MemoryStream();
                foreach (string f in Directory.GetFiles(patchDir, "*", SearchOption.AllDirectories).OrderBy(x => x, StringComparer.Ordinal))
                {
                    byte[] bytes = File.ReadAllBytes(f);
                    all.Write(bytes, 0, bytes.Length);
                }
                patch = BitConverter.ToString(sha.ComputeHash(all.ToArray())).Replace("-", "");
            }
            return string.Join("|", Version, fa.Length, fa.LastWriteTimeUtc.Ticks, fb.Length, fb.LastWriteTimeUtc.Ticks, patch);
        }

        // Without these the game still starts, with no Sonic: rebuild instead of trusting the stamp
        static bool AssetsPresent(string dir)
        {
            string spr = Path.Combine(dir, "spr"), sfx = Path.Combine(dir, "sfx");
            return File.Exists(Path.Combine(dir, "anims.json")) && Directory.Exists(spr) && Directory.Exists(sfx)
                && Directory.GetFiles(spr).Length > 0 && Directory.GetFiles(sfx).Length > 0;
        }

        static void Fail(string message)
        {
            Log("FAILED: " + message);
            MessageBox.Show(message + "\n\nDetails are in " + _log, "Sonic Tower", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }

        [STAThread]
        static int Main(string[] args)
        {
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string home = Path.Combine(local, ProductFolder);
            string gameDir = Path.Combine(home, "game");
            Directory.CreateDirectory(gameDir);
            _log = Path.Combine(home, "SonicTower.log");
            try { File.WriteAllText(_log, ""); } catch { }
            string pt = Arg(args, "--game");
            string mania = Arg(args, "--mania");
            bool buildOnly = args.Contains("--build-only");
            string here = AppDomain.CurrentDomain.BaseDirectory;
            Log($"Sonic Tower {Version} game={pt} mania={mania}");
            if (pt == null || mania == null) { Fail("Sonic Tower needs --game <Pizza Tower folder> and --mania <Sonic Mania folder>. Melty starts it with both."); return 2; }
            string dataWin = Path.Combine(pt, "data.win"), rsdk = Path.Combine(mania, "Data.rsdk"), exe = Path.Combine(pt, "PizzaTower.exe");
            if (!File.Exists(dataWin) || !File.Exists(exe)) { Fail("Pizza Tower's data.win or PizzaTower.exe was not found in " + pt); return 3; }
            if (!File.Exists(rsdk)) { Fail("Sonic Mania's Data.rsdk was not found in " + mania); return 4; }

            string outWin = Path.Combine(gameDir, "data.win"), stampFile = Path.Combine(home, "build.stamp");
            string stamp = Stamp(dataWin, rsdk, Path.Combine(here, "patch"));
            bool fresh = File.Exists(outWin) && File.Exists(stampFile) && File.ReadAllText(stampFile) == stamp && AssetsPresent(Path.Combine(gameDir, "sonic"));
            if (!fresh)
            {
                Form form = null;
                var ui = new Thread(() =>
                {
                    form = new Form { Text = "Sonic Tower", Width = 460, Height = 120, StartPosition = FormStartPosition.CenterScreen, FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false, ControlBox = false };
                    form.Controls.Add(new Label { Text = "Building Sonic Tower from your Pizza Tower and Sonic Mania.\nThis takes about a minute, once.", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter });
                    Application.Run(form);
                }) { IsBackground = true };
                ui.SetApartmentState(ApartmentState.STA);
                ui.Start();
                try
                {
                    Stopwatch sw = Stopwatch.StartNew();
                    string assets = Path.Combine(gameDir, "sonic");
                    if (Directory.Exists(assets)) Directory.Delete(assets, true);
                    Directory.CreateDirectory(assets);
                    Extract.All(rsdk, assets);
                    Log($"Mania assets extracted in {sw.ElapsedMilliseconds} ms");
                    string temp = outWin + ".new";
                    if (File.Exists(temp)) File.Delete(temp);
                    string cli = Path.Combine(here, "utmt", "UndertaleModCli.exe");
                    var psi = new ProcessStartInfo(cli, "load \"" + dataWin + "\" --scripts \"" + Path.Combine(here, "patch", "SonicTowerPatch.csx") + "\" --output \"" + temp + "\" -f")
                    {
                        WorkingDirectory = Path.Combine(here, "utmt"),
                        UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
                    };
                    int code;
                    string so, se;
                    using (var p = Process.Start(psi))
                    {
                        var errTask = p.StandardError.ReadToEndAsync();
                        so = p.StandardOutput.ReadToEnd();
                        se = errTask.Result;
                        p.WaitForExit();
                        code = p.ExitCode;
                    }
                    string filtered = string.Join("\n", so.Split('\n').Where(l => !l.StartsWith("[MESSAGE]: ") || l.Contains("Sonic Tower")));
                    Log("patch exit " + code + "\n" + filtered + "\n" + se);
                    if (code != 0 || !File.Exists(temp)) { Fail("Sonic Tower could not build its copy of Pizza Tower's data. This build of the game may not match."); return 5; }
                    if (File.Exists(outWin)) File.Delete(outWin);
                    File.Move(temp, outWin);
                    File.WriteAllText(stampFile, stamp);
                    Log($"built in {sw.ElapsedMilliseconds} ms");
                }
                catch (Exception e)
                {
                    Fail("Sonic Tower could not build: " + e.Message);
                    Log(e.ToString());
                    return 6;
                }
                finally
                {
                    try { form?.Invoke((Action)(() => form.Close())); } catch { }
                }
            }
            if (buildOnly) return 0;

            // Pizza Tower reads sound/ and lang/ beside its data file: the patched data sees the game's own folders.
            foreach (string sub in new[] { "sound", "lang" })
                if (Directory.Exists(Path.Combine(pt, sub))) Junction(Path.Combine(gameDir, sub), Path.Combine(pt, sub));
            Junction(Path.Combine(gameDir, "pizzatower"), pt);
            // GameMaker reads its frame-pacing settings from options.ini beside the data file: without them the game runs slower
            File.WriteAllText(Path.Combine(gameDir, "options.ini"), "[Windows]\r\nSleepMargin=10\r\nUsex64=True\r\n[Steamworks]\r\ndebug=Auto\r\n[gameframe_native]\r\n[fmod_gms]\r\n");

            // Test mode: Melty's file is handed to the game, its reports back to Melty's file.
            string testFile = Path.Combine(local, "Melty", "test", "sonic-tower-4.json");
            string testCopy = Path.Combine(gameDir, "sonic", "test.json");
            string checksOut = null;
            string[] saveDirs =
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "PizzaTower_GM2"),
                Path.Combine(local, "PizzaTower_GM2"),
                gameDir,
            };
            foreach (string d in saveDirs) { try { File.Delete(Path.Combine(d, "st_checks.txt")); File.Delete(Path.Combine(d, "st_checks_all.txt")); File.Delete(Path.Combine(d, "st_log.txt")); } catch { } }
            try
            {
                string found = File.Exists(testFile) ? testFile : Arg(args, "--test-file");
                if (found != null && File.Exists(found))
                {
                    string t = File.ReadAllText(found);
                    File.WriteAllText(testCopy, t);
                    var js = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(t);
                    if (js.TryGetValue("checks", out object c)) checksOut = c as string;
                    Log("test mode on: " + t);
                }
                else if (File.Exists(testCopy)) File.Delete(testCopy);
            }
            catch (Exception e) { Log("test file: " + e.Message); }

            Process game;
            try
            {
                Environment.SetEnvironmentVariable("SteamAppId", "2231450");
                Environment.SetEnvironmentVariable("SteamGameId", "2231450");
                string gameArgs = "-game \"" + outWin + "\"";
                // A ReShade dxgi.dll beside the game crashes it at start-up (in its window-resize handling, even with no
                // effects). Windows' prefer-System32 policy has this one process load the real system DLLs instead, so
                // nothing in the player's folder has to change.
                game = StartPreferSystem32(exe, gameArgs, pt);
                if (game == null)
                {
                    Log("prefer-System32 start failed, starting normally");
                    game = Process.Start(new ProcessStartInfo(exe, gameArgs) { WorkingDirectory = pt, UseShellExecute = false });
                }
                Log("started Pizza Tower pid " + game.Id);
            }
            catch (Exception e) { Fail("Pizza Tower could not start: " + e.Message); return 7; }

            long sent = 0;
            while (!game.WaitForExit(500))
            {
                if (checksOut == null) continue;
                sent = Relay(saveDirs, checksOut, sent);
            }
            if (checksOut != null) Relay(saveDirs, checksOut, sent);
            Log("Pizza Tower exited " + game.ExitCode);
            return 0;
        }

        static long Relay(string[] dirs, string target, long sent)
        {
            foreach (string d in dirs)
            {
                string src = Path.Combine(d, "st_checks.txt");
                if (!File.Exists(src)) continue;
                try
                {
                    using (var f = new FileStream(src, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                    {
                        if (f.Length <= sent) return sent;
                        f.Seek(sent, SeekOrigin.Begin);
                        var buf = new byte[f.Length - sent];
                        int n = f.Read(buf, 0, buf.Length);
                        Directory.CreateDirectory(Path.GetDirectoryName(target));
                        using (var o = new FileStream(target, FileMode.Append, FileAccess.Write, FileShare.ReadWrite)) o.Write(buf, 0, n);
                        return sent + n;
                    }
                }
                catch { }
            }
            return sent;
        }
    }
}
