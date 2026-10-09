using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

namespace MIEConvert
{
    /// <summary>Excel 97-2003 (.xls, BIFF8) reader and writer.</summary>
    public static class XlsFormat
    {
        // record ids
        const int BOF = 0x0809, EOF = 0x000A, BOUNDSHEET = 0x0085, SST = 0x00FC, CONTINUE = 0x003C, EXTSST = 0x00FF;
        const int LABELSST = 0x00FD, LABEL = 0x0204, RSTRING = 0x00D6, NUMBER = 0x0203, RK = 0x027E, MULRK = 0x00BD;
        const int FORMULA = 0x0006, STRING = 0x0207, BOOLERR = 0x0205, XF = 0x00E0, FORMAT = 0x041E, DATEMODE = 0x0022;
        const int CODEPAGE = 0x0042, WINDOW1 = 0x003D, FONT = 0x0031, STYLE = 0x0293, DIMENSIONS = 0x0200, ROW = 0x0208;
        const int WINDOW2 = 0x023E, COLINFO = 0x007D, DEFCOLWIDTH = 0x0055, PRECISION = 0x000E;
        const int MaxRecord = 8224;

        // ================================================================== reading

        sealed class Sheet { public string Name; public int Pos; public int Type; }

        sealed class Globals
        {
            public List<Sheet> Sheets = new List<Sheet>();
            public List<string> Sst = new List<string>();
            public Dictionary<int, string> Formats = new Dictionary<int, string>();
            public List<int> XfFormat = new List<int>();
            public bool Date1904;
            public List<Values.DateKind> Kinds;
        }

        static byte[] LoadWorkbook(string path)
        {
            byte[] file;
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                file = new byte[fs.Length];
                int read = 0;
                while (read < file.Length) { int n = fs.Read(file, read, file.Length - read); if (n <= 0) break; read += n; }
            }
            if (!CompoundFile.IsCompoundFile(file))
            {
                if (file.Length > 4 && file[0] == 'P' && file[1] == 'K')
                    throw new MieException("The file is an .xlsx workbook saved with an .xls extension; use --format xlsx.");
                throw new MieException("The file is not an Excel 97-2003 (.xls) workbook: " + path);
            }
            byte[] wb = CompoundFile.ReadStream(file, "Workbook", "Book");
            if (wb == null) throw new MieException("No Workbook stream found in " + path);
            return wb;
        }

        static Globals ReadGlobals(byte[] s)
        {
            var g = new Globals();
            int pos = 0;
            if (s.Length < 8 || BitConverter.ToUInt16(s, 0) != BOF)
                throw new MieException("Not a BIFF workbook stream.");
            int vers = BitConverter.ToUInt16(s, 4);
            if (vers != 0x0600)
                throw new MieException("Only Excel 97-2003 (BIFF8) .xls files are supported (this file is an older Excel 5/95 format). Save it as .xlsx or Excel 97-2003 first.");
            while (pos + 4 <= s.Length)
            {
                int id = BitConverter.ToUInt16(s, pos);
                int len = BitConverter.ToUInt16(s, pos + 2);
                int d = pos + 4;
                if (d + len > s.Length) break;
                switch (id)
                {
                    case BOUNDSHEET:
                    {
                        int lb = BitConverter.ToInt32(s, d);
                        int type = s[d + 5];
                        int p = d + 6;
                        int cch = s[p];
                        bool hi = (s[p + 1] & 1) != 0;
                        string name = hi ? Encoding.Unicode.GetString(s, p + 2, cch * 2) : Latin1(s, p + 2, cch);
                        g.Sheets.Add(new Sheet { Name = name, Pos = lb, Type = type });
                        break;
                    }
                    case FORMAT:
                    {
                        int ifmt = BitConverter.ToUInt16(s, d);
                        var rd = new SegReader(new List<Seg> { new Seg(s, d + 2, len - 2) });
                        g.Formats[ifmt] = rd.ReadXLUnicodeString(false);
                        break;
                    }
                    case XF:
                        g.XfFormat.Add(BitConverter.ToUInt16(s, d + 2));
                        break;
                    case DATEMODE:
                        g.Date1904 = BitConverter.ToUInt16(s, d) == 1;
                        break;
                    case SST:
                    {
                        var segs = new List<Seg> { new Seg(s, d, len) };
                        int q = d + len;
                        while (q + 4 <= s.Length && BitConverter.ToUInt16(s, q) == CONTINUE)
                        {
                            int cl = BitConverter.ToUInt16(s, q + 2);
                            segs.Add(new Seg(s, q + 4, cl));
                            q += 4 + cl;
                        }
                        ReadSst(segs, g.Sst);
                        break;
                    }
                }
                pos = d + len;
                if (id == EOF) break;
            }
            g.Kinds = new List<Values.DateKind>(g.XfFormat.Count);
            foreach (int f in g.XfFormat)
            {
                string code;
                g.Formats.TryGetValue(f, out code);
                g.Kinds.Add(Values.ClassifyFormat(f, code));
            }
            return g;
        }

        static string Latin1(byte[] b, int o, int n)
        {
            var c = new char[n];
            for (int i = 0; i < n; i++) c[i] = (char)b[o + i];
            return new string(c);
        }

        struct Seg
        {
            public byte[] B; public int Off, Len;
            public Seg(byte[] b, int off, int len) { B = b; Off = off; Len = len; }
        }

        /// <summary>Reads across an SST record and its CONTINUE records.</summary>
        sealed class SegReader
        {
            readonly List<Seg> segs;
            int si, p;
            public SegReader(List<Seg> s) { segs = s; si = 0; p = 0; }

            bool AtSegEnd { get { return p >= segs[si].Len; } }

            void Advance()
            {
                while (si < segs.Count && p >= segs[si].Len) { si++; p = 0; }
                if (si >= segs.Count) throw new EndOfStreamException();
            }

            public bool Eof
            {
                get
                {
                    int s2 = si, p2 = p;
                    while (s2 < segs.Count && p2 >= segs[s2].Len) { s2++; p2 = 0; }
                    return s2 >= segs.Count;
                }
            }

            public byte Byte()
            {
                Advance();
                var g = segs[si];
                return g.B[g.Off + p++];
            }

            public int U16() { int a = Byte(); return a | (Byte() << 8); }
            public int I32() { int a = U16(); return a | (U16() << 16); }

            public void Skip(int n) { for (int i = 0; i < n; i++) Byte(); }

            /// <summary>XLUnicodeRichExtendedString (SST) or XLUnicodeString (FORMAT, LABEL).</summary>
            public string ReadXLUnicodeString(bool rich)
            {
                int cch = U16();
                int flags = Byte();
                bool hi = (flags & 1) != 0;
                int runs = 0, ext = 0;
                if (rich)
                {
                    if ((flags & 8) != 0) runs = U16();
                    if ((flags & 4) != 0) ext = I32();
                }
                var sb = new StringBuilder(cch);
                for (int i = 0; i < cch; i++)
                {
                    if (AtSegEnd && rich)
                    {
                        // a CONTINUE boundary inside character data repeats the option flags
                        si++; p = 0;
                        if (si >= segs.Count) throw new EndOfStreamException();
                        hi = (Byte() & 1) != 0;
                    }
                    if (hi) sb.Append((char)U16());
                    else sb.Append((char)Byte());
                }
                if (runs > 0) Skip(runs * 4);
                if (ext > 0) Skip(ext);
                return sb.ToString();
            }
        }

        static void ReadSst(List<Seg> segs, List<string> into)
        {
            var r = new SegReader(segs);
            try
            {
                r.Skip(4);
                int unique = r.I32();
                for (int i = 0; i < unique && !r.Eof; i++) into.Add(r.ReadXLUnicodeString(true));
            }
            catch (EndOfStreamException) { }
        }

        public static List<string> SheetNames(string path)
        {
            var g = ReadGlobals(LoadWorkbook(path));
            return g.Sheets.Where(x => x.Type == 0).Select(x => x.Name).ToList();
        }

        public static Table Read(string path, Options o)
        {
            byte[] s = LoadWorkbook(path);
            Globals g = ReadGlobals(s);
            var sheets = g.Sheets.Where(x => x.Type == 0).ToList();
            if (sheets.Count == 0) throw new MieException("The workbook contains no worksheets.");
            Sheet sh = sheets[0];
            if (!string.IsNullOrEmpty(o.Sheet))
            {
                sh = sheets.FirstOrDefault(x => string.Equals(x.Name, o.Sheet, StringComparison.OrdinalIgnoreCase));
                if (sh == null) throw new MieException("Sheet '" + o.Sheet + "' not found. Sheets: " + string.Join(", ", sheets.Select(x => x.Name)));
            }
            var coll = new SheetCollector(o);
            ReadSheet(s, sh.Pos, g, coll);
            return coll.ToTable();
        }

        static string Num(Globals g, int xf, double v)
        {
            if (xf >= 0 && xf < g.Kinds.Count && g.Kinds[xf] != Values.DateKind.None)
                return Values.FormatSerial(v, g.Kinds[xf], g.Date1904);
            return Values.FormatNumber(v);
        }

        static double RkValue(int rk)
        {
            double v;
            if ((rk & 2) != 0) v = rk >> 2;
            else v = BitConverter.Int64BitsToDouble((long)((ulong)(uint)(rk & unchecked((int)0xFFFFFFFC)) << 32));
            if ((rk & 1) != 0) v /= 100.0;
            return v;
        }

        static string ErrorText(int code)
        {
            switch (code)
            {
                case 0x00: return "#NULL!";
                case 0x07: return "#DIV/0!";
                case 0x0F: return "#VALUE!";
                case 0x17: return "#REF!";
                case 0x1D: return "#NAME?";
                case 0x24: return "#NUM!";
                case 0x2A: return "#N/A";
            }
            return "#ERR";
        }

        static void ReadSheet(byte[] s, int pos, Globals g, SheetCollector coll)
        {
            int depth = 0;
            int pendRow = -1, pendCol = -1;
            if (pos < 0 || pos + 4 > s.Length) throw new MieException("Corrupt .xls file (bad sheet offset).");
            while (pos + 4 <= s.Length)
            {
                int id = BitConverter.ToUInt16(s, pos);
                int len = BitConverter.ToUInt16(s, pos + 2);
                int d = pos + 4;
                if (d + len > s.Length) break;
                pos = d + len;
                if (id == BOF) { depth++; continue; }
                if (id == EOF) { depth--; if (depth <= 0) break; continue; }
                if (depth != 1) continue;
                switch (id)
                {
                    case LABELSST:
                    {
                        int r = BitConverter.ToUInt16(s, d), c = BitConverter.ToUInt16(s, d + 2);
                        int isst = BitConverter.ToInt32(s, d + 6);
                        if (isst >= 0 && isst < g.Sst.Count) coll.Set(r, c, g.Sst[isst]);
                        break;
                    }
                    case LABEL:
                    case RSTRING:
                    {
                        int r = BitConverter.ToUInt16(s, d), c = BitConverter.ToUInt16(s, d + 2);
                        var rd = new SegReader(new List<Seg> { new Seg(s, d + 6, len - 6) });
                        try { coll.Set(r, c, rd.ReadXLUnicodeString(false)); } catch (EndOfStreamException) { }
                        break;
                    }
                    case NUMBER:
                    {
                        int r = BitConverter.ToUInt16(s, d), c = BitConverter.ToUInt16(s, d + 2), xf = BitConverter.ToUInt16(s, d + 4);
                        coll.Set(r, c, Num(g, xf, BitConverter.ToDouble(s, d + 6)));
                        break;
                    }
                    case RK:
                    {
                        int r = BitConverter.ToUInt16(s, d), c = BitConverter.ToUInt16(s, d + 2), xf = BitConverter.ToUInt16(s, d + 4);
                        coll.Set(r, c, Num(g, xf, RkValue(BitConverter.ToInt32(s, d + 6))));
                        break;
                    }
                    case MULRK:
                    {
                        int r = BitConverter.ToUInt16(s, d), c = BitConverter.ToUInt16(s, d + 2);
                        int n = (len - 6) / 6;
                        for (int i = 0; i < n; i++)
                        {
                            int o = d + 4 + i * 6;
                            int xf = BitConverter.ToUInt16(s, o);
                            coll.Set(r, c + i, Num(g, xf, RkValue(BitConverter.ToInt32(s, o + 2))));
                        }
                        break;
                    }
                    case BOOLERR:
                    {
                        int r = BitConverter.ToUInt16(s, d), c = BitConverter.ToUInt16(s, d + 2);
                        int v = s[d + 6], isErr = s[d + 7];
                        coll.Set(r, c, isErr != 0 ? ErrorText(v) : (v != 0 ? "1" : "0"));
                        break;
                    }
                    case FORMULA:
                    {
                        int r = BitConverter.ToUInt16(s, d), c = BitConverter.ToUInt16(s, d + 2), xf = BitConverter.ToUInt16(s, d + 4);
                        if (s[d + 12] == 0xFF && s[d + 13] == 0xFF)
                        {
                            int type = s[d + 6];
                            if (type == 0) { pendRow = r; pendCol = c; }
                            else if (type == 1) coll.Set(r, c, s[d + 8] != 0 ? "1" : "0");
                            else if (type == 2) coll.Set(r, c, ErrorText(s[d + 8]));
                        }
                        else coll.Set(r, c, Num(g, xf, BitConverter.ToDouble(s, d + 6)));
                        break;
                    }
                    case STRING:
                    {
                        if (pendRow >= 0)
                        {
                            var segs = new List<Seg> { new Seg(s, d, len) };
                            int q = pos;
                            while (q + 4 <= s.Length && BitConverter.ToUInt16(s, q) == CONTINUE)
                            {
                                int cl = BitConverter.ToUInt16(s, q + 2);
                                segs.Add(new Seg(s, q + 4, cl));
                                q += 4 + cl;
                            }
                            try { coll.Set(pendRow, pendCol, new SegReader(segs).ReadXLUnicodeString(true)); } catch (EndOfStreamException) { }
                            pendRow = pendCol = -1;
                        }
                        break;
                    }
                }
                if (coll.Full) break;
            }
        }

        // ================================================================== writing

        sealed class Rec
        {
            readonly MemoryStream ms = new MemoryStream();
            readonly BinaryWriter w;
            public Rec() { w = new BinaryWriter(ms); }
            public long Position { get { return ms.Position; } }
            public byte[] ToArray() { return ms.ToArray(); }

            public void Record(int id, byte[] data)
            {
                if (data.Length > MaxRecord) throw new InvalidOperationException("record too long");
                w.Write((ushort)id);
                w.Write((ushort)data.Length);
                w.Write(data);
            }

            public void Record(int id, params object[] parts)
            {
                var b = new MemoryStream();
                var bw = new BinaryWriter(b);
                foreach (object p in parts)
                {
                    if (p is ushort) bw.Write((ushort)p);
                    else if (p is short) bw.Write((short)p);
                    else if (p is int) bw.Write((int)p);
                    else if (p is uint) bw.Write((uint)p);
                    else if (p is byte) bw.Write((byte)p);
                    else if (p is double) bw.Write((double)p);
                    else if (p is byte[]) bw.Write((byte[])p);
                    else throw new ArgumentException(p.GetType().Name);
                }
                Record(id, b.ToArray());
            }
        }

        static byte[] ShortUnicode(string s)
        {
            // ShortXLUnicodeString, always stored as UTF-16
            if (s.Length > 255) s = s.Substring(0, 255);
            var b = new byte[2 + s.Length * 2];
            b[0] = (byte)s.Length;
            b[1] = 1;
            Encoding.Unicode.GetBytes(s, 0, s.Length, b, 2);
            return b;
        }

        static byte[] LongUnicode(string s)
        {
            // XLUnicodeString
            var b = new byte[3 + s.Length * 2];
            b[0] = (byte)s.Length; b[1] = (byte)(s.Length >> 8);
            b[2] = 1;
            Encoding.Unicode.GetBytes(s, 0, s.Length, b, 3);
            return b;
        }

        static byte[] FontRec(bool bold)
        {
            var b = new MemoryStream();
            var w = new BinaryWriter(b);
            w.Write((ushort)200);           // 10 pt
            w.Write((ushort)(bold ? 1 : 0)); // grbit (bit 0 = bold, read by some tools)
            w.Write((ushort)0x7FFF);        // colour: automatic
            w.Write((ushort)(bold ? 700 : 400));
            w.Write((ushort)0);             // super/subscript
            w.Write((byte)0);               // underline
            w.Write((byte)2);               // family: swiss
            w.Write((byte)0);               // charset
            w.Write((byte)0);
            w.Write((byte)5); w.Write((byte)0); w.Write(Encoding.ASCII.GetBytes("Arial"));
            return b.ToArray();
        }

        static byte[] XfRec(int font, int fmt, bool style, byte used)
        {
            var b = new byte[20];
            b[0] = (byte)font; b[1] = (byte)(font >> 8);
            b[2] = (byte)fmt; b[3] = (byte)(fmt >> 8);
            int prot = style ? 0xFFF5 : 0x0001;
            b[4] = (byte)prot; b[5] = (byte)(prot >> 8);
            b[6] = 0x20;     // bottom aligned
            b[9] = used;
            b[18] = 0xC0; b[19] = 0x20;  // default pattern colours
            return b;
        }

        const int XfCell = 15, XfDate = 16, XfTime = 17, XfHeader = 18;
        const int FmtDate = 164, FmtTime = 165;

        sealed class SstBuilder
        {
            public readonly List<string> Strings = new List<string>();
            public readonly Dictionary<string, int> Index = new Dictionary<string, int>(StringComparer.Ordinal);
            public int Total;

            public int Add(string s)
            {
                Total++;
                int i;
                if (Index.TryGetValue(s, out i)) return i;
                i = Strings.Count;
                Strings.Add(s);
                Index[s] = i;
                return i;
            }
        }

        /// <summary>Writes SST + CONTINUE records and an EXTSST index.</summary>
        static void WriteSst(Rec rec, SstBuilder sst)
        {
            var segs = new List<MemoryStream>();
            var cur = new MemoryStream();
            segs.Add(cur);
            cur.Write(BitConverter.GetBytes(sst.Total), 0, 4);
            cur.Write(BitConverter.GetBytes(sst.Strings.Count), 0, 4);
            int bucket = Math.Max(8, (sst.Strings.Count + 127) / 128);
            var marks = new List<KeyValuePair<int, int>>(); // (segment, offset) of bucket starts
            for (int i = 0; i < sst.Strings.Count; i++)
            {
                string s = sst.Strings[i];
                bool hi = false;
                foreach (char c in s) if (c > 0xFF) { hi = true; break; }
                if (MaxRecord - cur.Length < 4) { cur = new MemoryStream(); segs.Add(cur); }
                if (i % bucket == 0) marks.Add(new KeyValuePair<int, int>(segs.Count - 1, (int)cur.Length));
                cur.WriteByte((byte)s.Length); cur.WriteByte((byte)(s.Length >> 8));
                cur.WriteByte((byte)(hi ? 1 : 0));
                int pos = 0;
                while (pos < s.Length)
                {
                    int room = MaxRecord - (int)cur.Length;
                    int fit = hi ? room / 2 : room;
                    if (fit <= 0)
                    {
                        cur = new MemoryStream(); segs.Add(cur);
                        cur.WriteByte((byte)(hi ? 1 : 0));
                        continue;
                    }
                    int n = Math.Min(fit, s.Length - pos);
                    for (int k = 0; k < n; k++)
                    {
                        char c = s[pos + k];
                        cur.WriteByte((byte)c);
                        if (hi) cur.WriteByte((byte)(c >> 8));
                    }
                    pos += n;
                }
            }
            var segStart = new List<long>();
            for (int i = 0; i < segs.Count; i++)
            {
                segStart.Add(rec.Position);
                rec.Record(i == 0 ? SST : CONTINUE, segs[i].ToArray());
            }
            var ext = new MemoryStream();
            ext.Write(BitConverter.GetBytes((ushort)bucket), 0, 2);
            foreach (var m in marks)
            {
                ext.Write(BitConverter.GetBytes((uint)(segStart[m.Key] + 4 + m.Value)), 0, 4);
                ext.Write(BitConverter.GetBytes((ushort)(4 + m.Value)), 0, 2);
                ext.Write(BitConverter.GetBytes((ushort)0), 0, 2);
            }
            rec.Record(EXTSST, ext.ToArray());
        }

        public static void Write(string path, Table t, Options o)
        {
            string sheetName = ExcelUtil.SafeSheetName(string.IsNullOrEmpty(o.Sheet) ? "Sheet1" : o.Sheet);
            int nCols = t.Columns.Count;
            int nRows = t.Rows.Count + (o.NoHeader ? 0 : 1);
            if (nCols > 256) throw new MieException("The .xls format supports at most 256 columns (" + nCols + " requested). Use xlsx.");
            if (nRows > 65536) throw new MieException("The .xls format supports at most 65536 rows (" + nRows + " requested). Use xlsx.");

            // ---- cells first (so the SST is complete)
            var sst = new SstBuilder();
            var sheet = new Rec();
            sheet.Record(BOF, (ushort)0x0600, (ushort)0x0010, (ushort)0x0DBB, (ushort)0x07CC, 0, 6);
            sheet.Record(DEFCOLWIDTH, (ushort)8);
            if (nCols > 0)
            {
                double[] widths = ExcelUtil.ColumnWidths(t, !o.NoHeader);
                for (int c = 0; c < nCols; c++)
                    sheet.Record(COLINFO, (ushort)c, (ushort)c, (ushort)Math.Min(255 * 256, (int)(widths[c] * 256)), (ushort)XfCell, (ushort)0, (ushort)0);
            }
            sheet.Record(DIMENSIONS, 0, nRows, (ushort)0, (ushort)nCols, (ushort)0);

            int rowNo = 0;
            var cellBuf = new Rec();
            var rowBuf = new Rec();
            Action flush = () =>
            {
                byte[] rb = rowBuf.ToArray();
                byte[] cb = cellBuf.ToArray();
                WriteRaw(sheet, rb);
                WriteRaw(sheet, cb);
                rowBuf = new Rec();
                cellBuf = new Rec();
            };
            Action<int> addRow = r =>
            {
                rowBuf.Record(ROW, (ushort)r, (ushort)0, (ushort)nCols, (ushort)0x00FF, (ushort)0, (ushort)0, (ushort)0x0100, (ushort)XfCell);
            };
            if (!o.NoHeader)
            {
                addRow(rowNo);
                for (int c = 0; c < nCols; c++)
                {
                    string h = Trunc(t.Columns[c]);
                    if (h.Length > 0) cellBuf.Record(LABELSST, (ushort)rowNo, (ushort)c, (ushort)XfHeader, sst.Add(h));
                }
                rowNo++;
            }
            foreach (var r in t.Rows)
            {
                if (rowNo % 32 == 0 && rowNo > 0) flush();
                addRow(rowNo);
                for (int c = 0; c < nCols; c++)
                {
                    double num;
                    string v = r[c];
                    switch (ExcelUtil.Classify(v, t.TypeOf(c), out num))
                    {
                        case ExcelUtil.CellKind.Empty: break;
                        case ExcelUtil.CellKind.String: cellBuf.Record(LABELSST, (ushort)rowNo, (ushort)c, (ushort)XfCell, sst.Add(Trunc(v))); break;
                        case ExcelUtil.CellKind.Number: cellBuf.Record(NUMBER, (ushort)rowNo, (ushort)c, (ushort)XfCell, num); break;
                        case ExcelUtil.CellKind.Date: cellBuf.Record(NUMBER, (ushort)rowNo, (ushort)c, (ushort)XfDate, num); break;
                        case ExcelUtil.CellKind.Time: cellBuf.Record(NUMBER, (ushort)rowNo, (ushort)c, (ushort)XfTime, num); break;
                    }
                }
                rowNo++;
            }
            flush();
            sheet.Record(WINDOW2, (ushort)0x06B6, (ushort)0, (ushort)0, (ushort)0x40, (ushort)0, (ushort)0, (ushort)0, 0);
            sheet.Record(EOF, new byte[0]);
            byte[] sheetBytes = sheet.ToArray();

            // ---- workbook globals
            var gl = new Rec();
            gl.Record(BOF, (ushort)0x0600, (ushort)0x0005, (ushort)0x0DBB, (ushort)0x07CC, 0, 6);
            gl.Record(CODEPAGE, (ushort)1200);
            gl.Record(WINDOW1, (ushort)0, (ushort)0, (ushort)0x3A5C, (ushort)0x23BE, (ushort)0x0038, (ushort)0, (ushort)0, (ushort)1, (ushort)0x0258);
            gl.Record(DATEMODE, (ushort)0);
            gl.Record(PRECISION, (ushort)1);
            for (int i = 0; i < 4; i++) gl.Record(FONT, FontRec(false));
            gl.Record(FONT, FontRec(true)); // font index 5 (index 4 is never used in BIFF)
            gl.Record(FORMAT, (ushort)FmtDate, LongUnicode(ExcelUtil.DateFormatCode));
            gl.Record(FORMAT, (ushort)FmtTime, LongUnicode(ExcelUtil.TimeFormatCode));
            gl.Record(XF, XfRec(0, 0, true, 0x00));
            for (int i = 1; i < 15; i++) gl.Record(XF, XfRec(0, 0, true, 0xF4));
            gl.Record(XF, XfRec(0, 0, false, 0x00));          // 15 default cell format
            gl.Record(XF, XfRec(0, FmtDate, false, 0x04));    // 16 date
            gl.Record(XF, XfRec(0, FmtTime, false, 0x04));    // 17 time
            gl.Record(XF, XfRec(5, 0, false, 0x08));          // 18 bold header
            gl.Record(STYLE, (ushort)0x8000, (byte)0, (byte)0xFF);
            long bsPos = gl.Position;
            gl.Record(BOUNDSHEET, 0, (byte)0, (byte)0, ShortUnicode(sheetName));
            WriteSst(gl, sst);
            gl.Record(EOF, new byte[0]);
            byte[] globals = gl.ToArray();
            // patch the sheet offset in BOUNDSHEET
            byte[] lb = BitConverter.GetBytes(globals.Length);
            Array.Copy(lb, 0, globals, (int)bsPos + 4, 4);

            var stream = new byte[Math.Max(4096, globals.Length + sheetBytes.Length)];
            Array.Copy(globals, stream, globals.Length);
            Array.Copy(sheetBytes, 0, stream, globals.Length, sheetBytes.Length);

            string tmp = path + ".mietmp";
            try
            {
                using (var fs = new FileStream(tmp, FileMode.Create, FileAccess.Write))
                    CompoundFile.WriteSingleStream(fs, "Workbook", stream);
                if (File.Exists(path)) File.Delete(path);
                File.Move(tmp, path);
            }
            finally
            {
                try { if (File.Exists(tmp)) File.Delete(tmp); } catch { }
            }
        }

        static void WriteRaw(Rec target, byte[] records)
        {
            int p = 0;
            while (p + 4 <= records.Length)
            {
                int id = BitConverter.ToUInt16(records, p);
                int len = BitConverter.ToUInt16(records, p + 2);
                var d = new byte[len];
                Array.Copy(records, p + 4, d, 0, len);
                target.Record(id, d);
                p += 4 + len;
            }
        }

        static string Trunc(string s)
        {
            s = s ?? "";
            return s.Length > 32767 ? s.Substring(0, 32767) : s;
        }
    }
}
