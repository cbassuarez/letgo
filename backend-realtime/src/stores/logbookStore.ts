import { google } from "googleapis";

export interface LogbookEntryRecord {
  hashedId: string;
  signer: string;
  message: string;
  createdAt: number;
  updatedAt: number;
}

export interface LogbookStore {
  upsert(entry: LogbookEntryRecord): Promise<LogbookEntryRecord>;
  getByHashedId(hashedId: string): Promise<LogbookEntryRecord | null>;
  list(): Promise<LogbookEntryRecord[]>;
}

export class MemoryLogbookStore implements LogbookStore {
  private readonly entries = new Map<string, LogbookEntryRecord>();

  async upsert(entry: LogbookEntryRecord): Promise<LogbookEntryRecord> {
    const existing = this.entries.get(entry.hashedId);
    const normalized: LogbookEntryRecord = existing
      ? {
          ...existing,
          signer: entry.signer,
          message: entry.message,
          updatedAt: entry.updatedAt
        }
      : entry;

    this.entries.set(entry.hashedId, normalized);
    return normalized;
  }

  async getByHashedId(hashedId: string): Promise<LogbookEntryRecord | null> {
    return this.entries.get(hashedId) ?? null;
  }

  async list(): Promise<LogbookEntryRecord[]> {
    return [...this.entries.values()];
  }
}

export interface SheetsAdapter {
  read(range: string): Promise<string[][]>;
  update(range: string, values: Array<Array<string | number>>): Promise<void>;
  append(range: string, values: Array<Array<string | number>>): Promise<void>;
}

const HEADER = ["hashedId", "signer", "message", "createdAt", "updatedAt"] as const;

class GoogleSheetsAdapter implements SheetsAdapter {
  private readonly sheets;

  constructor(
    private readonly sheetId: string,
    serviceAccountEmail: string,
    privateKey: string
  ) {
    const auth = new google.auth.JWT({
      email: serviceAccountEmail,
      key: privateKey,
      scopes: ["https://www.googleapis.com/auth/spreadsheets"]
    });
    this.sheets = google.sheets({ version: "v4", auth });
  }

  async read(range: string): Promise<string[][]> {
    const res = await this.sheets.spreadsheets.values.get({
      spreadsheetId: this.sheetId,
      range
    });

    const values = res.data.values ?? [];
    return values.map((row) => row.map((value) => String(value)));
  }

  async update(range: string, values: Array<Array<string | number>>): Promise<void> {
    await this.sheets.spreadsheets.values.update({
      spreadsheetId: this.sheetId,
      range,
      valueInputOption: "RAW",
      requestBody: {
        values
      }
    });
  }

  async append(range: string, values: Array<Array<string | number>>): Promise<void> {
    await this.sheets.spreadsheets.values.append({
      spreadsheetId: this.sheetId,
      range,
      valueInputOption: "RAW",
      insertDataOption: "INSERT_ROWS",
      requestBody: {
        values
      }
    });
  }
}

export class GoogleSheetsLogbookStore implements LogbookStore {
  private headerEnsured = false;

  constructor(
    private readonly sheetTab: string,
    private readonly adapter: SheetsAdapter
  ) {}

  static fromEnv(config: {
    LOGBOOK_GOOGLE_SHEET_ID: string;
    LOGBOOK_GOOGLE_SERVICE_ACCOUNT_EMAIL: string;
    LOGBOOK_GOOGLE_PRIVATE_KEY: string;
    LOGBOOK_GOOGLE_SHEET_TAB: string;
  }): GoogleSheetsLogbookStore {
    return new GoogleSheetsLogbookStore(
      config.LOGBOOK_GOOGLE_SHEET_TAB,
      new GoogleSheetsAdapter(
        config.LOGBOOK_GOOGLE_SHEET_ID,
        config.LOGBOOK_GOOGLE_SERVICE_ACCOUNT_EMAIL,
        config.LOGBOOK_GOOGLE_PRIVATE_KEY.replace(/\\n/g, "\n")
      )
    );
  }

  async upsert(entry: LogbookEntryRecord): Promise<LogbookEntryRecord> {
    await this.ensureHeader();
    const rows = await this.adapter.read(this.bodyRange());

    const existingIndex = rows.findIndex((row) => row[0] === entry.hashedId);
    if (existingIndex >= 0) {
      const sheetRow = existingIndex + 2;
      const createdAt = Number(rows[existingIndex]?.[3] ?? entry.createdAt) || entry.createdAt;
      const updated: LogbookEntryRecord = {
        ...entry,
        createdAt
      };
      await this.adapter.update(this.rowRange(sheetRow), [this.toRow(updated)]);
      return updated;
    }

    await this.adapter.append(this.appendRange(), [this.toRow(entry)]);
    return entry;
  }

  async getByHashedId(hashedId: string): Promise<LogbookEntryRecord | null> {
    await this.ensureHeader();
    const rows = await this.adapter.read(this.bodyRange());
    const row = rows.find((candidate) => candidate[0] === hashedId);
    return row ? this.fromRow(row) : null;
  }

  async list(): Promise<LogbookEntryRecord[]> {
    await this.ensureHeader();
    const rows = await this.adapter.read(this.bodyRange());
    return rows
      .map((row) => this.fromRow(row))
      .filter((entry): entry is LogbookEntryRecord => Boolean(entry));
  }

  private async ensureHeader(): Promise<void> {
    if (this.headerEnsured) {
      return;
    }

    const headerRow = await this.adapter.read(this.headerRange());
    const existingHeader = headerRow[0] ?? [];
    const missingHeader = HEADER.some((column, index) => existingHeader[index] !== column);
    if (missingHeader) {
      await this.adapter.update(this.headerRange(), [Array.from(HEADER)]);
    }
    this.headerEnsured = true;
  }

  private fromRow(row: string[]): LogbookEntryRecord | null {
    const hashedId = row[0]?.trim();
    const signer = row[1]?.trim();
    const message = row[2]?.trim();
    const createdAt = Number(row[3] ?? 0);
    const updatedAt = Number(row[4] ?? 0);

    if (!hashedId || !signer || !message || !Number.isFinite(createdAt) || !Number.isFinite(updatedAt)) {
      return null;
    }

    return {
      hashedId,
      signer,
      message,
      createdAt,
      updatedAt
    };
  }

  private toRow(entry: LogbookEntryRecord): Array<string | number> {
    return [
      entry.hashedId,
      entry.signer,
      entry.message,
      entry.createdAt,
      entry.updatedAt
    ];
  }

  private headerRange(): string {
    return `'${this.sheetTab}'!A1:E1`;
  }

  private bodyRange(): string {
    return `'${this.sheetTab}'!A2:E`;
  }

  private rowRange(row: number): string {
    return `'${this.sheetTab}'!A${row}:E${row}`;
  }

  private appendRange(): string {
    return `'${this.sheetTab}'!A:E`;
  }
}
