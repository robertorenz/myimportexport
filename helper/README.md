# MIEConvert

`MIEConvert.exe` is the format converter used by the MyImportExport Clarion class. It turns
csv / tsv / json / xml / xls / xlsx files into the MIE-TSV intermediate file (import) and back
(export). The contract (file layout and command line) is in [`docs/DESIGN.md`](../docs/DESIGN.md)
sections 1 and 2.

* .NET Framework 4.8, `WinExe` (no console window when Clarion `RUN()`s it), AnyCPU.
* One file, no extra DLLs: only the .NET Framework class library is used. xlsx is read and written
  with `System.IO.Compression` + `System.Xml`; xls (BIFF8 in an OLE2 compound file) is read and
  written by our own code.
* The shipped copy is `bin\MIEConvert.exe` at the repository root.

## Build

```bat
cd helper\MIEConvert
dotnet build -c Release
copy /y bin\Release\net48\MIEConvert.exe ..\..\bin\MIEConvert.exe
```

Requires the .NET SDK (6 or later). The `Microsoft.NETFramework.ReferenceAssemblies` package is
restored from NuGet automatically, so the .NET Framework targeting pack is not needed.

## Usage

```text
MIEConvert sheets <inputFile> <outFile> [--errfile f]
MIEConvert import <inputFile> <outTsv> [--format f] [--sheet s] [--noheader] [--delimiter c]
                  [--encoding auto|utf8|ansi|<codepage>] [--rowpath name] [--maxrows n] [--errfile f]
MIEConvert export <inTsv> <outputFile> [--format f] [--sheet s] [--replacesheet] [--noheader]
                  [--delimiter c] [--encoding utf8|utf8bom|ansi|<codepage>] [--root name] [--row name]
                  [--errfile f]
```

Exit code 0 = success, 1 = error (message in `--errfile` and on stderr). The MIE-TSV file is ANSI
(`Encoding.Default`); `--codepage n` overrides it on any command.

Examples:

```bat
MIEConvert sheets  C:\in\book.xlsx  C:\tmp\sheets.txt
MIEConvert import  C:\in\book.xlsx  C:\tmp\data.tsv --sheet "Customers" --maxrows 20
MIEConvert import  C:\in\data.csv   C:\tmp\data.tsv --delimiter ; --encoding auto
MIEConvert import  C:\in\feed.json  C:\tmp\data.tsv --rowpath items
MIEConvert export  C:\tmp\data.tsv  C:\out\cust.xlsx --sheet Customers --replacesheet
MIEConvert export  C:\tmp\data.tsv  C:\out\cust.xml  --root Customers --row Customer
```

### Behaviour notes

| Area | Behaviour |
|---|---|
| CSV / TSV import | RFC 4180: quoted fields, doubled quotes, line breaks inside quotes. Blank lines are skipped. Encoding auto = BOM (UTF-8/UTF-16/UTF-32), else strict UTF-8, else ANSI. |
| CSV / TSV export | Fields are quoted only when they contain the delimiter, a quote, CR or LF. TSV uses the same quoting with TAB as delimiter. |
| JSON import | Rows = root array, else `--rowpath` (property name searched anywhere, or a dotted path such as `data.items`), else the first array in document order. Nested objects become `parent.child` columns; arrays are kept as compact JSON text; `true`/`false` become `1`/`0`; `null` becomes empty. A root array of arrays is read like CSV rows; an array of scalars gives one `Value` column. |
| JSON export | Array of objects (pretty printed), `--root name` wraps it as `{"name":[...]}`. `N` columns are JSON numbers (empty = `null`); everything else is a string. With a non-Unicode `--encoding`, non-ASCII characters are written as `\uXXXX`. |
| XML import | Row element = `--rowpath`, else auto-detected: the element name that repeats most often under one parent (structured elements with children or attributes are preferred over plain leaf elements). Columns = row attributes + child element text; deeper elements become `parent.child`. |
| XML export | `<Data><Row><Col>value</Col>...</Row></Data>`. Invalid name characters become `_`; a name that cannot start an element (e.g. a leading digit) gets a `_` prefix. CR is written as `&#xD;` so it survives parsing. |
| Excel import | First non-empty row is the header (unless `--noheader`); completely empty rows are skipped; sparse cells are placed by their reference. Dates: built-in formats 14-22, 45-47 and custom formats with d/m/y/h/s outside quotes and brackets give `yyyy-mm-dd`, `hh:mm:ss` or `yyyy-mm-dd hh:mm:ss`. Booleans are `1`/`0`, formulas give their cached value, error cells give their text (`#DIV/0!`). Numbers use the invariant culture, shortest round-trip form (12.5, 3, 0.0000001). The 1904 date system is honoured. |
| Excel export | Bold header row, `N` = numeric cells, `D` = date cells (`yyyy-mm-dd`), `T` = time cells (`hh:mm:ss`); values that do not parse are written as text. xlsx freezes the header row and sizes the columns. xls is limited to 65536 rows x 256 columns (an error tells the user to use xlsx). |
| `--replacesheet` | xlsx only: the existing package is opened, the sheet is added or replaced (workbook.xml, workbook.xml.rels, [Content_Types].xml updated, our three cell styles merged into the existing styles.xml, calcChain dropped so Excel rebuilds it); all other sheets stay intact. Without it, or for other formats, the file is overwritten. |
| Column names | Empty header cells become `ColumnN`; duplicate names get `_2`, `_3`... |

## Tests

`helper\tests\run_tests.py` round-trips a dataset with commas, quotes, tabs, CR/LF, backslashes,
accented characters, empty values, numbers, dates and times through every format, checks the
xlsx/xls output with openpyxl and xlrd, reads files written by openpyxl, xlwt and a hand-built
OpenXML package, and tests `--replacesheet`, `sheets`, `--noheader`, `--maxrows`, `--rowpath`,
XML auto-detection, encodings and error reporting.

```bat
python -m venv %TEMP%\mievenv
%TEMP%\mievenv\Scripts\pip install openpyxl xlrd xlwt
%TEMP%\mievenv\Scripts\python helper\tests\run_tests.py            REM tests bin\MIEConvert.exe
%TEMP%\mievenv\Scripts\python helper\tests\run_tests.py path\to\MIEConvert.exe
```
