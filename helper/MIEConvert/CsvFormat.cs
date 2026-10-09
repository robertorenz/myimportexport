using System.Collections.Generic;
using System.IO;
using System.Text;

namespace MIEConvert
{
    /// <summary>RFC 4180 CSV (and quoted TSV) reader / writer.</summary>
    public static class CsvFormat
    {
        public static Table Read(string path, Options o, char delim)
        {
            string text = TextEnc.ReadText(path, o.Encoding);
            int limit = o.MaxRows > 0 ? o.MaxRows + (o.NoHeader ? 0 : 1) : -1;
            List<string[]> raw = Parse(text, delim, limit);
            return Table.FromRawRows(raw, o.NoHeader, o.MaxRows);
        }

        /// <summary>Parses CSV text. Quoted fields may contain the delimiter, doubled quotes and line breaks.
        /// Completely empty lines are skipped.</summary>
        public static List<string[]> Parse(string text, char delim, int limit)
        {
            var rows = new List<string[]>();
            var fields = new List<string>();
            var sb = new StringBuilder();
            int i = 0, n = text.Length;
            bool fieldStarted = false;   // something on this line
            while (i < n)
            {
                if (limit > 0 && rows.Count >= limit) break;
                char c = text[i];
                if (c == '"' && sb.Length == 0)
                {
                    // quoted field
                    i++;
                    while (i < n)
                    {
                        char q = text[i];
                        if (q == '"')
                        {
                            if (i + 1 < n && text[i + 1] == '"') { sb.Append('"'); i += 2; continue; }
                            i++;
                            break;
                        }
                        sb.Append(q);
                        i++;
                    }
                    // anything after the closing quote up to the delimiter is appended verbatim (lenient)
                    while (i < n && text[i] != delim && text[i] != '\r' && text[i] != '\n') { sb.Append(text[i]); i++; }
                    fieldStarted = true;
                    continue;
                }
                if (c == delim)
                {
                    fields.Add(sb.ToString()); sb.Clear();
                    fieldStarted = true;
                    i++;
                    continue;
                }
                if (c == '\r' || c == '\n')
                {
                    if (c == '\r' && i + 1 < n && text[i + 1] == '\n') i++;
                    i++;
                    if (fieldStarted || sb.Length > 0)
                    {
                        fields.Add(sb.ToString()); sb.Clear();
                        rows.Add(fields.ToArray());
                    }
                    fields.Clear();
                    fieldStarted = false;
                    continue;
                }
                sb.Append(c);
                fieldStarted = true;
                i++;
            }
            if ((fieldStarted || sb.Length > 0) && !(limit > 0 && rows.Count >= limit))
            {
                fields.Add(sb.ToString());
                rows.Add(fields.ToArray());
            }
            return rows;
        }

        public static void Write(string path, Table t, Options o, char delim)
        {
            Encoding enc = TextEnc.ForOutput(o.Encoding);
            using (var w = new StreamWriter(path, false, enc, 1 << 16))
            {
                if (!o.NoHeader) WriteRow(w, t.Columns, delim, null);
                foreach (var r in t.Rows) WriteRow(w, r, delim, t);
            }
        }

        static void WriteRow(TextWriter w, IList<string> f, char delim, Table t)
        {
            for (int i = 0; i < f.Count; i++)
            {
                if (i > 0) w.Write(delim);
                string v = f[i] ?? "";
                if (t != null && t.TypeOf(i) == 'N') v = v.Trim();
                w.Write(Quote(v, delim));
            }
            w.Write("\r\n");
        }

        static string Quote(string v, char delim)
        {
            bool need = false;
            foreach (char c in v)
                if (c == delim || c == '"' || c == '\r' || c == '\n') { need = true; break; }
            if (!need) return v;
            return "\"" + v.Replace("\"", "\"\"") + "\"";
        }
    }
}
