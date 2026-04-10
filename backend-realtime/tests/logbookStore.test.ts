import { describe, expect, it } from "vitest";
import {
  GoogleSheetsLogbookStore,
  type SheetsAdapter
} from "../src/stores/logbookStore";

class FakeSheetsAdapter implements SheetsAdapter {
  rows: string[][] = [];
  header: string[] = [];

  async read(range: string): Promise<string[][]> {
    if (range.includes("A1:E1")) {
      return this.header.length > 0 ? [this.header] : [];
    }
    return this.rows.map((row) => [...row]);
  }

  async update(range: string, values: Array<Array<string | number>>): Promise<void> {
    if (range.includes("A1:E1")) {
      this.header = values[0].map(String);
      return;
    }

    const rowMatch = range.match(/A(\d+):E\1/);
    if (!rowMatch) {
      return;
    }
    const rowIndex = Number(rowMatch[1]) - 2;
    this.rows[rowIndex] = values[0].map(String);
  }

  async append(_: string, values: Array<Array<string | number>>): Promise<void> {
    this.rows.push(values[0].map(String));
  }
}

describe("GoogleSheetsLogbookStore", () => {
  it("ensures header and appends new entries", async () => {
    const adapter = new FakeSheetsAdapter();
    const store = new GoogleSheetsLogbookStore("logbook", adapter);

    await store.upsert({
      hashedId: "abc123",
      signer: "Ari",
      message: "First signature",
      createdAt: 100,
      updatedAt: 100
    });

    expect(adapter.header[0]).toBe("hashedId");
    expect(adapter.rows).toHaveLength(1);
    expect(adapter.rows[0][0]).toBe("abc123");
  });

  it("updates existing rows while preserving createdAt", async () => {
    const adapter = new FakeSheetsAdapter();
    const store = new GoogleSheetsLogbookStore("logbook", adapter);

    await store.upsert({
      hashedId: "abc123",
      signer: "Ari",
      message: "First signature",
      createdAt: 100,
      updatedAt: 100
    });
    const saved = await store.upsert({
      hashedId: "abc123",
      signer: "Ari V",
      message: "Edited signature",
      createdAt: 999,
      updatedAt: 200
    });

    expect(saved.createdAt).toBe(100);
    expect(saved.updatedAt).toBe(200);
    expect(adapter.rows).toHaveLength(1);
    expect(adapter.rows[0][1]).toBe("Ari V");
  });
});
