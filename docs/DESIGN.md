# MyImportExport – Design Contract

Three parts, built independently, wired together by this contract.

```
 AppGen template (template\win\MyImportExport.tpl/.tpw)
   └─ generates, per dictionary table, AddField() calls + ABC/Legacy file hooks
        └─ Clarion class MyImportExportClass (libsrc\win\MyImportExport.inc/.clw)
             ├─ mapping window (choose columns, align to fields, choose sheet)
             ├─ reads/writes the MIE-TSV intermediate file
             └─ RUN()s the helper
                  └─ MIEConvert.exe (helper\MIEConvert, C# .NET Framework 4.8)
                       csv / tsv / json / xml / xls / xlsx  <->  MIE-TSV
```

## 1. MIE-TSV intermediate file

* Encoding: Windows ANSI (`Encoding.Default`, override with `--codepage n`). CRLF line ends.
* Fields separated by TAB (`<9>`). Inside a field these escapes are used:
  `\\` = backslash, `\t` = TAB, `\n` = LF, `\r` = CR. Nothing else is escaped.
* Line 1 = column names.
* **Export only** (Clarion -> helper): line 2 = column types, one code per column:
  `S` string, `N` number, `D` date (`yyyy-mm-dd`), `T` time (`hh:mm:ss`).
* Remaining lines = data rows. Empty field = empty string.
* Numbers use `.` as decimal separator, no thousands separator.

## 2. MIEConvert.exe command line

WinExe (no console window). Exit code 0 = success, 1 = error. On error the message is
written to the file named by `--errfile` (if given) and to stderr.

```
MIEConvert sheets <inputFile> <outFile> [--errfile f]
    outFile: one sheet name per line (ANSI). xls/xlsx only.

MIEConvert import <inputFile> <outTsv> [options]
    --format csv|tsv|json|xml|xls|xlsx   (default: from extension)
    --sheet <name>          Excel sheet (default: first sheet)
    --noheader              first row is data; columns are named Column1..ColumnN
    --delimiter <c>         csv: , ; | tab   (default ,)
    --encoding auto|utf8|ansi|<codepage>  text input (default auto: BOM, else valid UTF-8, else ANSI)
    --rowpath <name>        xml: element name of a row (default: auto-detect repeating element)
                            json: property name holding the array (default: root array or first array)
    --maxrows <n>           stop after n data rows (preview / column discovery)
    --errfile <f>

MIEConvert export <inTsv> <outputFile> [options]
    --format csv|tsv|json|xml|xls|xlsx   (default: from extension)
    --sheet <name>          default Sheet1
    --replacesheet          xlsx: if the file exists keep its other sheets, add/replace this one
    --noheader              do not write a header row (csv/tsv/xls/xlsx)
    --delimiter <c>         csv
    --encoding utf8|utf8bom|ansi|<codepage>   text output (default utf8bom)
    --root <name>           xml root element (default Data); json: wrap array in {"name":[...]}
    --row <name>            xml row element (default Row)
    --errfile <f>
```

Import rules: JSON array of objects -> columns are the union of keys in first-seen order,
nested objects flattened as `parent.child`, arrays emitted as JSON text. XML rows: attributes
+ child element text. Excel dates -> `yyyy-mm-dd`, `yyyy-mm-dd hh:mm:ss`, or `hh:mm:ss`.
Excel numbers -> invariant culture.

Export rules: `N` columns become numeric cells / unquoted JSON numbers (empty -> blank / null),
`D` -> real Excel date cells (format yyyy-mm-dd), `T` -> Excel time cells (hh:mm:ss).
XML element names are sanitised (invalid chars -> `_`).

## 3. Clarion class (libsrc\win\MyImportExport.inc)

See the .inc for the authoritative declaration. Key API used by generated code:

```clarion
MIE              MyImportExportClass
  CODE
  MIE.Init()
  MIE.SetTable(Customer, 'Customer', CUS:KeyCustNumber)   ! key optional
  MIE.AddField('CUS:CustNumber','CustNumber','LONG','@n_10',CUS:CustNumber,1)
  MIE.AddField('CUS:Name','Name','STRING','@s40',CUS:Name,0)
  ...
  MIE.Ask()            ! full UI   – or MIE.Export() / MIE.Import() for no UI
  MIE.Kill()
```

Virtual hooks (derive to use ABC FileManager / add rules):

| Method | Default (raw driver) | Purpose |
|---|---|---|
| `OpenTable(),BYTE` | SHARE (CREATE if missing on import) unless already open | return 0 = ok |
| `CloseTable()` | CLOSE if we opened it | |
| `PrimeRecord()` | nothing | before field assignment on insert, only when no key field is mapped |
| `CancelPrime()` | nothing | insert failed after PrimeRecord |
| `InsertRecord(),BYTE` | ADD | 0 = ok |
| `UpdateRecord(),BYTE` | PUT | 0 = ok |
| `FetchRecord(),BYTE` | GET(file,key) | 0 = found |
| `DeleteRecord(),BYTE` | DELETE | used by "replace all" |
| `ValidateRecord(),BYTE` | 0 | import: non-zero = skip row |
| `ExportFilter(),BYTE` | 1 | export: 0 = skip record |
| `TakeProgress(LONG done)` | updates progress | |

Import modes: 1 Add, 2 Add or update (by primary key), 3 Update existing only, 4 Replace all.
