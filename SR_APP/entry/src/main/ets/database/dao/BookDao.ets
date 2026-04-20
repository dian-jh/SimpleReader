import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocalBook, LocalBookEntity, LocalBookState, LocalBookSyncStatus } from '../entity/LocalBook';

const LOG_DOMAIN: number = 0xFF11;
const LOG_TAG: string = 'BookDao';
const DB_NAME: string = 'simple_reader.db';

type SqlArg = string | number | boolean | Uint8Array | null;

export class BookDao {
  private static instance?: BookDao;
  private store?: relationalStore.RdbStore;

  public static getInstance(): BookDao {
    if (!BookDao.instance) {
      BookDao.instance = new BookDao();
    }
    return BookDao.instance;
  }

  public async init(context: common.UIAbilityContext): Promise<void> {
    if (this.store) {
      return;
    }

    try {
      const config: relationalStore.StoreConfig = {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      };
      this.store = await this.openStore(context, config);
      await this.store.executeSql(LocalBookEntity.CREATE_TABLE_SQL);
      for (const sql of LocalBookEntity.CREATE_INDEX_SQL_LIST) {
        await this.store.executeSql(sql);
      }
    } catch (e) {
      const err: Error = e instanceof Error ? e : new Error(String(e));
      hilog.error(LOG_DOMAIN, LOG_TAG, 'init failed: %{public}s', err.message);
      throw new Error(String(err.message));
    }
  }

  public async insert(localBook: LocalBook): Promise<number> {
    const db: relationalStore.RdbStore = this.getStoreOrThrow();
    const book: LocalBook = LocalBookEntity.createDefault(localBook);

    try {
      return await db.insert(LocalBookEntity.TABLE_NAME, LocalBookEntity.toValuesBucket(book));
    } catch (e) {
      const err: Error = e instanceof Error ? e : new Error(String(e));
      hilog.error(LOG_DOMAIN, LOG_TAG, 'insert failed, hash=%{public}s, err=%{public}s', book.fileHash, err.message);
      throw new Error(String(err.message));
    }
  }

  public async listAll(orderDescByUpdatedAt: boolean = true): Promise<LocalBook[]> {
    const db: relationalStore.RdbStore = this.getStoreOrThrow();
    const orderSql: string = orderDescByUpdatedAt ? 'DESC' : 'ASC';
    const sql: string = `SELECT * FROM ${LocalBookEntity.TABLE_NAME} ORDER BY updatedAt ${orderSql}`;
    const resultSet: relationalStore.ResultSet = await db.querySql(sql);
    return this.parseRows(resultSet);
  }

  public async listPendingSyncBooks(limit: number = 30): Promise<LocalBook[]> {
    const db: relationalStore.RdbStore = this.getStoreOrThrow();
    const sql: string = `
      SELECT * FROM ${LocalBookEntity.TABLE_NAME}
      WHERE syncStatus = ?
      ORDER BY updatedAt ASC
      LIMIT ?
    `;
    const args: SqlArg[] = [LocalBookSyncStatus.PENDING, limit];
    const resultSet: relationalStore.ResultSet = await db.querySql(sql, args);
    return this.parseRows(resultSet);
  }

  public async findByFileHash(fileHash: string): Promise<LocalBook | null> {
    const db: relationalStore.RdbStore = this.getStoreOrThrow();
    const sql: string = `SELECT * FROM ${LocalBookEntity.TABLE_NAME} WHERE fileHash = ? LIMIT 1`;
    const args: SqlArg[] = [fileHash];
    const resultSet: relationalStore.ResultSet = await db.querySql(sql, args);
    const rows: LocalBook[] = await this.parseRows(resultSet);
    return rows.length > 0 ? rows[0] : null;
  }

  public async markSyncPending(localId: number): Promise<void> {
    const db: relationalStore.RdbStore = this.getStoreOrThrow();
    const sql: string = `
      UPDATE ${LocalBookEntity.TABLE_NAME}
      SET syncStatus = ?, updatedAt = ?
      WHERE id = ?
    `;
    const args: SqlArg[] = [LocalBookSyncStatus.PENDING, Date.now(), localId];
    await db.executeSql(sql, args);
  }

  public async updateLocalState(localId: number, localState: LocalBookState, localPath: string = ''): Promise<void> {
    const db: relationalStore.RdbStore = this.getStoreOrThrow();
    const sql: string = `
      UPDATE ${LocalBookEntity.TABLE_NAME}
      SET localState = ?, localPath = ?, updatedAt = ?
      WHERE id = ?
    `;
    const args: SqlArg[] = [localState, localPath, Date.now(), localId];
    await db.executeSql(sql, args);
  }

  public async markSyncSuccess(localId: number, cloudBookId: string, fileUrl: string): Promise<void> {
    const db: relationalStore.RdbStore = this.getStoreOrThrow();
    const sql: string = `
      UPDATE ${LocalBookEntity.TABLE_NAME}
      SET bookId = ?, fileUrl = ?, syncStatus = ?, updatedAt = ?
      WHERE id = ?
    `;
    const args: SqlArg[] = [cloudBookId, fileUrl, LocalBookSyncStatus.SYNCED, Date.now(), localId];
    await db.executeSql(sql, args);
  }

  public async close(): Promise<void> {
    if (!this.store) {
      return;
    }
    this.store.close();
    this.store = undefined;
  }

  private getStoreOrThrow(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('BookDao not initialized. Call init(context) first.');
    }
    return this.store;
  }

  private async parseRows(resultSet: relationalStore.ResultSet): Promise<LocalBook[]> {
    const books: LocalBook[] = [];
    try {
      while (resultSet.goToNextRow()) {
        books.push(LocalBookEntity.fromResultSet(resultSet));
      }
      return books;
    } finally {
      resultSet.close();
    }
  }

  private openStore(
    context: common.UIAbilityContext,
    config: relationalStore.StoreConfig
  ): Promise<relationalStore.RdbStore> {
    return new Promise<relationalStore.RdbStore>((resolve, reject) => {
      relationalStore.getRdbStore(context, config, (err: Object | undefined, store: relationalStore.RdbStore) => {
        if (err) {
          reject(new Error(String(err)));
          return;
        }
        resolve(store);
      });
    });
  }
}
