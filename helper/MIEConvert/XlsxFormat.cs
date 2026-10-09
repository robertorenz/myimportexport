using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;

namespace MIEConvert
{
    /// <summary>OpenXML spreadsheet (.xlsx) reader and writer using only System.IO.Compression and System.Xml.</summary>
    public static class XlsxFormat
    {
        const string NsMain = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
        const string NsRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
        const string NsPkgRel = "http://schemas.openxmlformats.org/package/2006/relationships";
        const string NsCt = "http://schemas.openxmlformats.org/package/2006/content-types";
        const string RelOfficeDoc = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument";
        const string RelWorksheet = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet";
        const string RelStyles = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles";
        const string CtWorksheet = "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml";
        const string CtStyles = "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml";
        const string CtWorkbook = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml";
        const string CtRels = "application/vnd.openxmlformats-package.relationships+xml";

        static readonly XmlReaderSettings ReaderSettings = new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Ignore,
            XmlResolver = null,
            IgnoreComments = true,
            IgnoreWhitespace = false,
            CloseInput = true
        };

        // ------------------------------------------------------------------ package helpers

        sealed class Rel
        {
            public string Id, Type, Target;
        }

        sealed class SheetInfo
        {
            public string Name, RelId, Part, Type;
        }

        static ZipArchiveEntry Entry(ZipArchive zip, string part)
        {
            string p = part.TrimStart('/');
            var e = zip.GetEntry(p);
            if (e != null) return e;
            foreach (var x in zip.Entries)
                if (string.Equals(x.FullName.Replace('\\', '/').TrimStart('/'), p, StringComparison.OrdinalIgnoreCase)) return x;
            return null;
        }

        static string RelsPartFor(string part)
        {
            part = part.TrimStart('/');
            int slash = part.LastIndexOf('/');
            string dir = slash >= 0 ? part.Substring(0, slash + 1) : "";
            string file = slash >= 0 ? part.Substring(slash + 1) : part;
            return dir + "_rels/" + file + ".rels";
        }

        static string ResolveTarget(string sourcePart, string target)
        {
            if (target.StartsWith("/", StringComparison.Ordinal)) return target.TrimStart('/');
            sourcePart = sourcePart.TrimStart('/');
            int slash = sourcePart.LastIndexOf('/');
            var parts = new List<string>(slash >= 0 ? sourcePart.Substring(0, slash).Split('/') : new string[0]);
            foreach (string seg in target.Split('/'))
            {
                if (seg == "..") { if (parts.Count > 0) parts.RemoveAt(parts.Count - 1); }
                else if (seg != "." && seg.Length > 0) parts.Add(seg);
            }
            return string.Join("/", parts);
        }

        static List<Rel> ReadRels(ZipArchive zip, string sourcePart)
        {
            var list = new List<Rel>();
            var e = Entry(zip, sourcePart == "" ? "_rels/.rels" : RelsPartFor(sourcePart));
            if (e == null) return list;
            using (var xr = XmlReader.Create(e.Open(), ReaderSettings))
            {
                while (xr.Read())
                {
                    if (xr.NodeType == XmlNodeType.Element && xr.LocalName == "Relationship")
                    {
                        if (string.Equals(xr.GetAttribute("TargetMode"), "External", StringComparison.OrdinalIgnoreCase)) continue;
                        list.Add(new Rel
                        {
                            Id = xr.GetAttribute("Id"),
                            Type = xr.GetAttribute("Type") ?? "",
                            Target = ResolveTarget(sourcePart, xr.GetAttribute("Target") ?? "")
                        });
                    }
                }
            }
            return list;
        }

        static string WorkbookPart(ZipArchive zip)
        {
            foreach (var r in ReadRels(zip, ""))
                if (r.Type.EndsWith("/officeDocument", StringComparison.Ordinal)) return r.Target;
            if (Entry(zip, "xl/workbook.xml") != null) return "xl/workbook.xml";
            throw new MieException("Not an Excel workbook (no workbook part found).");
        }

        static ZipArchive OpenRead(string path)
        {
            try
            {
                var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                return new ZipArchive(fs, ZipArchiveMode.Read, false);
            }
            catch (InvalidDataException)
            {
                throw new MieException("The file is not a valid .xlsx workbook: " + path);
            }
        }

        static List<SheetInfo> ReadSheets(ZipArchive zip, string wbPart, out bool date1904)
        {
            date1904 = false;
            var rels = ReadRels(zip, wbPart);
            var list = new List<SheetInfo>();
            var e = Entry(zip, wbPart);
            if (e == null) throw new MieException("Workbook part missing: " + wbPart);
            using (var xr = XmlReader.Create(e.Open(), ReaderSettings))
            {
                while (xr.Read())
                {
                    if (xr.NodeType != XmlNodeType.Element) continue;
                    if (xr.LocalName == "workbookPr")
                    {
                        string d = xr.GetAttribute("date1904");
                        date1904 = d == "1" || string.Equals(d, "true", StringComparison.OrdinalIgnoreCase);
                    }
                    else if (xr.LocalName == "sheet")
                    {
                        string rid = null;
                        if (xr.MoveToFirstAttribute())
                        {
                            do { if (xr.LocalName == "id" && xr.NamespaceURI.EndsWith("/relationships", StringComparison.Ordinal)) rid = xr.Value; }
                            while (xr.MoveToNextAttribute());
                            xr.MoveToElement();
                        }
                        var si = new SheetInfo { Name = xr.GetAttribute("name") ?? "", RelId = rid };
                        var rel = rels.FirstOrDefault(r => r.Id == rid);
                        if (rel != null) { si.Part = rel.Target; si.Type = rel.Type; }
                        list.Add(si);
                    }
                }
            }
            return list;
        }

        public static List<string> SheetNames(string path)
        {
            using (var zip = OpenRead(path))
            {
                bool d1904;
                return ReadSheets(zip, WorkbookPart(zip), out d1904)
                    .Where(s => s.Type == null || s.Type.EndsWith("/worksheet", StringComparison.Ordinal))
                    .Select(s => s.Name).ToList();
            }
        }

        // ------------------------------------------------------------------ reading

        static readonly Regex XEscape = new Regex("_x([0-9A-Fa-f]{4})_", RegexOptions.Compiled);

        static string DecodeX(string s)
        {
            if (s.IndexOf("_x", StringComparison.Ordinal) < 0) return s;
            return XEscape.Replace(s, m => ((char)int.Parse(m.Groups[1].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture)).ToString());
        }

        static readonly Regex XEscapeLiteral = new Regex("_(x[0-9A-Fa-f]{4}_)", RegexOptions.Compiled);

        /// <summary>Encodes a string for a &lt;t&gt; element: literal _xHHHH_ is protected, illegal XML chars become _xHHHH_.</summary>
        static string EncodeX(string s)
        {
            if (s.IndexOf("_x", StringComparison.Ordinal) >= 0) s = XEscapeLiteral.Replace(s, "_x005F_$1");
            StringBuilder sb = null;
            for (int i = 0; i < s.Length; i++)
            {
                char c = s[i];
                bool bad = (c < 0x20 && c != '\t' && c != '\n' && c != '\r') || c == 0xFFFE || c == 0xFFFF
                    || (char.IsSurrogate(c) && !(char.IsHighSurrogate(c) && i + 1 < s.Length && char.IsLowSurrogate(s[i + 1]))
                        && !(char.IsLowSurrogate(c) && i > 0 && char.IsHighSurrogate(s[i - 1])));
                if (bad)
                {
                    if (sb == null) { sb = new StringBuilder(); sb.Append(s, 0, i); }
                    sb.Append("_x").Append(((int)c).ToString("X4", CultureInfo.InvariantCulture)).Append('_');
                }
                else if (sb != null) sb.Append(c);
            }
            return sb == null ? s : sb.ToString();
        }

        static List<string> ReadSharedStrings(ZipArchive zip, string part)
        {
            var list = new List<string>();
            var e = part == null ? null : Entry(zip, part);
            if (e == null) return list;
            using (var xr = XmlReader.Create(e.Open(), ReaderSettings))
            {
                StringBuilder cur = null;
                while (!xr.EOF)
                {
                    if (xr.NodeType == XmlNodeType.Element)
                    {
                        if (xr.LocalName == "si") { cur = new StringBuilder(); if (xr.IsEmptyElement) { list.Add(""); cur = null; } xr.Read(); continue; }
                        if (xr.LocalName == "rPh") { xr.Skip(); continue; }
                        if (xr.LocalName == "t" && cur != null) { cur.Append(xr.ReadElementContentAsString()); continue; }
                    }
                    else if (xr.NodeType == XmlNodeType.EndElement && xr.LocalName == "si" && cur != null)
                    {
                        list.Add(DecodeX(cur.ToString()));
                        cur = null;
                    }
                    xr.Read();
                }
            }
            return list;
        }

        static List<Values.DateKind> ReadStyles(ZipArchive zip, string part)
        {
            var kinds = new List<Values.DateKind>();
            var e = part == null ? null : Entry(zip, part);
            if (e == null) return kinds;
            XDocument doc;
            using (var xr = XmlReader.Create(e.Open(), ReaderSettings)) doc = XDocument.Load(xr);
            var fmts = new Dictionary<int, string>();
            foreach (var nf in doc.Descendants().Where(x => x.Name.LocalName == "numFmt"))
            {
                int id;
                if (int.TryParse((string)nf.Attribute("numFmtId"), out id)) fmts[id] = (string)nf.Attribute("formatCode") ?? "";
            }
            var cellXfs = doc.Descendants().FirstOrDefault(x => x.Name.LocalName == "cellXfs");
            if (cellXfs != null)
            {
                foreach (var xf in cellXfs.Elements().Where(x => x.Name.LocalName == "xf"))
                {
                    int id;
                    int.TryParse((string)xf.Attribute("numFmtId") ?? "0", out id);
                    string code;
                    fmts.TryGetValue(id, out code);
                    kinds.Add(Values.ClassifyFormat(id, code));
                }
            }
            return kinds;
        }

        public static Table Read(string path, Options o)
        {
            using (var zip = OpenRead(path))
            {
                string wb = WorkbookPart(zip);
                bool d1904;
                var sheets = ReadSheets(zip, wb, out d1904).Where(s => s.Type == null || s.Type.EndsWith("/worksheet", StringComparison.Ordinal)).ToList();
                if (sheets.Count == 0) throw new MieException("The workbook contains no worksheets.");
                SheetInfo sheet = sheets[0];
                if (!string.IsNullOrEmpty(o.Sheet))
                {
                    sheet = sheets.FirstOrDefault(s => string.Equals(s.Name, o.Sheet, StringComparison.OrdinalIgnoreCase));
                    if (sheet == null) throw new MieException("Sheet '" + o.Sheet + "' not found. Sheets: " + string.Join(", ", sheets.Select(s => s.Name)));
                }
                if (sheet.Part == null) throw new MieException("Sheet '" + sheet.Name + "' has no worksheet part.");
                var rels = ReadRels(zip, wb);
                var sstRel = rels.FirstOrDefault(r => r.Type.EndsWith("/sharedStrings", StringComparison.Ordinal));
                var styRel = rels.FirstOrDefault(r => r.Type.EndsWith("/styles", StringComparison.Ordinal));
                List<string> sst = ReadSharedStrings(zip, sstRel != null ? sstRel.Target : "xl/sharedStrings.xml");
                List<Values.DateKind> kinds = ReadStyles(zip, styRel != null ? styRel.Target : "xl/styles.xml");

                var e = Entry(zip, sheet.Part);
                if (e == null) throw new MieException("Worksheet part missing: " + sheet.Part);
                var coll = new SheetCollector(o);
                ReadSheetData(e, sst, kinds, d1904, coll);
                return coll.ToTable();
            }
        }

        static void ReadSheetData(ZipArchiveEntry e, List<string> sst, List<Values.DateKind> kinds, bool d1904, SheetCollector coll)
        {
            using (var xr = XmlReader.Create(e.Open(), ReaderSettings))
            {
                int curRow = -1, curCol = -1;
                while (xr.Read())
                {
                    if (xr.NodeType != XmlNodeType.Element) continue;
                    string ln = xr.LocalName;
                    if (ln == "row")
                    {
                        string r = xr.GetAttribute("r");
                        int rr;
                        curRow = r != null && int.TryParse(r, NumberStyles.Integer, CultureInfo.InvariantCulture, out rr) ? rr - 1 : curRow + 1;
                        curCol = -1;
                        if (coll.Full) return;
                    }
                    else if (ln == "c")
                    {
                        int row = curRow, col = curCol + 1;
                        int pr, pc;
                        if (ExcelUtil.ParseRef(xr.GetAttribute("r"), out pr, out pc)) { row = pr; col = pc; }
                        if (row < 0) row = 0;
                        curCol = col;
                        string t = xr.GetAttribute("t") ?? "n";
                        int s = 0;
                        string sa = xr.GetAttribute("s");
                        if (sa != null) int.TryParse(sa, NumberStyles.Integer, CultureInfo.InvariantCulture, out s);
                        if (xr.IsEmptyElement) continue;
                        string v = null;
                        StringBuilder inl = null;
                        using (var sub = xr.ReadSubtree())
                        {
                            sub.Read();
                            sub.Read();
                            while (!sub.EOF)
                            {
                                if (sub.NodeType == XmlNodeType.Element)
                                {
                                    if (sub.LocalName == "v") { v = sub.ReadElementContentAsString(); continue; }
                                    if (sub.LocalName == "t") { (inl ?? (inl = new StringBuilder())).Append(sub.ReadElementContentAsString()); continue; }
                                    if (sub.LocalName == "rPh" || sub.LocalName == "f" || sub.LocalName == "extLst") { sub.Skip(); continue; }
                                }
                                sub.Read();
                            }
                        }
                        string val = CellText(t, v, inl, s, sst, kinds, d1904);
                        coll.Set(row, col, val);
                    }
                }
            }
        }

        static string CellText(string t, string v, StringBuilder inl, int style, List<string> sst, List<Values.DateKind> kinds, bool d1904)
        {
            switch (t)
            {
                case "s":
                    int idx;
                    if (v != null && int.TryParse(v.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out idx) && idx >= 0 && idx < sst.Count) return sst[idx];
                    return "";
                case "inlineStr":
                    return inl != null ? DecodeX(inl.ToString()) : (v != null ? DecodeX(v) : "");
                case "str":
                    return v != null ? DecodeX(v) : "";
                case "b":
                    return v == null ? "" : (v.Trim() == "1" || v.Trim().Equals("true", StringComparison.OrdinalIgnoreCase) ? "1" : "0");
                case "e":
                    return v ?? "";
                case "d":
                    if (v == null) return "";
                    DateTime dt;
                    if (DateTime.TryParse(v, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out dt))
                    {
                        var k = style >= 0 && style < kinds.Count && kinds[style] != Values.DateKind.None ? kinds[style] : (dt.TimeOfDay == TimeSpan.Zero ? Values.DateKind.Date : Values.DateKind.DateTime);
                        return Values.FormatSerial(Values.DateToSerial(dt), k, false);
                    }
                    return v;
                default:
                    if (v == null) return inl != null ? DecodeX(inl.ToString()) : "";
                    double d;
                    if (!double.TryParse(v.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out d)) return v;
                    if (style >= 0 && style < kinds.Count && kinds[style] != Values.DateKind.None)
                        return Values.FormatSerial(d, kinds[style], d1904);
                    return Values.FormatNumber(d);
            }
        }

        // ------------------------------------------------------------------ writing

        struct StyleIds { public int Date, Time, Header; }

        static XmlWriter NewWriter(Stream s)
        {
            return XmlWriter.Create(s, new XmlWriterSettings { Encoding = new UTF8Encoding(false), Indent = false, CloseOutput = true });
        }

        static void WriteEntry(ZipArchive zip, string part, string content)
        {
            var e = zip.CreateEntry(part, CompressionLevel.Optimal);
            using (var s = e.Open())
            {
                byte[] b = new UTF8Encoding(false).GetBytes(content);
                s.Write(b, 0, b.Length);
            }
        }

        static void WriteXDoc(ZipArchive zip, string part, XDocument doc)
        {
            var old = Entry(zip, part);
            if (old != null) old.Delete();
            var e = zip.CreateEntry(part.TrimStart('/'), CompressionLevel.Optimal);
            using (var w = NewWriter(e.Open())) doc.Save(w);
        }

        static XDocument LoadXDoc(ZipArchive zip, string part)
        {
            var e = Entry(zip, part);
            if (e == null) return null;
            using (var xr = XmlReader.Create(e.Open(), ReaderSettings)) return XDocument.Load(xr);
        }

        public static void Write(string path, Table t, Options o)
        {
            string sheetName = ExcelUtil.SafeSheetName(string.IsNullOrEmpty(o.Sheet) ? "Sheet1" : o.Sheet);
            if (o.ReplaceSheet && File.Exists(path) && new FileInfo(path).Length > 0)
            {
                ReplaceSheet(path, t, o, sheetName);
                return;
            }
            WriteBook(path, new List<KeyValuePair<string, Table>> { new KeyValuePair<string, Table>(sheetName, t) }, o);
        }

        /// <summary>Writes a new workbook with one worksheet per table (names must already be valid and unique).</summary>
        public static void WriteBook(string path, List<KeyValuePair<string, Table>> sheets, Options o)
        {
            string tmp = path + ".mietmp";
            try
            {
                using (var fs = new FileStream(tmp, FileMode.Create, FileAccess.ReadWrite))
                using (var zip = new ZipArchive(fs, ZipArchiveMode.Create))
                {
                    var ct = new StringBuilder();
                    ct.Append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n" +
                        "<Types xmlns=\"" + NsCt + "\">" +
                        "<Default Extension=\"rels\" ContentType=\"" + CtRels + "\"/>" +
                        "<Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
                        "<Override PartName=\"/xl/workbook.xml\" ContentType=\"" + CtWorkbook + "\"/>");
                    for (int i = 1; i <= sheets.Count; i++)
                        ct.Append("<Override PartName=\"/xl/worksheets/sheet" + i + ".xml\" ContentType=\"" + CtWorksheet + "\"/>");
                    ct.Append("<Override PartName=\"/xl/styles.xml\" ContentType=\"" + CtStyles + "\"/>" +
                        "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>" +
                        "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>" +
                        "</Types>");
                    WriteEntry(zip, "[Content_Types].xml", ct.ToString());
                    WriteEntry(zip, "_rels/.rels",
                        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n" +
                        "<Relationships xmlns=\"" + NsPkgRel + "\">" +
                        "<Relationship Id=\"rId1\" Type=\"" + RelOfficeDoc + "\" Target=\"xl/workbook.xml\"/>" +
                        "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/>" +
                        "<Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties\" Target=\"docProps/app.xml\"/>" +
                        "</Relationships>");
                    string now = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture);
                    WriteEntry(zip, "docProps/core.xml",
                        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n" +
                        "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:dcmitype=\"http://purl.org/dc/dcmitype/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">" +
                        "<dc:creator>MyImportExport</dc:creator>" +
                        "<dcterms:created xsi:type=\"dcterms:W3CDTF\">" + now + "</dcterms:created>" +
                        "<dcterms:modified xsi:type=\"dcterms:W3CDTF\">" + now + "</dcterms:modified>" +
                        "</cp:coreProperties>");
                    WriteEntry(zip, "docProps/app.xml",
                        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n" +
                        "<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\"><Application>Microsoft Excel</Application></Properties>");
                    var rels = new StringBuilder();
                    rels.Append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n<Relationships xmlns=\"" + NsPkgRel + "\">");
                    for (int i = 1; i <= sheets.Count; i++)
                        rels.Append("<Relationship Id=\"rId" + i + "\" Type=\"" + RelWorksheet + "\" Target=\"worksheets/sheet" + i + ".xml\"/>");
                    rels.Append("<Relationship Id=\"rId" + (sheets.Count + 1) + "\" Type=\"" + RelStyles + "\" Target=\"styles.xml\"/></Relationships>");
                    WriteEntry(zip, "xl/_rels/workbook.xml.rels", rels.ToString());
                    var wb = new StringBuilder();
                    wb.Append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n" +
                        "<workbook xmlns=\"" + NsMain + "\" xmlns:r=\"" + NsRel + "\">" +
                        "<workbookPr/>" +
                        "<bookViews><workbookView xWindow=\"0\" yWindow=\"0\" windowWidth=\"16384\" windowHeight=\"8192\"/></bookViews><sheets>");
                    for (int i = 1; i <= sheets.Count; i++)
                        wb.Append("<sheet name=\"" + SecurityElementEscape(sheets[i - 1].Key) + "\" sheetId=\"" + i + "\" r:id=\"rId" + i + "\"/>");
                    wb.Append("</sheets></workbook>");
                    WriteEntry(zip, "xl/workbook.xml", wb.ToString());
                    WriteEntry(zip, "xl/styles.xml", DefaultStyles());
                    for (int i = 1; i <= sheets.Count; i++)
                    {
                        var ze = zip.CreateEntry("xl/worksheets/sheet" + i + ".xml", CompressionLevel.Optimal);
                        using (var s = ze.Open())
                            WriteSheet(s, sheets[i - 1].Value, o, new StyleIds { Date = 1, Time = 2, Header = 3 });
                    }
                }
                if (File.Exists(path)) File.Delete(path);
                File.Move(tmp, path);
            }
            finally
            {
                try { if (File.Exists(tmp)) File.Delete(tmp); } catch { }
            }
        }

        static string SecurityElementEscape(string s)
        {
            return System.Security.SecurityElement.Escape(s);
        }

        static string DefaultStyles()
        {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n" +
                "<styleSheet xmlns=\"" + NsMain + "\">" +
                "<numFmts count=\"2\"><numFmt numFmtId=\"164\" formatCode=\"" + ExcelUtil.DateFormatCode + "\"/><numFmt numFmtId=\"165\" formatCode=\"" + ExcelUtil.TimeFormatCode + "\"/></numFmts>" +
                "<fonts count=\"2\"><font><sz val=\"11\"/><color theme=\"1\"/><name val=\"Calibri\"/><family val=\"2\"/><scheme val=\"minor\"/></font>" +
                "<font><b/><sz val=\"11\"/><color theme=\"1\"/><name val=\"Calibri\"/><family val=\"2\"/><scheme val=\"minor\"/></font></fonts>" +
                "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>" +
                "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>" +
                "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>" +
                "<cellXfs count=\"4\">" +
                "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>" +
                "<xf numFmtId=\"164\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/>" +
                "<xf numFmtId=\"165\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/>" +
                "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/>" +
                "</cellXfs>" +
                "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>" +
                "<dxfs count=\"0\"/><tableStyles count=\"0\" defaultTableStyle=\"TableStyleMedium2\" defaultPivotStyle=\"PivotStyleLight16\"/>" +
                "</styleSheet>";
        }

        static void WriteSheet(Stream s, Table t, Options o, StyleIds st)
        {
            int nCols = t.Columns.Count;
            int nRows = t.Rows.Count + (o.NoHeader ? 0 : 1);
            using (var w = NewWriter(s))
            {
                w.WriteStartDocument(true);
                w.WriteStartElement("worksheet", NsMain);
                w.WriteAttributeString("xmlns", "r", null, NsRel);
                w.WriteStartElement("dimension", NsMain);
                w.WriteAttributeString("ref", nCols == 0 || nRows == 0 ? "A1" : "A1:" + ExcelUtil.ColName(nCols - 1) + nRows.ToString(CultureInfo.InvariantCulture));
                w.WriteEndElement();
                w.WriteStartElement("sheetViews", NsMain);
                w.WriteStartElement("sheetView", NsMain);
                w.WriteAttributeString("workbookViewId", "0");
                if (!o.NoHeader && nCols > 0)
                {
                    w.WriteStartElement("pane", NsMain);
                    w.WriteAttributeString("ySplit", "1");
                    w.WriteAttributeString("topLeftCell", "A2");
                    w.WriteAttributeString("activePane", "bottomLeft");
                    w.WriteAttributeString("state", "frozen");
                    w.WriteEndElement();
                }
                w.WriteEndElement();
                w.WriteEndElement();
                w.WriteStartElement("sheetFormatPr", NsMain);
                w.WriteAttributeString("defaultRowHeight", "15");
                w.WriteEndElement();
                if (nCols > 0)
                {
                    double[] widths = ExcelUtil.ColumnWidths(t, !o.NoHeader);
                    w.WriteStartElement("cols", NsMain);
                    for (int c = 0; c < nCols; c++)
                    {
                        w.WriteStartElement("col", NsMain);
                        string n = (c + 1).ToString(CultureInfo.InvariantCulture);
                        w.WriteAttributeString("min", n);
                        w.WriteAttributeString("max", n);
                        w.WriteAttributeString("width", widths[c].ToString("0.##", CultureInfo.InvariantCulture));
                        w.WriteAttributeString("customWidth", "1");
                        w.WriteEndElement();
                    }
                    w.WriteEndElement();
                }
                w.WriteStartElement("sheetData", NsMain);
                var colNames = new string[nCols];
                for (int c = 0; c < nCols; c++) colNames[c] = ExcelUtil.ColName(c);
                int rowNo = 0;
                if (!o.NoHeader)
                {
                    rowNo++;
                    string rn = rowNo.ToString(CultureInfo.InvariantCulture);
                    w.WriteStartElement("row", NsMain);
                    w.WriteAttributeString("r", rn);
                    for (int c = 0; c < nCols; c++) WriteStringCell(w, colNames[c] + rn, t.Columns[c], st.Header);
                    w.WriteEndElement();
                }
                foreach (var r in t.Rows)
                {
                    rowNo++;
                    string rn = rowNo.ToString(CultureInfo.InvariantCulture);
                    w.WriteStartElement("row", NsMain);
                    w.WriteAttributeString("r", rn);
                    for (int c = 0; c < nCols; c++)
                    {
                        double num;
                        string v = r[c];
                        switch (ExcelUtil.Classify(v, t.TypeOf(c), out num))
                        {
                            case ExcelUtil.CellKind.Empty: break;
                            case ExcelUtil.CellKind.String: WriteStringCell(w, colNames[c] + rn, v, -1); break;
                            case ExcelUtil.CellKind.Number: WriteNumberCell(w, colNames[c] + rn, num, -1); break;
                            case ExcelUtil.CellKind.Date: WriteNumberCell(w, colNames[c] + rn, num, st.Date); break;
                            case ExcelUtil.CellKind.Time: WriteNumberCell(w, colNames[c] + rn, num, st.Time); break;
                        }
                    }
                    w.WriteEndElement();
                }
                w.WriteEndElement(); // sheetData
                w.WriteStartElement("pageMargins", NsMain);
                w.WriteAttributeString("left", "0.7"); w.WriteAttributeString("right", "0.7");
                w.WriteAttributeString("top", "0.75"); w.WriteAttributeString("bottom", "0.75");
                w.WriteAttributeString("header", "0.3"); w.WriteAttributeString("footer", "0.3");
                w.WriteEndElement();
                w.WriteEndElement(); // worksheet
                w.WriteEndDocument();
            }
        }

        static void WriteStringCell(XmlWriter w, string r, string v, int style)
        {
            if (string.IsNullOrEmpty(v)) return;
            if (v.Length > 32767) v = v.Substring(0, 32767);
            w.WriteStartElement("c", NsMain);
            w.WriteAttributeString("r", r);
            if (style >= 0) w.WriteAttributeString("s", style.ToString(CultureInfo.InvariantCulture));
            w.WriteAttributeString("t", "inlineStr");
            w.WriteStartElement("is", NsMain);
            w.WriteStartElement("t", NsMain);
            if (v.Trim().Length != v.Length || v.IndexOf('\n') >= 0 || v.IndexOf('\t') >= 0 || v.IndexOf('\r') >= 0)
                w.WriteAttributeString("xml", "space", null, "preserve");
            string enc = EncodeX(v);
            // keep CR as a character reference so XML end-of-line normalisation does not drop it
            if (enc.IndexOf('\r') >= 0)
            {
                string[] parts = enc.Split('\r');
                for (int i = 0; i < parts.Length; i++)
                {
                    if (i > 0) w.WriteCharEntity('\r');
                    w.WriteString(parts[i]);
                }
            }
            else w.WriteString(enc);
            w.WriteEndElement();
            w.WriteEndElement();
            w.WriteEndElement();
        }

        static void WriteNumberCell(XmlWriter w, string r, double num, int style)
        {
            w.WriteStartElement("c", NsMain);
            w.WriteAttributeString("r", r);
            if (style >= 0) w.WriteAttributeString("s", style.ToString(CultureInfo.InvariantCulture));
            w.WriteStartElement("v", NsMain);
            w.WriteString(num.ToString("R", CultureInfo.InvariantCulture));
            w.WriteEndElement();
            w.WriteEndElement();
        }

        // ------------------------------------------------------------------ --replacesheet

        static void ReplaceSheet(string path, Table t, Options o, string sheetName)
        {
            string tmp = path + ".mietmp";
            try
            {
                File.Copy(path, tmp, true);
                using (var fs = new FileStream(tmp, FileMode.Open, FileAccess.ReadWrite))
                using (var zip = OpenUpdate(fs, path))
                {
                    string wbPart = WorkbookPart(zip);
                    XNamespace m = NsMain, r = NsRel, pr = NsPkgRel, ct = NsCt;
                    XDocument wb = LoadXDoc(zip, wbPart);
                    XElement sheetsEl = wb.Root.Elements().FirstOrDefault(x => x.Name.LocalName == "sheets");
                    XNamespace wbNs = wb.Root.Name.Namespace;
                    if (sheetsEl == null) throw new MieException("The workbook has no <sheets> element.");
                    string relsPart = RelsPartFor(wbPart);
                    XDocument rels = LoadXDoc(zip, relsPart) ?? new XDocument(new XElement(pr + "Relationships"));
                    XDocument types = LoadXDoc(zip, "[Content_Types].xml");
                    if (types == null) throw new MieException("The workbook has no [Content_Types].xml.");

                    // styles: merge our three cell formats into the existing styles part
                    StyleIds st;
                    var styleRel = rels.Root.Elements().FirstOrDefault(x => ((string)x.Attribute("Type") ?? "").EndsWith("/styles", StringComparison.Ordinal));
                    if (styleRel == null)
                    {
                        string stylePart = ResolveTarget(wbPart, "styles.xml");
                        var old = Entry(zip, stylePart);
                        if (old != null) old.Delete();
                        WriteEntry(zip, stylePart, DefaultStyles());
                        rels.Root.Add(new XElement(pr + "Relationship", new XAttribute("Id", NewRelId(rels)), new XAttribute("Type", RelStyles), new XAttribute("Target", "styles.xml")));
                        SetOverride(types, "/" + stylePart, CtStyles);
                        st = new StyleIds { Date = 1, Time = 2, Header = 3 };
                    }
                    else
                    {
                        string stylePart = ResolveTarget(wbPart, (string)styleRel.Attribute("Target"));
                        XDocument sd = LoadXDoc(zip, stylePart);
                        st = MergeStyles(sd);
                        WriteXDoc(zip, stylePart, sd);
                    }

                    // find existing sheet with that name
                    XElement existing = sheetsEl.Elements().FirstOrDefault(x => x.Name.LocalName == "sheet" &&
                        string.Equals((string)x.Attribute("name"), sheetName, StringComparison.OrdinalIgnoreCase));
                    string sheetPart;
                    if (existing != null)
                    {
                        string rid = (string)existing.Attributes().FirstOrDefault(a => a.Name.LocalName == "id" && a.Name.NamespaceName.EndsWith("/relationships", StringComparison.Ordinal));
                        XElement rel = rels.Root.Elements().FirstOrDefault(x => (string)x.Attribute("Id") == rid);
                        if (rel == null || !((string)rel.Attribute("Type") ?? "").EndsWith("/worksheet", StringComparison.Ordinal))
                            throw new MieException("Sheet '" + sheetName + "' exists but is not a worksheet; cannot replace it.");
                        sheetPart = ResolveTarget(wbPart, (string)rel.Attribute("Target"));
                        var oldE = Entry(zip, sheetPart);
                        if (oldE != null) oldE.Delete();
                        var oldRels = Entry(zip, RelsPartFor(sheetPart));
                        if (oldRels != null) oldRels.Delete();
                        existing.SetAttributeValue("name", sheetName);
                    }
                    else
                    {
                        int n = 1;
                        while (Entry(zip, "xl/worksheets/sheet" + n + ".xml") != null) n++;
                        sheetPart = "xl/worksheets/sheet" + n + ".xml";
                        string rid = NewRelId(rels);
                        rels.Root.Add(new XElement(pr + "Relationship", new XAttribute("Id", rid), new XAttribute("Type", RelWorksheet),
                            new XAttribute("Target", "/" + sheetPart)));
                        int maxId = 0;
                        foreach (var s in sheetsEl.Elements())
                        {
                            int id;
                            if (int.TryParse((string)s.Attribute("sheetId"), out id) && id > maxId) maxId = id;
                        }
                        sheetsEl.Add(new XElement(wbNs + "sheet", new XAttribute("name", sheetName),
                            new XAttribute("sheetId", (maxId + 1).ToString(CultureInfo.InvariantCulture)), new XAttribute(r + "id", rid)));
                        SetOverride(types, "/" + sheetPart, CtWorksheet);
                    }

                    // calcChain may reference formulas of the replaced sheet: drop it, Excel rebuilds it
                    foreach (var cc in rels.Root.Elements().Where(x => ((string)x.Attribute("Type") ?? "").EndsWith("/calcChain", StringComparison.Ordinal)).ToList())
                    {
                        string ccPart = ResolveTarget(wbPart, (string)cc.Attribute("Target"));
                        var ce = Entry(zip, ccPart);
                        if (ce != null) ce.Delete();
                        cc.Remove();
                        foreach (var ov in types.Root.Elements().Where(x => string.Equals((string)x.Attribute("PartName"), "/" + ccPart, StringComparison.OrdinalIgnoreCase)).ToList()) ov.Remove();
                    }

                    var ze = zip.CreateEntry(sheetPart, CompressionLevel.Optimal);
                    using (var s = ze.Open()) WriteSheet(s, t, o, st);
                    WriteXDoc(zip, wbPart, wb);
                    WriteXDoc(zip, relsPart, rels);
                    WriteXDoc(zip, "[Content_Types].xml", types);
                }
                File.Copy(tmp, path, true);
            }
            finally
            {
                try { if (File.Exists(tmp)) File.Delete(tmp); } catch { }
            }
        }

        static ZipArchive OpenUpdate(Stream fs, string path)
        {
            try { return new ZipArchive(fs, ZipArchiveMode.Update, false); }
            catch (InvalidDataException) { throw new MieException("--replacesheet: the existing file is not a valid .xlsx workbook: " + path); }
        }

        static string NewRelId(XDocument rels)
        {
            var ids = new HashSet<string>(rels.Root.Elements().Select(x => (string)x.Attribute("Id") ?? ""));
            int n = 1;
            while (ids.Contains("rId" + n)) n++;
            return "rId" + n;
        }

        static void SetOverride(XDocument types, string partName, string contentType)
        {
            XNamespace ct = types.Root.Name.Namespace;
            var ov = types.Root.Elements().FirstOrDefault(x => x.Name.LocalName == "Override" &&
                string.Equals((string)x.Attribute("PartName"), partName, StringComparison.OrdinalIgnoreCase));
            if (ov != null) ov.SetAttributeValue("ContentType", contentType);
            else types.Root.Add(new XElement(ct + "Override", new XAttribute("PartName", partName), new XAttribute("ContentType", contentType)));
        }

        static readonly string[] StyleOrder = { "numFmts", "fonts", "fills", "borders", "cellStyleXfs", "cellXfs", "cellStyles", "dxfs", "tableStyles", "colors", "extLst" };

        static XElement EnsureChild(XElement root, string name)
        {
            XNamespace ns = root.Name.Namespace;
            var el = root.Elements().FirstOrDefault(x => x.Name.LocalName == name);
            if (el != null) return el;
            el = new XElement(ns + name, new XAttribute("count", "0"));
            int myIdx = Array.IndexOf(StyleOrder, name);
            XElement before = root.Elements().FirstOrDefault(x => Array.IndexOf(StyleOrder, x.Name.LocalName) > myIdx);
            if (before != null) before.AddBeforeSelf(el); else root.Add(el);
            return el;
        }

        static StyleIds MergeStyles(XDocument sd)
        {
            XElement root = sd.Root;
            XNamespace ns = root.Name.Namespace;
            // number formats
            XElement numFmts = EnsureChild(root, "numFmts");
            int maxId = 163;
            foreach (var nf in numFmts.Elements())
            {
                int id;
                if (int.TryParse((string)nf.Attribute("numFmtId"), out id) && id > maxId) maxId = id;
            }
            Func<string, int> fmtId = code =>
            {
                var hit = numFmts.Elements().FirstOrDefault(x => (string)x.Attribute("formatCode") == code);
                int id;
                if (hit != null && int.TryParse((string)hit.Attribute("numFmtId"), out id)) return id;
                id = ++maxId;
                numFmts.Add(new XElement(ns + "numFmt", new XAttribute("numFmtId", id), new XAttribute("formatCode", code)));
                return id;
            };
            int dateFmt = fmtId(ExcelUtil.DateFormatCode);
            int timeFmt = fmtId(ExcelUtil.TimeFormatCode);
            numFmts.SetAttributeValue("count", numFmts.Elements().Count());

            // bold font
            XElement fonts = EnsureChild(root, "fonts");
            XElement baseFont = fonts.Elements().FirstOrDefault();
            XElement bold = baseFont != null ? new XElement(baseFont) : new XElement(ns + "font", new XElement(ns + "sz", new XAttribute("val", "11")), new XElement(ns + "name", new XAttribute("val", "Calibri")));
            if (!bold.Elements().Any(x => x.Name.LocalName == "b")) bold.AddFirst(new XElement(ns + "b"));
            fonts.Add(bold);
            int boldId = fonts.Elements().Count() - 1;
            fonts.SetAttributeValue("count", fonts.Elements().Count());

            // fills / borders must have at least one entry for fillId/borderId 0
            XElement fills = EnsureChild(root, "fills");
            if (!fills.Elements().Any())
            {
                fills.Add(new XElement(ns + "fill", new XElement(ns + "patternFill", new XAttribute("patternType", "none"))));
                fills.Add(new XElement(ns + "fill", new XElement(ns + "patternFill", new XAttribute("patternType", "gray125"))));
                fills.SetAttributeValue("count", 2);
            }
            XElement borders = EnsureChild(root, "borders");
            if (!borders.Elements().Any())
            {
                borders.Add(new XElement(ns + "border", new XElement(ns + "left"), new XElement(ns + "right"), new XElement(ns + "top"), new XElement(ns + "bottom"), new XElement(ns + "diagonal")));
                borders.SetAttributeValue("count", 1);
            }
            XElement csx = EnsureChild(root, "cellStyleXfs");
            if (!csx.Elements().Any())
            {
                csx.Add(new XElement(ns + "xf", new XAttribute("numFmtId", 0), new XAttribute("fontId", 0), new XAttribute("fillId", 0), new XAttribute("borderId", 0)));
                csx.SetAttributeValue("count", 1);
            }
            XElement xfs = EnsureChild(root, "cellXfs");
            if (!xfs.Elements().Any())
                xfs.Add(new XElement(ns + "xf", new XAttribute("numFmtId", 0), new XAttribute("fontId", 0), new XAttribute("fillId", 0), new XAttribute("borderId", 0), new XAttribute("xfId", 0)));
            int first = xfs.Elements().Count();
            xfs.Add(new XElement(ns + "xf", new XAttribute("numFmtId", dateFmt), new XAttribute("fontId", 0), new XAttribute("fillId", 0), new XAttribute("borderId", 0), new XAttribute("xfId", 0), new XAttribute("applyNumberFormat", 1)));
            xfs.Add(new XElement(ns + "xf", new XAttribute("numFmtId", timeFmt), new XAttribute("fontId", 0), new XAttribute("fillId", 0), new XAttribute("borderId", 0), new XAttribute("xfId", 0), new XAttribute("applyNumberFormat", 1)));
            xfs.Add(new XElement(ns + "xf", new XAttribute("numFmtId", 0), new XAttribute("fontId", boldId), new XAttribute("fillId", 0), new XAttribute("borderId", 0), new XAttribute("xfId", 0), new XAttribute("applyFont", 1)));
            xfs.SetAttributeValue("count", xfs.Elements().Count());
            return new StyleIds { Date = first, Time = first + 1, Header = first + 2 };
        }
    }
}
