using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace MIEConvert
{
    /// <summary>In-memory tabular data: column names, optional type codes, string rows.</summary>
    public sealed class Table
    {
        public List<string> Columns = new List<string>();
        /// <summary>Type code per column (S, N, D, T). Only filled for export input.</summary>
        public List<char> Types = new List<char>();
        public List<string[]> Rows = new List<string[]>();

        public char TypeOf(int col)
        {
            return col < Types.Count ? Types[col] : 'S';
        }

        /// <summary>
        /// Pads every row to the column count, names empty headers ColumnN and makes duplicate
        /// names unique (Name, Name_2, ...), so the Clarion side can map columns by name.
        /// </summary>
        public void Normalize()
        {
            int n = Columns.Count;
            foreach (var r in Rows) if (r.Length > n) n = r.Length;
            while (Columns.Count < n) Columns.Add("");
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < Columns.Count; i++)
            {
                string c = (Columns[i] ?? "").Trim();
                if (c.Length == 0) c = "Column" + (i + 1).ToString(CultureInfo.InvariantCulture);
                string u = c;
                int k = 2;
                while (seen.Contains(u)) u = c + "_" + (k++).ToString(CultureInfo.InvariantCulture);
                seen.Add(u);
                Columns[i] = u;
            }
            for (int i = 0; i < Rows.Count; i++)
            {
                var r = Rows[i];
                if (r.Length != n)
                {
                    var nr = new string[n];
                    for (int j = 0; j < n; j++) nr[j] = j < r.Length ? (r[j] ?? "") : "";
                    Rows[i] = nr;
                }
                else for (int j = 0; j < n; j++) if (r[j] == null) r[j] = "";
            }
        }

        /// <summary>Builds a table from a list of raw rows (first row = header unless noHeader).</summary>
        public static Table FromRawRows(List<string[]> raw, bool noHeader, int maxRows)
        {
            var t = new Table();
            int start = 0;
            if (!noHeader && raw.Count > 0)
            {
                t.Columns.AddRange(raw[0]);
                start = 1;
            }
            for (int i = start; i < raw.Count; i++)
            {
                if (maxRows > 0 && t.Rows.Count >= maxRows) break;
                t.Rows.Add(raw[i]);
            }
            int n = t.Columns.Count;
            foreach (var r in t.Rows) if (r.Length > n) n = r.Length;
            if (noHeader)
                for (int i = 0; i < n; i++) t.Columns.Add("Column" + (i + 1).ToString(CultureInfo.InvariantCulture));
            return t;
        }
    }

    /// <summary>Reader / writer for the MIE-TSV intermediate file (see docs/DESIGN.md section 1).</summary>
    public static class MieTsv
    {
        public static string Escape(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            bool need = false;
            foreach (char c in s) if (c == '\\' || c == '\t' || c == '\n' || c == '\r') { need = true; break; }
            if (!need) return s;
            var sb = new StringBuilder(s.Length + 8);
            foreach (char c in s)
            {
                switch (c)
                {
                    case '\\': sb.Append("\\\\"); break;
                    case '\t': sb.Append("\\t"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    default: sb.Append(c); break;
                }
            }
            return sb.ToString();
        }

        public static string Unescape(string s)
        {
            if (s.IndexOf('\\') < 0) return s;
            var sb = new StringBuilder(s.Length);
            for (int i = 0; i < s.Length; i++)
            {
                char c = s[i];
                if (c == '\\' && i + 1 < s.Length)
                {
                    char n = s[i + 1];
                    switch (n)
                    {
                        case '\\': sb.Append('\\'); i++; continue;
                        case 't': sb.Append('\t'); i++; continue;
                        case 'n': sb.Append('\n'); i++; continue;
                        case 'r': sb.Append('\r'); i++; continue;
                    }
                }
                sb.Append(c);
            }
            return sb.ToString();
        }

        static string[] SplitLine(string line)
        {
            string[] parts = line.Split('\t');
            for (int i = 0; i < parts.Length; i++) parts[i] = Unescape(parts[i]);
            return parts;
        }

        /// <summary>Writes an import result: line 1 column names, then data rows (no type line).</summary>
        public static void WriteImport(string path, Table t, Encoding enc)
        {
            using (var w = new StreamWriter(path, false, enc, 1 << 16))
            {
                w.NewLine = "\r\n";
                WriteLine(w, t.Columns);
                foreach (var r in t.Rows) WriteLine(w, r);
            }
        }

        static void WriteLine(TextWriter w, IList<string> fields)
        {
            for (int i = 0; i < fields.Count; i++)
            {
                if (i > 0) w.Write('\t');
                w.Write(Escape(fields[i]));
            }
            w.Write("\r\n");
        }

        /// <summary>Reads an export file: line 1 names, line 2 type codes, then data rows.</summary>
        public static Table ReadExport(string path, Encoding enc)
        {
            var t = new Table();
            using (var r = new StreamReader(path, enc, false, 1 << 16))
            {
                string line = r.ReadLine();
                if (line == null) throw new MieException("The intermediate file is empty: " + path);
                t.Columns.AddRange(SplitLine(line));
                line = r.ReadLine();
                if (line != null)
                {
                    foreach (string code in line.Split('\t'))
                    {
                        string c = code.Trim().ToUpperInvariant();
                        t.Types.Add(c.Length > 0 && (c[0] == 'N' || c[0] == 'D' || c[0] == 'T') ? c[0] : 'S');
                    }
                }
                while (t.Types.Count < t.Columns.Count) t.Types.Add('S');
                int n = t.Columns.Count;
                while ((line = r.ReadLine()) != null)
                {
                    string[] f = SplitLine(line);
                    if (f.Length != n)
                    {
                        var nf = new string[n];
                        for (int i = 0; i < n; i++) nf[i] = i < f.Length ? f[i] : "";
                        f = nf;
                    }
                    t.Rows.Add(f);
                }
            }
            return t;
        }
    }

    public static class TextEnc
    {
        public static Encoding FromCodePage(int cp)
        {
            try { return Encoding.GetEncoding(cp); }
            catch (Exception) { throw new MieException("Unknown code page " + cp); }
        }

        /// <summary>Encoding for text output: utf8 | utf8bom (default) | ansi | codepage.</summary>
        public static Encoding ForOutput(string spec)
        {
            string s = (spec ?? "").Trim().ToLowerInvariant();
            switch (s)
            {
                case "": case "auto": case "utf8bom": case "utf-8-bom": return new UTF8Encoding(true);
                case "utf8": case "utf-8": return new UTF8Encoding(false);
                case "ansi": case "default": return Encoding.Default;
                case "unicode": case "utf16": case "utf-16": return new UnicodeEncoding(false, true);
            }
            int cp;
            if (int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out cp))
            {
                if (cp == 65001) return new UTF8Encoding(false);
                return FromCodePage(cp);
            }
            throw new MieException("Unknown encoding '" + spec + "'. Use utf8, utf8bom, ansi or a code page number.");
        }

        public static bool IsUnicode(Encoding e)
        {
            return e is UTF8Encoding || e is UnicodeEncoding || e is UTF32Encoding || e.CodePage == 65001 || e.CodePage == 1200 || e.CodePage == 1201;
        }

        /// <summary>Decodes text input: auto (BOM, else strict UTF-8, else ANSI) | utf8 | ansi | codepage.</summary>
        public static string ReadText(string path, string spec)
        {
            byte[] b = File.ReadAllBytes(path);
            string s = (spec ?? "").Trim().ToLowerInvariant();
            if (s == "" || s == "auto")
            {
                if (b.Length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF)
                    return new UTF8Encoding(false).GetString(b, 3, b.Length - 3);
                if (b.Length >= 4 && b[0] == 0xFF && b[1] == 0xFE && b[2] == 0 && b[3] == 0)
                    return new UTF32Encoding(false, false).GetString(b, 4, b.Length - 4);
                if (b.Length >= 2 && b[0] == 0xFF && b[1] == 0xFE)
                    return new UnicodeEncoding(false, false).GetString(b, 2, b.Length - 2);
                if (b.Length >= 2 && b[0] == 0xFE && b[1] == 0xFF)
                    return new UnicodeEncoding(true, false).GetString(b, 2, b.Length - 2);
                try { return new UTF8Encoding(false, true).GetString(b); }
                catch (DecoderFallbackException) { return Encoding.Default.GetString(b); }
            }
            Encoding e;
            switch (s)
            {
                case "utf8": case "utf-8": case "utf8bom": e = new UTF8Encoding(false); break;
                case "ansi": case "default": e = Encoding.Default; break;
                case "unicode": case "utf16": case "utf-16": e = new UnicodeEncoding(false, false); break;
                default:
                    int cp;
                    if (!int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out cp))
                        throw new MieException("Unknown encoding '" + spec + "'. Use auto, utf8, ansi or a code page number.");
                    e = FromCodePage(cp);
                    break;
            }
            int skip = 0;
            byte[] pre = e.GetPreamble();
            if (pre.Length > 0 && b.Length >= pre.Length)
            {
                bool match = true;
                for (int i = 0; i < pre.Length; i++) if (b[i] != pre[i]) { match = false; break; }
                if (match) skip = pre.Length;
            }
            else if (e.CodePage == 65001 && b.Length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) skip = 3;
            return e.GetString(b, skip, b.Length - skip);
        }
    }

    /// <summary>Number, date and time conversions shared by all formats.</summary>
    public static class Values
    {
        static readonly CultureInfo Inv = CultureInfo.InvariantCulture;
        static readonly DateTime OaBase = new DateTime(1899, 12, 30);

        /// <summary>Formats a double with invariant culture: 12.5 -> "12.5", 3 -> "3", no exponent where avoidable.</summary>
        public static string FormatNumber(double d)
        {
            if (double.IsNaN(d) || double.IsInfinity(d)) return "";
            if (d == 0) return "0";
            string r = d.ToString("R", Inv);
            if (r.IndexOf('E') >= 0)
            {
                double a = Math.Abs(d);
                if (a < 7.9e27 && a >= 1e-28)
                {
                    try { return ((decimal)d).ToString(Inv); } catch (OverflowException) { }
                }
            }
            return r;
        }

        /// <summary>Parses a number written by Clarion ("12.50", "-.5", " 3 ").</summary>
        public static bool TryParseNumber(string s, out double d)
        {
            s = (s ?? "").Trim();
            if (s.Length == 0) { d = 0; return false; }
            return double.TryParse(s, NumberStyles.Float, Inv, out d) && !double.IsNaN(d) && !double.IsInfinity(d);
        }

        /// <summary>Normalises a numeric text for JSON (keeps scale: "12.50" stays "12.50").</summary>
        public static string NormalizeNumberText(string s)
        {
            s = (s ?? "").Trim();
            decimal m;
            if (decimal.TryParse(s, NumberStyles.Float, Inv, out m)) return m.ToString(Inv);
            double d;
            if (TryParseNumber(s, out d)) return d.ToString("R", Inv);
            return null;
        }

        public static bool TryParseDate(string s, out DateTime dt)
        {
            s = (s ?? "").Trim();
            string[] fm = { "yyyy-MM-dd", "yyyy-M-d", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-ddTHH:mm:ss", "yyyy-MM-dd HH:mm" };
            return DateTime.TryParseExact(s, fm, Inv, DateTimeStyles.None, out dt);
        }

        public static bool TryParseTime(string s, out TimeSpan ts)
        {
            s = (s ?? "").Trim();
            ts = TimeSpan.Zero;
            if (s.Length == 0) return false;
            string[] p = s.Split(':');
            if (p.Length < 2 || p.Length > 3) return false;
            int h, m; double sec = 0;
            if (!int.TryParse(p[0], NumberStyles.Integer, Inv, out h)) return false;
            if (!int.TryParse(p[1], NumberStyles.Integer, Inv, out m)) return false;
            if (p.Length == 3 && !double.TryParse(p[2], NumberStyles.Float, Inv, out sec)) return false;
            if (h < 0 || m < 0 || m > 59 || sec < 0 || sec >= 60) return false;
            ts = TimeSpan.FromSeconds(h * 3600 + m * 60 + sec);
            return true;
        }

        public static double DateToSerial(DateTime dt)
        {
            return (dt - OaBase).TotalDays;
        }

        public static double TimeToSerial(TimeSpan ts)
        {
            return ts.TotalSeconds / 86400.0;
        }

        public enum DateKind { None, Date, Time, DateTime }

        /// <summary>Formats an Excel serial according to the kind of date format applied to the cell.</summary>
        public static string FormatSerial(double serial, DateKind kind, bool date1904)
        {
            if (date1904) serial += 1462;
            if (kind == DateKind.Time)
            {
                double frac = serial - Math.Floor(serial);
                long secs = (long)Math.Round(frac * 86400.0, MidpointRounding.AwayFromZero);
                if (secs >= 86400) secs = 0;
                return string.Format(Inv, "{0:00}:{1:00}:{2:00}", secs / 3600, (secs / 60) % 60, secs % 60);
            }
            if (serial < 0 || serial > 2958465) return FormatNumber(serial);
            long total = (long)Math.Round(serial * 86400.0, MidpointRounding.AwayFromZero);
            DateTime dt = OaBase.AddSeconds(total);
            if (kind == DateKind.Date) return dt.ToString("yyyy-MM-dd", Inv);
            return dt.ToString("yyyy-MM-dd HH:mm:ss", Inv);
        }

        /// <summary>Classifies an Excel number format as date, time, date+time or not a date.</summary>
        public static DateKind ClassifyFormat(int numFmtId, string code)
        {
            if (!string.IsNullOrEmpty(code)) return ClassifyCode(code);
            if (numFmtId >= 14 && numFmtId <= 17) return DateKind.Date;
            if (numFmtId == 22) return DateKind.DateTime;
            if ((numFmtId >= 18 && numFmtId <= 21) || (numFmtId >= 45 && numFmtId <= 47)) return DateKind.Time;
            return DateKind.None;
        }

        public static DateKind ClassifyBuiltin(int numFmtId)
        {
            return ClassifyFormat(numFmtId, null);
        }

        public static DateKind ClassifyCode(string code)
        {
            // first section only
            var sb = new StringBuilder();
            bool inQ = false;
            for (int i = 0; i < code.Length; i++)
            {
                char c = code[i];
                if (inQ) { if (c == '"') inQ = false; continue; }
                if (c == '"') { inQ = true; continue; }
                if (c == ';') break;
                if (c == '\\' || c == '_' || c == '*') { i++; continue; }
                if (c == '[')
                {
                    int e = code.IndexOf(']', i + 1);
                    if (e < 0) break;
                    string inner = code.Substring(i + 1, e - i - 1).ToLowerInvariant();
                    // elapsed time [h] [mm] [ss] counts as time
                    if (inner.Length > 0 && (inner.Trim('h').Length == 0 || inner.Trim('m').Length == 0 || inner.Trim('s').Length == 0))
                        sb.Append(inner[0] == 'm' ? 'n' : inner[0]);
                    i = e;
                    continue;
                }
                sb.Append(char.ToLowerInvariant(c));
            }
            string f = sb.ToString();
            if (f == "general" || f.Length == 0) return DateKind.None;
            bool d = f.IndexOf('d') >= 0 || f.IndexOf('y') >= 0;
            bool h = f.IndexOf('h') >= 0 || f.IndexOf('s') >= 0 || f.IndexOf('n') >= 0;
            bool m = f.IndexOf('m') >= 0;
            if (m && !h) d = true;
            if (d && h) return DateKind.DateTime;
            if (d) return DateKind.Date;
            if (h) return DateKind.Time;
            return DateKind.None;
        }

        /// <summary>Strips characters that are not allowed in XML 1.0 documents.</summary>
        public static string XmlSafe(string s)
        {
            if (string.IsNullOrEmpty(s)) return s ?? "";
            StringBuilder sb = null;
            for (int i = 0; i < s.Length; i++)
            {
                char c = s[i];
                bool ok;
                if (char.IsHighSurrogate(c) && i + 1 < s.Length && char.IsLowSurrogate(s[i + 1]))
                {
                    if (sb != null) { sb.Append(c).Append(s[i + 1]); }
                    i++;
                    continue;
                }
                ok = c == 0x9 || c == 0xA || c == 0xD || (c >= 0x20 && c <= 0xD7FF) || (c >= 0xE000 && c <= 0xFFFD);
                if (!ok)
                {
                    if (sb == null) { sb = new StringBuilder(s.Length); sb.Append(s, 0, i); }
                    continue;
                }
                if (sb != null) sb.Append(c);
            }
            return sb == null ? s : sb.ToString();
        }
    }
}
