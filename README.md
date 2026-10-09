# MyImportExport

A Clarion 12 template set that imports and exports **any table in your dictionary** to and from
**CSV, TSV, JSON, XML, XLSX and XLS**. You pick the file and the format, choose an Excel sheet,
tick the columns you want and match each source column to a table field. Mappings are saved per
table, so the next run is one click.

```
 AppGen template (template\MyImportExport.tpl/.tpw)
   └─ generates MIE_ImportExport(table, mode) with AddField() calls for every dictionary table
        └─ MyImportExportClass (libsrc\MyImportExport.inc/.clw)
             ├─ mapping window: format, file, sheet, columns, field alignment, import mode
             └─ RUN()s MIEConvert.exe (bin\, single 110 KB exe, .NET Framework 4.8)
                  csv / tsv / json / xml / xls / xlsx  <->  intermediate tab file
```

Excel does **not** need to be installed: MIEConvert reads and writes .xlsx (OpenXML) and
.xls (BIFF8) itself.

## Install

```powershell
pwsh .\install.ps1                 # or -ClarionRoot D:\clarion12
```

This copies the template to `accessory\template\win`, the class to `accessory\libsrc\win` and
`MIEConvert.exe` to `accessory\bin`, then registers the template. Restart the IDE if it is open.

## Use it in an app

1. **Global extension** `MyImportExportGlobal` (add it to every app in a multi-DLL suite).
   Settings: helper path, INI file for saved mappings, default format, tables to exclude,
   "copy the helper to the output folder", delete mode for *Replace all*.
2. Then either:
   - **Control template** `MyImportExportButtons` on a browse: *Import...* / *Export...* buttons
     (or one button with a menu). The browse refreshes after an import.
   - **Code template** `MyImportExportCall`: a chosen table, the primary table, or a table picker.
   - Or call the generated procedure from your own code:

```clarion
  MIE_ImportExport('Customer', MIE:Mode:Import)   ! mode 0 = let the user choose
  MIE_ImportExport('')                            ! shows a table picker first
```

Ship `MIEConvert.exe` next to your program's exe.

### The window

| Area | What it does |
|---|---|
| Action | Export or Import |
| Format / File | the format follows the file extension; `...` opens a file dialog |
| Sheet | xls / xlsx: pick an existing sheet (import) or name one (export) |
| First row contains column names | csv / tsv / xls / xlsx |
| Delimiter | csv: comma, semicolon, tab, pipe |
| Root / Row / Array | xml element names, json array property (blank = auto-detect on import) |
| Import mode | Add new · Add or update (by primary key) · Update existing only · Replace all |
| Format with dictionary pictures | export dates / numbers as they are shown in the app |
| Keep other sheets | xlsx export: add or replace only this sheet in an existing workbook |
| Field list | tick fields (double-click / Space), set the source column or column header, reorder with Move Up / Down, **Auto Map** matches by name |
| Save Mapping | remembers everything for this table (INI) |

### Field rules

- Every field of every table is offered except GROUP markers, MEMO, BLOB, fields declared `OVER()`,
  and fields or tables whose **dictionary User Options contain `MIEEXCLUDE`**.
  ALIAS tables are skipped (the real table is offered instead).
- `DIM()` arrays become one column per element (`Phones_1`, `Phones_2`, ...).
- Column names come from the external `NAME()` when set, otherwise the label without its prefix.
- Dates are written as `yyyy-mm-dd`, times as `hh:mm:ss`, numbers with a `.` decimal point. In Excel
  they become real date, time and number cells. On import, ISO dates, `yyyymmdd`, Excel dates and the
  field's own picture are all understood.
- Auto-increment keys: if you map the key column, the imported IDs are kept. If you don't, ABC
  numbers the new records.

### Embeds

The generated procedure has embeds before and after the window, plus one in every hook.
`ValidateRecord` (return non-zero to skip a row) and `ExportFilter` (return 0 to skip a record)
are available for all tables and per table.

## Use the class directly (no template)

```clarion
MIE   MyImportExportClass
  CODE
  MIE.Init()
  MIE.SetTable(Customer, 'Customer', CUS:KeyId)
  MIE.AddField('CUS:Id',   'Id',   'LONG',   '@n_10', CUS:Id, 1)
  MIE.AddField('CUS:Name', 'Name', 'STRING', '@s40',  CUS:Name)
  MIE.Ask()                        ! full window
  ! ...or no window:
  MIE.Format = 'XLSX'; MIE.FileName = 'c:\temp\cust.xlsx'; MIE.SheetName = 'Customers'
  MIE.Export()
  MIE.LoadColumns(); MIE.AutoMap(); MIE.Import()   ! LoadColumns + AutoMap before Import
  MIE.Kill()
```

Derive the class to change table I/O (`OpenTable`, `InsertRecord`, `UpdateRecord`, `FetchRecord`,
`DeleteRecord`, `PrimeRecord`, ...). The template does exactly that to use ABC's
`Access:`/`Relate:` objects.

## Limits

- **Keep other sheets** works for .xlsx only. Other formats overwrite the file.
- .xls export stops above 65,536 rows / 256 columns (use .xlsx).
- The intermediate file is Windows ANSI, so characters outside the current code page become `?`
  (set `MIE.Encoding` / `--codepage` to change it).
- MEMO and BLOB fields are not imported or exported.

## Repository

| Folder | Contents |
|---|---|
| `template\` | `MyImportExport.tpl`, `MyImportExport.tpw` |
| `libsrc\` | `MyImportExport.inc`, `MyImportExport.clw` |
| `bin\` | `MIEConvert.exe` (built) |
| `helper\MIEConvert\` | C# source of the helper (`dotnet build -c Release`), see `helper\README.md` |
| `helper\tests\` | helper round-trip tests (`python run_tests.py`, needs openpyxl, xlrd, xlwt) |
| `test\` | headless Clarion test: `pwsh test\build.ps1` exports and re-imports every format |
| `example\` | demo dictionary (`.dctx`) and app (`.txa`) using all three templates |
| `docs\DESIGN.md` | contract between the template, the class and the helper |

## Tests

- `pwsh test\build.ps1`: all six formats round-trip through the Clarion class with 0 differences,
  and add-or-update import works.
- `helper\tests\run_tests.py`: 29/29 checks. Our files were verified in openpyxl, xlrd and Excel 16.
- Template: generated and compiled for ABC single-EXE, multi-DLL (data DLL + consumer EXE) and Legacy.
