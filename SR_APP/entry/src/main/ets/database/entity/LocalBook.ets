import { relationalStore } from '@kit.ArkData';

/**
 * 本地文件状态：
 * 0 = 仅云端存在（本地未下载）
 * 1 = 本地已存在，可离线阅读
 */
export enum LocalBookState {
  CLOUD_ONLY = 0,
  LOCAL_AVAILABLE = 1
}

/**
 * 同步状态：
 * 0 = 已同步
 * 1 = 待同步
 */
export enum LocalBookSyncStatus {
  SYNCED = 0,
  PENDING = 1
}

export interface LocalBook {
  id?: number;
  bookId?: string;
  title: string;
  author: string;
  coverUrl: string;
  localCoverPath: string;
  fileHash: string;
  fileUrl: string;
  format: string;
  fileName: string;
  fileSize: number;
  totalCatalogCount: number;
  readerBookKey: string;
  localPath: string;
  localState: LocalBookState;
  syncStatus: LocalBookSyncStatus;
  createdAt: number;
  updatedAt: number;
  toc?: string; // 【新增】用于存储章节目录的 JSON 字符串
}

export class LocalBookEntity {
  static readonly TABLE_NAME: string = 'local_books';

  static readonly CREATE_TABLE_SQL: string = `
    CREATE TABLE IF NOT EXISTS ${LocalBookEntity.TABLE_NAME} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bookId TEXT DEFAULT '',
      title TEXT NOT NULL,
      author TEXT DEFAULT '',
      coverUrl TEXT DEFAULT '',
      localCoverPath TEXT DEFAULT '',
      fileHash TEXT NOT NULL,
      fileUrl TEXT DEFAULT '',
      format TEXT NOT NULL DEFAULT 'EPUB',
      fileName TEXT DEFAULT '',
      fileSize INTEGER NOT NULL DEFAULT 0,
      totalCatalogCount INTEGER NOT NULL DEFAULT 0,
      readerBookKey TEXT DEFAULT '',
      localPath TEXT NOT NULL,
      localState INTEGER NOT NULL DEFAULT 1,
      syncStatus INTEGER NOT NULL DEFAULT 1,
      createdAt INTEGER NOT NULL,
      updatedAt INTEGER NOT NULL
    )
  `;

  static readonly CREATE_INDEX_SQL_LIST: string[] = [
    `CREATE UNIQUE INDEX IF NOT EXISTS idx_local_books_file_hash ON ${LocalBookEntity.TABLE_NAME}(fileHash)`,
    `CREATE INDEX IF NOT EXISTS idx_local_books_sync_status ON ${LocalBookEntity.TABLE_NAME}(syncStatus)`,
    `CREATE INDEX IF NOT EXISTS idx_local_books_local_state ON ${LocalBookEntity.TABLE_NAME}(localState)`,
    `CREATE INDEX IF NOT EXISTS idx_local_books_updated_at ON ${LocalBookEntity.TABLE_NAME}(updatedAt DESC)`
  ];

  static createDefault(partial: Partial<LocalBook>): LocalBook {
    const now: number = Date.now();
    return {
      title: partial.title ?? '',
      author: partial.author ?? '',
      coverUrl: partial.coverUrl ?? '',
      localCoverPath: partial.localCoverPath ?? '',
      fileHash: partial.fileHash ?? '',
      fileUrl: partial.fileUrl ?? '',
      format: partial.format ?? 'EPUB',
      fileName: partial.fileName ?? '',
      fileSize: partial.fileSize ?? 0,
      totalCatalogCount: partial.totalCatalogCount ?? 0,
      readerBookKey: partial.readerBookKey ?? '',
      localPath: partial.localPath ?? '',
      localState: partial.localState ?? LocalBookState.LOCAL_AVAILABLE,
      syncStatus: partial.syncStatus ?? LocalBookSyncStatus.PENDING,
      createdAt: partial.createdAt ?? now,
      updatedAt: partial.updatedAt ?? now,
      bookId: partial.bookId ?? '',
      id: partial.id
    };
  }

  static toValuesBucket(book: LocalBook): relationalStore.ValuesBucket {
    return {
      bookId: book.bookId ?? '',
      title: book.title,
      author: book.author,
      coverUrl: book.coverUrl,
      localCoverPath: book.localCoverPath,
      fileHash: book.fileHash,
      fileUrl: book.fileUrl,
      format: book.format,
      fileName: book.fileName,
      fileSize: book.fileSize,
      totalCatalogCount: book.totalCatalogCount,
      readerBookKey: book.readerBookKey,
      localPath: book.localPath,
      localState: book.localState,
      syncStatus: book.syncStatus,
      createdAt: book.createdAt,
      updatedAt: book.updatedAt
    };
  }

  static fromResultSet(resultSet: relationalStore.ResultSet): LocalBook {
    return {
      id: LocalBookEntity.getNumber(resultSet, 'id'),
      bookId: LocalBookEntity.getString(resultSet, 'bookId'),
      title: LocalBookEntity.getString(resultSet, 'title'),
      author: LocalBookEntity.getString(resultSet, 'author'),
      coverUrl: LocalBookEntity.getString(resultSet, 'coverUrl'),
      localCoverPath: LocalBookEntity.getString(resultSet, 'localCoverPath'),
      fileHash: LocalBookEntity.getString(resultSet, 'fileHash'),
      fileUrl: LocalBookEntity.getString(resultSet, 'fileUrl'),
      format: LocalBookEntity.getString(resultSet, 'format'),
      fileName: LocalBookEntity.getString(resultSet, 'fileName'),
      fileSize: LocalBookEntity.getNumber(resultSet, 'fileSize'),
      totalCatalogCount: LocalBookEntity.getNumber(resultSet, 'totalCatalogCount'),
      readerBookKey: LocalBookEntity.getString(resultSet, 'readerBookKey'),
      localPath: LocalBookEntity.getString(resultSet, 'localPath'),
      localState: LocalBookEntity.getNumber(resultSet, 'localState') as LocalBookState,
      syncStatus: LocalBookEntity.getNumber(resultSet, 'syncStatus') as LocalBookSyncStatus,
      createdAt: LocalBookEntity.getNumber(resultSet, 'createdAt'),
      updatedAt: LocalBookEntity.getNumber(resultSet, 'updatedAt')
    };
  }

  private static getString(resultSet: relationalStore.ResultSet, columnName: string): string {
    const columnIndex: number = resultSet.getColumnIndex(columnName);
    if (columnIndex < 0) {
      return '';
    }
    if (resultSet.isColumnNull(columnIndex)) {
      return '';
    }
    return resultSet.getString(columnIndex);
  }

  private static getNumber(resultSet: relationalStore.ResultSet, columnName: string): number {
    const columnIndex: number = resultSet.getColumnIndex(columnName);
    if (columnIndex < 0) {
      return 0;
    }
    if (resultSet.isColumnNull(columnIndex)) {
      return 0;
    }
    return Number(resultSet.getLong(columnIndex));
  }
}
