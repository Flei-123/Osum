# OFFICE -- concept (15.10.2026, nothing implemented yet)

Goal: a small everyday office base on the fUi scene tree, pure Firn, no external engine.

## Layers
1. `lib/office/doc.fi` -- text document model: UTF-8 gap buffer + run table (bold/italic/heading/list per line range).
   Load/save `.txt`, `.md` (headings `#`, `**`, `*`, lists), export minimal `.docx` (zip of document.xml via lib zip) and `.odt`.
2. `lib/office/sheet.fi` -- grid (sparse cells, 26x999 first), cell = number | text | formula. Formulas: `+ - * /`, parentheses,
   cell refs `A1`, ranges in `SUM(A1:B3)`, `AVG/MIN/MAX/COUNT` next. Dependency graph with cycle detection (`#CYCLE`),
   errors `#DIV/0!`, `#REF!`, `#NAME?`. CSV load/save (RFC 4180, UTF-8, `;` or `,` sniffed); xlsx-lite = zip with
   `sheet1.xml` (inline strings, no styles) read + write.
3. Apps `kernel/user/sheet.fi`, `kernel/user/write.fi` (fUi): grid as canvas2 + entry for the active cell; text as memo/editor.
4. Gates `tools/office/run.sh`: host oracle (formula golden values vs Python `ast` evaluator, CSV round trip vs Python csv,
   docx opens with python-docx, xlsx opens with openpyxl) + KVM smoke.

## Order
mail (lib done) -> sheet lib + oracle -> sheet app -> text model -> text app -> docx/odt/xlsx export.
