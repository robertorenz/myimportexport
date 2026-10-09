using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Xml;

namespace MIEConvert
{
    public static class XmlFormat
    {
        public static Table Read(string path, Options o)
        {
            var doc = new XmlDocument { PreserveWhitespace = true, XmlResolver = null };
            var settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Ignore, XmlResolver = null, IgnoreComments = true, IgnoreProcessingInstructions = true };
            string enc = (o.Encoding ?? "").Trim().ToLowerInvariant();
            if (enc == "" || enc == "auto")
            {
                using (var r = XmlReader.Create(path, settings)) doc.Load(r);
            }
            else
            {
                string text = TextEnc.ReadText(path, o.Encoding);
                using (var r = XmlReader.Create(new StringReader(text), settings)) doc.Load(r);
            }
            XmlElement root = doc.DocumentElement;
            if (root == null) throw new MieException("The XML file has no root element.");

            List<XmlElement> rows;
            if (!string.IsNullOrEmpty(o.RowPath))
            {
                rows = new List<XmlElement>();
                Collect(root, o.RowPath, rows);
                if (rows.Count == 0) throw new MieException("No <" + o.RowPath + "> elements found in the XML file.");
            }
            else rows = AutoRows(root);

            var t = new Table();
            var index = new Dictionary<string, int>(StringComparer.Ordinal);
            var data = new List<Dictionary<int, string>>();
            foreach (XmlElement e in rows)
            {
                if (o.MaxRows > 0 && data.Count >= o.MaxRows) break;
                var row = new Dictionary<int, string>();
                foreach (XmlAttribute a in e.Attributes)
                {
                    if (a.Prefix == "xmlns" || a.LocalName == "xmlns" && a.Prefix.Length == 0) continue;
                    Set(a.LocalName, a.Value, row, index, t.Columns);
                }
                bool hasChild = false;
                foreach (XmlNode n in e.ChildNodes)
                    if (n is XmlElement) { hasChild = true; AddElement((XmlElement)n, "", row, index, t.Columns); }
                if (!hasChild)
                {
                    string txt = e.InnerText;
                    if (txt.Trim().Length > 0 || e.Attributes.Count == 0) Set(e.LocalName, txt, row, index, t.Columns);
                }
                data.Add(row);
            }
            foreach (var row in data)
            {
                var r = new string[t.Columns.Count];
                for (int i = 0; i < r.Length; i++) { string v; r[i] = row.TryGetValue(i, out v) ? v : ""; }
                t.Rows.Add(r);
            }
            return t;
        }

        static void AddElement(XmlElement e, string prefix, Dictionary<int, string> row, Dictionary<string, int> index, List<string> cols)
        {
            string key = prefix + e.LocalName;
            bool hasChild = false;
            foreach (XmlNode n in e.ChildNodes)
                if (n is XmlElement) { hasChild = true; AddElement((XmlElement)n, key + ".", row, index, cols); }
            if (!hasChild)
            {
                int i;
                if (index.TryGetValue(key, out i) && row.ContainsKey(i)) return; // keep the first occurrence
                Set(key, e.InnerText, row, index, cols);
            }
        }

        static void Set(string key, string val, Dictionary<int, string> row, Dictionary<string, int> index, List<string> cols)
        {
            int i;
            if (!index.TryGetValue(key, out i)) { i = cols.Count; cols.Add(key); index[key] = i; }
            row[i] = val;
        }

        static void Collect(XmlElement e, string name, List<XmlElement> into)
        {
            foreach (XmlNode n in e.ChildNodes)
            {
                var c = n as XmlElement;
                if (c == null) continue;
                if (string.Equals(c.LocalName, name, StringComparison.Ordinal) || string.Equals(c.Name, name, StringComparison.Ordinal)) into.Add(c);
                else Collect(c, name, into);
            }
        }

        /// <summary>Finds the row element: the element name that repeats most often under one parent.
        /// Structured elements (with child elements or attributes) win over plain leaf elements;
        /// on equal counts the shallower group wins.</summary>
        static List<XmlElement> AutoRows(XmlElement root)
        {
            List<XmlElement> bestS = null, bestL = null;
            int depthS = int.MaxValue, depthL = int.MaxValue;
            Walk(root, 0, ref bestS, ref depthS, ref bestL, ref depthL);
            if (bestS != null && bestS.Count >= 2) return bestS;
            if (bestL != null && bestL.Count >= 2) return bestL;
            // no repetition: a single structured child of the root is one row, otherwise the root is the row
            var kids = new List<XmlElement>();
            foreach (XmlNode n in root.ChildNodes) if (n is XmlElement) kids.Add((XmlElement)n);
            if (kids.Count == 1 && IsStructured(kids[0])) return kids;
            if (kids.Count == 0 && root.Attributes.Count == 0 && root.InnerText.Trim().Length == 0) return new List<XmlElement>();
            return new List<XmlElement> { root };
        }

        static bool IsStructured(XmlElement e)
        {
            if (e.Attributes.Count > 0) return true;
            foreach (XmlNode n in e.ChildNodes) if (n is XmlElement) return true;
            return false;
        }

        static void Walk(XmlElement e, int depth, ref List<XmlElement> bestS, ref int depthS, ref List<XmlElement> bestL, ref int depthL)
        {
            var groups = new Dictionary<string, List<XmlElement>>(StringComparer.Ordinal);
            var order = new List<string>();
            foreach (XmlNode n in e.ChildNodes)
            {
                var c = n as XmlElement;
                if (c == null) continue;
                List<XmlElement> l;
                if (!groups.TryGetValue(c.Name, out l)) { groups[c.Name] = l = new List<XmlElement>(); order.Add(c.Name); }
                l.Add(c);
            }
            foreach (string name in order)
            {
                var g = groups[name];
                bool structured = false;
                foreach (var x in g) if (IsStructured(x)) { structured = true; break; }
                if (structured)
                {
                    if (bestS == null || g.Count > bestS.Count || (g.Count == bestS.Count && depth < depthS)) { bestS = g; depthS = depth; }
                }
                else if (bestL == null || g.Count > bestL.Count || (g.Count == bestL.Count && depth < depthL)) { bestL = g; depthL = depth; }
            }
            foreach (XmlNode n in e.ChildNodes)
                if (n is XmlElement) Walk((XmlElement)n, depth + 1, ref bestS, ref depthS, ref bestL, ref depthL);
        }

        /// <summary>Makes a valid XML element name: invalid characters become '_'; a name that cannot
        /// start an element (digit, '-', '.') gets a '_' prefix.</summary>
        public static string SafeName(string name)
        {
            name = (name ?? "").Trim();
            if (name.Length == 0) return "_";
            var sb = new StringBuilder(name.Length + 1);
            foreach (char c in name)
                sb.Append(XmlConvert.IsNCNameChar(c) ? c : '_');
            if (!XmlConvert.IsStartNCNameChar(sb[0])) sb.Insert(0, '_');
            return sb.ToString();
        }

        public static void Write(string path, Table t, Options o)
        {
            Encoding enc = TextEnc.ForOutput(o.Encoding);
            var settings = new XmlWriterSettings
            {
                Encoding = enc,
                Indent = true,
                IndentChars = "  ",
                NewLineChars = "\r\n",
                NewLineHandling = NewLineHandling.Entitize,
                CheckCharacters = true
            };
            string rootName = SafeName(string.IsNullOrEmpty(o.Root) ? "Data" : o.Root);
            string rowName = SafeName(string.IsNullOrEmpty(o.Row) ? "Row" : o.Row);
            var names = new string[t.Columns.Count];
            for (int i = 0; i < names.Length; i++) names[i] = SafeName(t.Columns[i]);
            using (var fs = new FileStream(path, FileMode.Create, FileAccess.Write))
            using (var w = XmlWriter.Create(fs, settings))
            {
                w.WriteStartDocument();
                w.WriteStartElement(rootName);
                foreach (var r in t.Rows)
                {
                    w.WriteStartElement(rowName);
                    for (int c = 0; c < names.Length; c++)
                    {
                        string v = r[c] ?? "";
                        if (t.TypeOf(c) == 'N') v = v.Trim();
                        w.WriteStartElement(names[c]);
                        if (v.Length > 0) w.WriteString(Values.XmlSafe(v));
                        w.WriteEndElement();
                    }
                    w.WriteEndElement();
                }
                w.WriteEndElement();
                w.WriteEndDocument();
            }
        }
    }
}
