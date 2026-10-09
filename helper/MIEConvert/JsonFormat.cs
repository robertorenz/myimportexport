using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace MIEConvert
{
    /// <summary>Minimal JSON DOM: JObject (ordered), List&lt;object&gt;, string, JNumber, bool, null.</summary>
    public sealed class JObject
    {
        public readonly List<KeyValuePair<string, object>> Props = new List<KeyValuePair<string, object>>();
    }

    public sealed class JNumber
    {
        public readonly string Raw;
        public JNumber(string raw) { Raw = raw; }
    }

    public sealed class JsonParser
    {
        readonly string s;
        int p;

        JsonParser(string text) { s = text; }

        public static object Parse(string text)
        {
            var jp = new JsonParser(text);
            jp.Ws();
            if (jp.p < jp.s.Length && jp.s[jp.p] == '﻿') { jp.p++; jp.Ws(); }
            object v = jp.Value();
            jp.Ws();
            if (jp.p < jp.s.Length) throw jp.Err("Unexpected text after the JSON value");
            return v;
        }

        Exception Err(string msg)
        {
            int line = 1, col = 1;
            for (int i = 0; i < p && i < s.Length; i++) { if (s[i] == '\n') { line++; col = 1; } else col++; }
            return new MieException("Invalid JSON: " + msg + " at line " + line + ", column " + col);
        }

        void Ws()
        {
            while (p < s.Length)
            {
                char c = s[p];
                if (c == ' ' || c == '\t' || c == '\r' || c == '\n') p++;
                else if (c == '/' && p + 1 < s.Length && s[p + 1] == '/') { while (p < s.Length && s[p] != '\n') p++; }
                else if (c == '/' && p + 1 < s.Length && s[p + 1] == '*') { int e = s.IndexOf("*/", p + 2, StringComparison.Ordinal); p = e < 0 ? s.Length : e + 2; }
                else break;
            }
        }

        object Value()
        {
            if (p >= s.Length) throw Err("Unexpected end of input");
            char c = s[p];
            switch (c)
            {
                case '{': return Obj();
                case '[': return Arr();
                case '"': return Str();
                case 't': Lit("true"); return true;
                case 'f': Lit("false"); return false;
                case 'n': Lit("null"); return null;
            }
            if (c == '-' || (c >= '0' && c <= '9')) return Num();
            throw Err("Unexpected character '" + c + "'");
        }

        void Lit(string w)
        {
            if (string.CompareOrdinal(s, p, w, 0, w.Length) != 0) throw Err("Expected " + w);
            p += w.Length;
        }

        JObject Obj()
        {
            var o = new JObject();
            p++;
            Ws();
            if (p < s.Length && s[p] == '}') { p++; return o; }
            while (true)
            {
                Ws();
                if (p >= s.Length || s[p] != '"') throw Err("Expected property name");
                string k = Str();
                Ws();
                if (p >= s.Length || s[p] != ':') throw Err("Expected ':'");
                p++;
                Ws();
                object v = Value();
                o.Props.Add(new KeyValuePair<string, object>(k, v));
                Ws();
                if (p < s.Length && s[p] == ',') { p++; Ws(); if (p < s.Length && s[p] == '}') { p++; return o; } continue; }
                if (p < s.Length && s[p] == '}') { p++; return o; }
                throw Err("Expected ',' or '}'");
            }
        }

        List<object> Arr()
        {
            var a = new List<object>();
            p++;
            Ws();
            if (p < s.Length && s[p] == ']') { p++; return a; }
            while (true)
            {
                Ws();
                a.Add(Value());
                Ws();
                if (p < s.Length && s[p] == ',') { p++; Ws(); if (p < s.Length && s[p] == ']') { p++; return a; } continue; }
                if (p < s.Length && s[p] == ']') { p++; return a; }
                throw Err("Expected ',' or ']'");
            }
        }

        string Str()
        {
            p++;
            var sb = new StringBuilder();
            while (true)
            {
                if (p >= s.Length) throw Err("Unterminated string");
                char c = s[p++];
                if (c == '"') return sb.ToString();
                if (c != '\\') { sb.Append(c); continue; }
                if (p >= s.Length) throw Err("Unterminated string");
                char e = s[p++];
                switch (e)
                {
                    case '"': sb.Append('"'); break;
                    case '\\': sb.Append('\\'); break;
                    case '/': sb.Append('/'); break;
                    case 'b': sb.Append('\b'); break;
                    case 'f': sb.Append('\f'); break;
                    case 'n': sb.Append('\n'); break;
                    case 'r': sb.Append('\r'); break;
                    case 't': sb.Append('\t'); break;
                    case 'u':
                        if (p + 4 > s.Length) throw Err("Bad \\u escape");
                        sb.Append((char)int.Parse(s.Substring(p, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture));
                        p += 4;
                        break;
                    default: throw Err("Bad escape \\" + e);
                }
            }
        }

        JNumber Num()
        {
            int st = p;
            if (s[p] == '-') p++;
            while (p < s.Length && "0123456789.eE+-".IndexOf(s[p]) >= 0) p++;
            return new JNumber(s.Substring(st, p - st));
        }
    }

    public static class JsonFormat
    {
        public static Table Read(string path, Options o)
        {
            string text = TextEnc.ReadText(path, o.Encoding);
            object root = JsonParser.Parse(text);
            List<object> arr = FindRows(root, o.RowPath);
            var t = new Table();
            if (arr == null)
            {
                if (root is JObject && string.IsNullOrEmpty(o.RowPath)) arr = new List<object> { root };
                else throw new MieException(string.IsNullOrEmpty(o.RowPath)
                    ? "No array of rows found in the JSON file."
                    : "No array named '" + o.RowPath + "' found in the JSON file.");
            }

            // array of arrays: like CSV rows
            bool allArrays = arr.Count > 0;
            foreach (object x in arr) if (!(x is List<object>)) { allArrays = false; break; }
            if (allArrays)
            {
                var raw = new List<string[]>();
                foreach (object x in arr)
                {
                    var l = (List<object>)x;
                    var r = new string[l.Count];
                    for (int i = 0; i < l.Count; i++) r[i] = Scalar(l[i]);
                    raw.Add(r);
                }
                return Table.FromRawRows(raw, o.NoHeader, o.MaxRows);
            }

            var index = new Dictionary<string, int>(StringComparer.Ordinal);
            var rows = new List<Dictionary<int, string>>();
            foreach (object x in arr)
            {
                if (o.MaxRows > 0 && rows.Count >= o.MaxRows) break;
                var row = new Dictionary<int, string>();
                if (x is JObject)
                    Flatten((JObject)x, "", row, index, t.Columns);
                else
                    Set("Value", Scalar(x), row, index, t.Columns);
                rows.Add(row);
            }
            foreach (var row in rows)
            {
                var r = new string[t.Columns.Count];
                for (int i = 0; i < r.Length; i++) { string v; r[i] = row.TryGetValue(i, out v) ? v : ""; }
                t.Rows.Add(r);
            }
            return t;
        }

        static void Set(string key, string val, Dictionary<int, string> row, Dictionary<string, int> index, List<string> cols)
        {
            int i;
            if (!index.TryGetValue(key, out i)) { i = cols.Count; cols.Add(key); index[key] = i; }
            row[i] = val;
        }

        static void Flatten(JObject o, string prefix, Dictionary<int, string> row, Dictionary<string, int> index, List<string> cols)
        {
            foreach (var kv in o.Props)
            {
                string key = prefix + kv.Key;
                if (kv.Value is JObject) Flatten((JObject)kv.Value, key + ".", row, index, cols);
                else Set(key, Scalar(kv.Value), row, index, cols);
            }
        }

        static string Scalar(object v)
        {
            if (v == null) return "";
            if (v is string) return (string)v;
            if (v is bool) return (bool)v ? "1" : "0";
            if (v is JNumber)
            {
                string raw = ((JNumber)v).Raw;
                if (raw.IndexOf('e') >= 0 || raw.IndexOf('E') >= 0)
                {
                    double d;
                    if (double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out d)) return Values.FormatNumber(d);
                }
                return raw;
            }
            var sb = new StringBuilder();
            WriteCompact(sb, v);
            return sb.ToString();
        }

        static List<object> FindRows(object root, string rowPath)
        {
            if (string.IsNullOrEmpty(rowPath))
            {
                if (root is List<object>) return (List<object>)root;
                return FirstArray(root);
            }
            // dotted path from the root first, then search by property name
            if (rowPath.IndexOf('.') >= 0)
            {
                object cur = root;
                foreach (string part in rowPath.Split('.'))
                {
                    var jo = cur as JObject;
                    cur = null;
                    if (jo == null) break;
                    foreach (var kv in jo.Props) if (kv.Key == part) { cur = kv.Value; break; }
                }
                if (cur is List<object>) return (List<object>)cur;
            }
            return FindNamed(root, rowPath);
        }

        static List<object> FirstArray(object v)
        {
            // depth-first, in document order
            var jo = v as JObject;
            if (jo == null) return null;
            foreach (var kv in jo.Props)
            {
                if (kv.Value is List<object>) return (List<object>)kv.Value;
                var r = FirstArray(kv.Value);
                if (r != null) return r;
            }
            return null;
        }

        static List<object> FindNamed(object v, string name)
        {
            var jo = v as JObject;
            if (jo != null)
            {
                foreach (var kv in jo.Props)
                    if (string.Equals(kv.Key, name, StringComparison.Ordinal) && kv.Value is List<object>) return (List<object>)kv.Value;
                foreach (var kv in jo.Props)
                    if (string.Equals(kv.Key, name, StringComparison.OrdinalIgnoreCase) && kv.Value is List<object>) return (List<object>)kv.Value;
                foreach (var kv in jo.Props)
                {
                    var r = FindNamed(kv.Value, name);
                    if (r != null) return r;
                }
                return null;
            }
            var arr = v as List<object>;
            if (arr != null)
                foreach (object x in arr)
                {
                    var r = FindNamed(x, name);
                    if (r != null) return r;
                }
            return null;
        }

        static void WriteCompact(StringBuilder sb, object v)
        {
            if (v == null) { sb.Append("null"); return; }
            if (v is string) { WriteString(sb, (string)v, false); return; }
            if (v is bool) { sb.Append((bool)v ? "true" : "false"); return; }
            if (v is JNumber) { sb.Append(((JNumber)v).Raw); return; }
            if (v is List<object>)
            {
                sb.Append('[');
                bool first = true;
                foreach (object x in (List<object>)v) { if (!first) sb.Append(','); first = false; WriteCompact(sb, x); }
                sb.Append(']');
                return;
            }
            var o = (JObject)v;
            sb.Append('{');
            bool f2 = true;
            foreach (var kv in o.Props)
            {
                if (!f2) sb.Append(','); f2 = false;
                WriteString(sb, kv.Key, false);
                sb.Append(':');
                WriteCompact(sb, kv.Value);
            }
            sb.Append('}');
        }

        static void WriteString(StringBuilder sb, string s, bool asciiOnly)
        {
            sb.Append('"');
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    case '\b': sb.Append("\\b"); break;
                    case '\f': sb.Append("\\f"); break;
                    default:
                        if (c < 0x20 || (asciiOnly && c > 0x7E) || c == (char)0x2028 || c == (char)0x2029)
                            sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                        else sb.Append(c);
                        break;
                }
            }
            sb.Append('"');
        }

        public static void Write(string path, Table t, Options o)
        {
            Encoding enc = TextEnc.ForOutput(o.Encoding);
            bool ascii = !TextEnc.IsUnicode(enc);
            using (var w = new StreamWriter(path, false, enc, 1 << 16))
            {
                w.NewLine = "\r\n";
                string ind = "  ";
                if (!string.IsNullOrEmpty(o.Root))
                {
                    var sbr = new StringBuilder();
                    WriteString(sbr, o.Root, ascii);
                    w.Write("{\r\n  " + sbr + ": ");
                    ind = "    ";
                }
                w.Write("[");
                var sb = new StringBuilder();
                var keys = new string[t.Columns.Count];
                for (int i = 0; i < keys.Length; i++) { sb.Clear(); WriteString(sb, t.Columns[i], ascii); keys[i] = sb.ToString(); }
                for (int r = 0; r < t.Rows.Count; r++)
                {
                    sb.Clear();
                    sb.Append(r == 0 ? "\r\n" : ",\r\n").Append(ind).Append('{');
                    string[] row = t.Rows[r];
                    for (int c = 0; c < keys.Length; c++)
                    {
                        if (c > 0) sb.Append(',');
                        sb.Append("\r\n").Append(ind).Append("  ").Append(keys[c]).Append(": ");
                        string v = row[c] ?? "";
                        if (t.TypeOf(c) == 'N')
                        {
                            if (v.Trim().Length == 0) { sb.Append("null"); continue; }
                            string num = Values.NormalizeNumberText(v);
                            if (num != null) { sb.Append(num); continue; }
                        }
                        WriteString(sb, v, ascii);
                    }
                    sb.Append("\r\n").Append(ind).Append('}');
                    w.Write(sb.ToString());
                }
                if (t.Rows.Count > 0) w.Write("\r\n" + ind.Substring(2));
                w.Write("]");
                if (!string.IsNullOrEmpty(o.Root)) w.Write("\r\n}");
                w.Write("\r\n");
            }
        }
    }
}
