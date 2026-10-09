using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace MIEConvert
{
    /// <summary>Collects the cells of one sheet (possibly sparse) and turns them into a Table.</summary>
    public sealed class SheetCollector
    {
        readonly SortedDictionary<int, SortedDictionary<int, string>> rows = new SortedDictionary<int, SortedDictionary<int, string>>();
        readonly int maxDataRows;
        readonly bool noHeader;

        public SheetCollector(Options o)
        {
            noHeader = o.NoHeader;
            maxDataRows = o.MaxRows;
        }

        /// <summary>True once enough non-empty rows were collected (reader may stop).</summary>
        public bool Full
        {
            get
            {
                if (maxDataRows <= 0) return false;
                return rows.Count >= maxDataRows + (noHeader ? 0 : 1) + 1;
            }
        }

        public void Set(int row, int col, string value)
        {
            if (string.IsNullOrEmpty(value)) return;
            SortedDictionary<int, string> r;
            if (!rows.TryGetValue(row, out r)) { r = new SortedDictionary<int, string>(); rows[row] = r; }
            r[col] = value;
        }

        /// <summary>Builds the table. Completely empty rows are skipped; the first non-empty row is the header.</summary>
        public Table ToTable()
        {
            var raw = new List<string[]>();
            int maxCol = -1;
            foreach (var r in rows.Values) foreach (int c in r.Keys) if (c > maxCol) maxCol = c;
            foreach (var r in rows.Values)
            {
                var a = new string[maxCol + 1];
                for (int i = 0; i <= maxCol; i++) a[i] = "";
                foreach (var kv in r) a[kv.Key] = kv.Value;
                raw.Add(a);
            }
            return Table.FromRawRows(raw, noHeader, maxDataRows);
        }
    }

    /// <summary>Excel helpers shared by the xls and xlsx code.</summary>
    public static class ExcelUtil
    {
        public const int DateStyle = 1, TimeStyle = 2, HeaderStyle = 3;
        public const string DateFormatCode = "yyyy-mm-dd";
        public const string TimeFormatCode = "hh:mm:ss";

        /// <summary>Column letters for a 0-based column index (0 -> A).</summary>
        public static string ColName(int col)
        {
            var sb = new StringBuilder();
            col++;
            while (col > 0)
            {
                int m = (col - 1) % 26;
                sb.Insert(0, (char)('A' + m));
                col = (col - 1) / 26;
            }
            return sb.ToString();
        }

        /// <summary>Parses a cell reference like "C5" into 0-based row/col. Returns false if malformed.</summary>
        public static bool ParseRef(string r, out int row, out int col)
        {
            row = -1; col = -1;
            if (string.IsNullOrEmpty(r)) return false;
            int i = 0, c = 0;
            while (i < r.Length && char.IsLetter(r[i])) { c = c * 26 + (char.ToUpperInvariant(r[i]) - 'A' + 1); i++; }
            if (i == 0) return false;
            int rr;
            if (!int.TryParse(r.Substring(i), NumberStyles.Integer, CultureInfo.InvariantCulture, out rr)) return false;
            row = rr - 1; col = c - 1;
            return true;
        }

        /// <summary>Excel sheet names: max 31 chars, none of : \ / ? * [ ].</summary>
        public static string SafeSheetName(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return "Sheet1";
            var sb = new StringBuilder();
            foreach (char c in name.Trim())
                sb.Append(":\\/?*[]".IndexOf(c) >= 0 || c < 0x20 ? '_' : c);
            string s = sb.ToString().Trim('\'');
            if (s.Length == 0) s = "Sheet1";
            if (s.Length > 31) s = s.Substring(0, 31);
            return s;
        }

        /// <summary>A typed export cell.</summary>
        public enum CellKind { Empty, String, Number, Date, Time }

        public static CellKind Classify(string v, char type, out double num)
        {
            num = 0;
            if (string.IsNullOrEmpty(v)) return CellKind.Empty;
            switch (type)
            {
                case 'N':
                    if (v.Trim().Length == 0) return CellKind.Empty;
                    if (Values.TryParseNumber(v, out num)) return CellKind.Number;
                    return CellKind.String;
                case 'D':
                    if (v.Trim().Length == 0) return CellKind.Empty;
                    DateTime dt;
                    if (Values.TryParseDate(v, out dt) && dt.Year >= 1900) { num = Values.DateToSerial(dt); return CellKind.Date; }
                    return CellKind.String;
                case 'T':
                    if (v.Trim().Length == 0) return CellKind.Empty;
                    TimeSpan ts;
                    if (Values.TryParseTime(v, out ts)) { num = Values.TimeToSerial(ts); return CellKind.Time; }
                    return CellKind.String;
            }
            return CellKind.String;
        }

        /// <summary>Approximate column width (characters) for a column, capped.</summary>
        public static double[] ColumnWidths(Table t, bool header)
        {
            var w = new double[t.Columns.Count];
            for (int c = 0; c < w.Length; c++)
            {
                int m = header ? t.Columns[c].Length + 2 : 8;
                char ty = t.TypeOf(c);
                if (ty == 'D') m = Math.Max(m, 11);
                if (ty == 'T') m = Math.Max(m, 9);
                int limit = Math.Min(t.Rows.Count, 500);
                for (int r = 0; r < limit; r++)
                {
                    string v = t.Rows[r][c];
                    if (v == null) continue;
                    int nl = v.IndexOf('\n');
                    int len = nl >= 0 ? nl : v.Length;
                    if (len > m) m = len;
                }
                w[c] = Math.Min(Math.Max(m + 1, 8), 60);
            }
            return w;
        }
    }
}
