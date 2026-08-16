import ExcelJS from "exceljs";
import { servesNonProductionData } from "./environment";

type ExportCell = ExcelJS.CellValue;

export type ExportColumn<Row> = {
  header: string;
  width?: number;
  numFmt?: string;
  value: (row: Row) => ExportCell;
};

const FOREST = "153D37";
const FOREST_SECONDARY = "285D53";
const MINT = "DCEAE3";
const PAPER = "F5F3ED";
const WHITE = "FFFEFB";
const INK = "142522";
const MUTED = "5F6D68";
const LINE = "D7DDD7";

function protectText(value: ExportCell): ExportCell {
  if (typeof value !== "string") return value;
  const normalized = value.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, " ");
  return /^[=+\-@]/.test(normalized) ? `'${normalized}` : normalized;
}

export function createExportWorkbook(subject: string) {
  const workbook = new ExcelJS.Workbook();
  const author = servesNonProductionData ? "Ruta Solidaria · datos de práctica" : "Ruta Solidaria";
  workbook.creator = author;
  workbook.lastModifiedBy = author;
  workbook.created = new Date();
  workbook.modified = new Date();
  workbook.subject = subject;
  workbook.company = author;
  workbook.calcProperties.fullCalcOnLoad = true;
  return workbook;
}

export function addDataSheet<Row>(
  workbook: ExcelJS.Workbook,
  options: {
    name: string;
    title: string;
    description: string;
    columns: ExportColumn<Row>[];
    rows: Row[];
  },
) {
  const sheet = workbook.addWorksheet(options.name, { views: [{ state: "frozen", ySplit: 4 }] });
  const lastColumn = Math.max(1, options.columns.length);
  sheet.mergeCells(1, 1, 1, lastColumn);
  sheet.mergeCells(2, 1, 2, lastColumn);
  const titleCell = sheet.getCell(1, 1);
  titleCell.value = options.title;
  titleCell.font = { name: "Aptos Display", size: 18, bold: true, color: { argb: WHITE } };
  titleCell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: FOREST } };
  titleCell.alignment = { vertical: "middle" };
  sheet.getRow(1).height = 34;

  const descriptionCell = sheet.getCell(2, 1);
  descriptionCell.value = options.description;
  descriptionCell.font = { name: "Aptos", size: 10, color: { argb: FOREST } };
  descriptionCell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: MINT } };
  descriptionCell.alignment = { vertical: "middle", wrapText: true };
  sheet.getRow(2).height = 31;
  sheet.getRow(3).height = 8;

  options.columns.forEach((column, index) => {
    const excelColumn = sheet.getColumn(index + 1);
    excelColumn.width = Math.min(42, Math.max(11, column.width ?? 18));
    const cell = sheet.getCell(4, index + 1);
    cell.value = column.header;
    cell.font = { name: "Aptos", size: 10, bold: true, color: { argb: WHITE } };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: FOREST_SECONDARY } };
    cell.alignment = { vertical: "middle", wrapText: true };
    cell.border = { bottom: { style: "thin", color: { argb: FOREST } } };
  });
  sheet.getRow(4).height = 28;

  options.rows.forEach((row, rowIndex) => {
    const targetRow = sheet.getRow(rowIndex + 5);
    options.columns.forEach((column, columnIndex) => {
      const cell = targetRow.getCell(columnIndex + 1);
      cell.value = protectText(column.value(row));
      cell.font = { name: "Aptos", size: 10, color: { argb: INK } };
      cell.alignment = { vertical: "top", wrapText: true };
      cell.border = { bottom: { style: "hair", color: { argb: LINE } } };
      if (column.numFmt) cell.numFmt = column.numFmt;
    });
    if (rowIndex % 2 === 1) {
      targetRow.eachCell((cell) => {
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: PAPER } };
      });
    }
  });

  if (!options.rows.length) {
    const emptyCell = sheet.getCell(5, 1);
    emptyCell.value = "Sin registros disponibles para este corte.";
    emptyCell.font = { name: "Aptos", italic: true, color: { argb: MUTED } };
    sheet.mergeCells(5, 1, 5, lastColumn);
  } else {
    sheet.autoFilter = { from: { row: 4, column: 1 }, to: { row: 4 + options.rows.length, column: lastColumn } };
  }

  sheet.pageSetup = {
    orientation: lastColumn > 7 ? "landscape" : "portrait",
    fitToPage: true,
    fitToWidth: 1,
    fitToHeight: 0,
    margins: { left: 0.25, right: 0.25, top: 0.5, bottom: 0.5, header: 0.2, footer: 0.2 },
  };
  sheet.headerFooter.oddFooter = `${servesNonProductionData ? "Ruta Solidaria · datos de práctica" : "Ruta Solidaria"} · &D &T · Página &P de &N`;
  return sheet;
}

export async function workbookResponse(workbook: ExcelJS.Workbook, filename: string) {
  const buffer = await workbook.xlsx.writeBuffer();
  return new Response(new Uint8Array(buffer), {
    status: 200,
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename*=UTF-8''${encodeURIComponent(filename)}`,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
