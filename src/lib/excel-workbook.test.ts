import ExcelJS from "exceljs";
import { describe, expect, it } from "vitest";
import { addDataSheet, createExportWorkbook, workbookResponse } from "@/lib/excel-workbook";

describe("exportaciones Excel", () => {
  it("conserva tipos, fórmulas y neutraliza texto ejecutable", async () => {
    const workbook = createExportWorkbook("Prueba segura");
    const date = new Date("2026-08-14T12:00:00.000Z");
    addDataSheet(workbook, {
      name: "Datos",
      title: "Datos de prueba",
      description: "Corte sintético",
      columns: [
        { header: "Texto", value: (row: { text: string; quantity: number; date: Date }) => row.text },
        { header: "Cantidad", value: (row) => row.quantity, numFmt: "#,##0" },
        { header: "Fecha", value: (row) => row.date, numFmt: "yyyy-mm-dd" },
        { header: "Doble", value: (row) => ({ formula: "B5*2", result: row.quantity * 2 }) },
      ],
      rows: [{ text: "=HYPERLINK(\"https://example.invalid\")", quantity: 7, date }],
    });

    const response = await workbookResponse(workbook, "prueba.xlsx");
    expect(response.headers.get("content-type")).toContain("spreadsheetml.sheet");
    expect(response.headers.get("content-disposition")).toContain("prueba.xlsx");

    const loaded = new ExcelJS.Workbook();
    await loaded.xlsx.load(await response.arrayBuffer());
    const sheet = loaded.getWorksheet("Datos");
    expect(sheet?.getCell("A5").value).toBe("'=HYPERLINK(\"https://example.invalid\")");
    expect(sheet?.getCell("B5").value).toBe(7);
    expect(sheet?.getCell("C5").value).toBeInstanceOf(Date);
    expect(sheet?.getCell("D5").value).toEqual({ formula: "B5*2", result: 14 });
    expect(sheet?.views[0]).toMatchObject({ state: "frozen", ySplit: 4 });
    expect(sheet?.autoFilter).toBeTruthy();
  });

  it("incluye un estado vacío claro cuando no hay filas", () => {
    const workbook = createExportWorkbook("Sin registros");
    const sheet = addDataSheet(workbook, {
      name: "Vacío",
      title: "Sin datos",
      description: "Prueba",
      columns: [{ header: "Campo", value: (row: { field: string }) => row.field }],
      rows: [],
    });
    expect(sheet.getCell("A5").value).toBe("Sin registros disponibles para este corte.");
  });
});
