using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;

namespace MIEConvert
{
    /// <summary>Thrown for user-facing errors (bad arguments, unreadable input, ...).</summary>
    public sealed class MieException : Exception
    {
        public MieException(string message) : base(message) { }
    }

    public sealed class Options
    {
        public string Command;
        public string Input;
        public string Output;
        public string Format;
        public string Sheet;
        public bool NoHeader;
        public bool ReplaceSheet;
        public string Delimiter;
        public string Encoding;
        public string RowPath;
        public int MaxRows = -1;
        public string ErrFile;
        public string Root;
        public string Row;
        public int CodePage = -1;

        public char DelimiterChar
        {
            get
            {
                if (string.IsNullOrEmpty(Delimiter)) return ',';
                string d = Delimiter;
                switch (d.ToLowerInvariant())
                {
                    case "tab": case "\\t": case "<9>": return '\t';
                    case "comma": return ',';
                    case "semicolon": return ';';
                    case "pipe": return '|';
                    case "space": return ' ';
                }
                if (d.Length == 1) return d[0];
                throw new MieException("Invalid delimiter '" + d + "'. Use , ; | or tab.");
            }
        }

        /// <summary>Encoding of the MIE-TSV intermediate file.</summary>
        public Encoding TsvEncoding
        {
            get
            {
                if (CodePage == 65001) return new UTF8Encoding(false);
                if (CodePage > 0) return TextEnc.FromCodePage(CodePage);
                return System.Text.Encoding.Default;
            }
        }
    }

    public static class Program
    {
        [STAThread]
        public static int Main(string[] args)
        {
            Thread.CurrentThread.CurrentCulture = CultureInfo.InvariantCulture;
            string errFile = PreScanErrFile(args);
            try
            {
                Options o = Parse(args);
                Run(o);
                return 0;
            }
            catch (Exception ex)
            {
                string msg = ex is MieException ? ex.Message : ex.GetType().Name + ": " + ex.Message;
                ReportError(errFile, msg);
                return 1;
            }
        }

        static string PreScanErrFile(string[] args)
        {
            for (int i = 0; i < args.Length - 1; i++)
                if (string.Equals(args[i], "--errfile", StringComparison.OrdinalIgnoreCase))
                    return args[i + 1];
            return null;
        }

        static void ReportError(string errFile, string msg)
        {
            try { Console.Error.WriteLine(msg); } catch { }
            if (!string.IsNullOrEmpty(errFile))
            {
                try { File.WriteAllText(errFile, msg + "\r\n", System.Text.Encoding.Default); } catch { }
            }
        }

        public const string Usage =
            "Usage:\r\n" +
            "  MIEConvert sheets <inputFile> <outFile> [--errfile f]\r\n" +
            "  MIEConvert import <inputFile> <outTsv> [--format f] [--sheet s] [--noheader] [--delimiter c]\r\n" +
            "                    [--encoding e] [--rowpath name] [--maxrows n] [--errfile f]\r\n" +
            "  MIEConvert export <inTsv> <outputFile> [--format f] [--sheet s] [--replacesheet] [--noheader]\r\n" +
            "                    [--delimiter c] [--encoding e] [--root name] [--row name] [--errfile f]";

        static Options Parse(string[] args)
        {
            var o = new Options();
            var pos = new List<string>();
            for (int i = 0; i < args.Length; i++)
            {
                string a = args[i];
                if (a.StartsWith("--", StringComparison.Ordinal) && a.Length > 2)
                {
                    string name = a.Substring(2).ToLowerInvariant();
                    string val = null;
                    int eq = name.IndexOf('=');
                    if (eq > 0) { val = a.Substring(2 + eq + 1); name = name.Substring(0, eq); }
                    switch (name)
                    {
                        case "noheader": o.NoHeader = true; continue;
                        case "replacesheet": o.ReplaceSheet = true; continue;
                    }
                    if (val == null)
                    {
                        if (i + 1 >= args.Length) throw new MieException("Missing value for --" + name + "\r\n" + Usage);
                        val = args[++i];
                    }
                    switch (name)
                    {
                        case "format": o.Format = val.Trim().TrimStart('.').ToLowerInvariant(); break;
                        case "sheet": o.Sheet = val; break;
                        case "delimiter": o.Delimiter = val; break;
                        case "encoding": o.Encoding = val.Trim(); break;
                        case "rowpath": o.RowPath = val.Trim(); break;
                        case "maxrows":
                            int n;
                            if (!int.TryParse(val.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out n))
                                throw new MieException("Invalid --maxrows value '" + val + "'");
                            o.MaxRows = n <= 0 ? -1 : n;
                            break;
                        case "errfile": o.ErrFile = val; break;
                        case "root": o.Root = val.Trim(); break;
                        case "row": o.Row = val.Trim(); break;
                        case "codepage":
                            int cp;
                            if (!int.TryParse(val.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out cp))
                                throw new MieException("Invalid --codepage value '" + val + "'");
                            o.CodePage = cp;
                            break;
                        default: throw new MieException("Unknown option --" + name + "\r\n" + Usage);
                    }
                }
                else pos.Add(a);
            }
            if (pos.Count < 3) throw new MieException("Missing arguments.\r\n" + Usage);
            if (pos.Count > 3) throw new MieException("Too many arguments: '" + pos[3] + "' (quote paths that contain spaces).\r\n" + Usage);
            o.Command = pos[0].ToLowerInvariant();
            o.Input = pos[1];
            o.Output = pos[2];
            return o;
        }

        static string FormatOf(Options o, string file)
        {
            string f = o.Format;
            if (string.IsNullOrEmpty(f))
            {
                f = Path.GetExtension(file).TrimStart('.').ToLowerInvariant();
                if (f == "txt") f = "csv";
                if (f == "tab") f = "tsv";
                if (f == "xlsm") f = "xlsx";
            }
            switch (f)
            {
                case "csv": case "tsv": case "json": case "xml": case "xls": case "xlsx": return f;
            }
            throw new MieException("Unknown or unsupported format '" + f + "' for file " + file + ". Use --format csv|tsv|json|xml|xls|xlsx.");
        }

        static void Run(Options o)
        {
            switch (o.Command)
            {
                case "sheets": RunSheets(o); break;
                case "import": RunImport(o); break;
                case "export": RunExport(o); break;
                default: throw new MieException("Unknown command '" + o.Command + "'.\r\n" + Usage);
            }
        }

        static void RequireInput(string path)
        {
            if (!File.Exists(path)) throw new MieException("File not found: " + path);
        }

        static void RunSheets(Options o)
        {
            RequireInput(o.Input);
            string fmt = FormatOf(o, o.Input);
            List<string> names;
            if (fmt == "xlsx") names = XlsxFormat.SheetNames(o.Input);
            else if (fmt == "xls") names = XlsFormat.SheetNames(o.Input);
            else throw new MieException("The sheets command supports xls and xlsx files only.");
            using (var w = new StreamWriter(o.Output, false, o.TsvEncoding))
            {
                w.NewLine = "\r\n";
                foreach (string n in names) w.WriteLine(MieTsv.Escape(n));
            }
        }

        static void RunImport(Options o)
        {
            RequireInput(o.Input);
            string fmt = FormatOf(o, o.Input);
            Table t;
            switch (fmt)
            {
                case "csv": t = CsvFormat.Read(o.Input, o, o.DelimiterChar); break;
                case "tsv": t = CsvFormat.Read(o.Input, o, '\t'); break;
                case "json": t = JsonFormat.Read(o.Input, o); break;
                case "xml": t = XmlFormat.Read(o.Input, o); break;
                case "xlsx": t = XlsxFormat.Read(o.Input, o); break;
                case "xls": t = XlsFormat.Read(o.Input, o); break;
                default: throw new MieException("Unsupported format " + fmt);
            }
            t.Normalize();
            MieTsv.WriteImport(o.Output, t, o.TsvEncoding);
        }

        static void RunExport(Options o)
        {
            RequireInput(o.Input);
            string fmt = FormatOf(o, o.Output);
            Table t = MieTsv.ReadExport(o.Input, o.TsvEncoding);
            string dir = Path.GetDirectoryName(Path.GetFullPath(o.Output));
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir)) Directory.CreateDirectory(dir);
            switch (fmt)
            {
                case "csv": CsvFormat.Write(o.Output, t, o, o.DelimiterChar); break;
                case "tsv": CsvFormat.Write(o.Output, t, o, '\t'); break;
                case "json": JsonFormat.Write(o.Output, t, o); break;
                case "xml": XmlFormat.Write(o.Output, t, o); break;
                case "xlsx": XlsxFormat.Write(o.Output, t, o); break;
                case "xls": XlsFormat.Write(o.Output, t, o); break;
                default: throw new MieException("Unsupported format " + fmt);
            }
        }
    }
}
