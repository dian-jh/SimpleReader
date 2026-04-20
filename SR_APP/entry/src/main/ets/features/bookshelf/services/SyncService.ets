import fs from '@ohos.file.fs';
import request from '@ohos.request';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BookDao } from '../../../database/dao/BookDao';
import { LocalBook } from '../../../database/entity/LocalBook';

const LOG_DOMAIN: number = 0xFF22;
const LOG_TAG: string = 'SyncService';

interface CheckFileResp {
  exists: boolean;
  fileUrl: string | null;
}

interface UploadFileResp {
  fileHash: string;
  fileUrl: string;
}

interface RegisterBookResp {
  bookId: string;
  isNew?: boolean;
  createdAt?: string;
}

interface CheckFilePayload {
  fileHash: string;
}

interface RegisterBookPayload {
  readerBookKey: string;
  fileHash: string;
  fileUrl: string;
  title: string;
  author: string;
  coverUrl: string;
  format: string;
  fileName: string;
  fileSize: number;
  totalCatalogCount: number;
}

interface RequestPostOptions {
  headers?: Record<string, string>;
}

interface UploadCompleteEvent {
  responseCode: number;
  data: string;
}

interface UploadFailEvent {
  code: number;
  message: string;
}

// Temporary compile-safe request stub.
// Replace this function with your real request wrapper after backend integration.
async function requestPost<T>(
  url: string,
  payload: CheckFilePayload | RegisterBookPayload,
  options?: RequestPostOptions
): Promise<T> {
  void payload;
  void options;

  if (url.endsWith('/api/v1/files/check')) {
    const mock: CheckFileResp = { exists: false, fileUrl: null };
    return mock as T;
  }
  if (url.endsWith('/api/v1/library/books')) {
    const mock: RegisterBookResp = { bookId: 'mock-uuid-9999' };
    return mock as T;
  }
  throw new Error(`mock request route not found: ${url}`);
}

export class SyncService {
  private readonly dao: BookDao = BookDao.getInstance();
  private syncing: boolean = false;
  private context: common.UIAbilityContext;
  private uploadBaseUrl: string;

  constructor(context: common.UIAbilityContext, uploadBaseUrl: string) {
    this.context = context;
    this.uploadBaseUrl = uploadBaseUrl;
  }

  public async syncPendingBooks(): Promise<void> {
    if (this.syncing) {
      return;
    }
    this.syncing = true;
    try {
      await this.dao.init(this.context);
      const pendingBooks: LocalBook[] = await this.dao.listPendingSyncBooks();
      for (const book of pendingBooks) {
        if (!book.id) {
          continue;
        }
        try {
          const check: CheckFileResp = await this.checkFileExists(book);
          const fileUrl: string = check.exists ? (check.fileUrl ?? '') : await this.uploadBookFile(book);
          if (fileUrl.length === 0) {
            throw new Error(`empty fileUrl after upload, hash=${book.fileHash}`);
          }
          const cloudBookId: string = await this.registerBookAsset(book, fileUrl);
          await this.dao.markSyncSuccess(book.id, cloudBookId, fileUrl);
        } catch (e) {
          const err: Error = e instanceof Error ? e : new Error(String(e));
          hilog.error(LOG_DOMAIN, LOG_TAG, 'sync failed hash=%{public}s err=%{public}s', book.fileHash, err.message);
        }
      }
    } finally {
      this.syncing = false;
    }
  }

  public async fetchCloudBooksAndUpdateLocal(): Promise<void> {
    await this.syncPendingBooks();
  }

  private async checkFileExists(book: LocalBook): Promise<CheckFileResp> {
    const payload: CheckFilePayload = { fileHash: book.fileHash };
    return await requestPost<CheckFileResp>('/api/v1/files/check', payload);
  }

  private async uploadBookFile(book: LocalBook): Promise<string> {
    const cachePath: string = await this.prepareUploadCacheFile(book.localPath, book.fileName);
    const filePart: request.File = {
      filename: book.fileName,
      name: 'file',
      uri: this.toInternalCacheUri(cachePath),
      type: 'application/epub+zip'
    };
    const uploadTask: request.UploadTask = await request.uploadFile(this.context, {
      url: `${this.uploadBaseUrl}/api/v1/files/upload`,
      method: 'POST',
      header: { Accept: 'application/json' },
      files: [filePart],
      data: [{ name: 'type', value: 'epub' }]
    });
    const uploadResp: UploadFileResp = await this.waitUploadResult(uploadTask);
    return uploadResp.fileUrl;
  }

  private async registerBookAsset(book: LocalBook, fileUrl: string): Promise<string> {
    const payload: RegisterBookPayload = {
      readerBookKey: book.readerBookKey,
      fileHash: book.fileHash,
      fileUrl: fileUrl,
      title: book.title,
      author: book.author,
      coverUrl: book.localCoverPath.length > 0 ? book.localCoverPath : (book.coverUrl || ''),
      format: book.format || 'EPUB',
      fileName: book.fileName,
      fileSize: book.fileSize,
      totalCatalogCount: book.totalCatalogCount
    };
    const idempotencyKey: string = `${book.fileHash}-${book.updatedAt}`;
    const options: RequestPostOptions = { headers: { 'Idempotency-Key': idempotencyKey } };
    const resp: RegisterBookResp = await requestPost<RegisterBookResp>('/api/v1/library/books', payload, options);
    return resp.bookId;
  }

  private async prepareUploadCacheFile(localPath: string, fileName: string): Promise<string> {
    const uploadDir: string = `${this.context.cacheDir}/sync_upload`;
    this.ensureDir(uploadDir);
    const safeName: string = fileName.trim().length > 0 ? fileName : `${Date.now()}.epub`;
    const cachePath: string = `${uploadDir}/${Date.now()}_${safeName.replace(/[^a-zA-Z0-9._-]/g, '_')}`;
    await this.copyFile(localPath, cachePath);
    return cachePath;
  }

  private waitUploadResult(uploadTask: request.UploadTask): Promise<UploadFileResp> {
    return new Promise<UploadFileResp>((resolve, reject) => {
      uploadTask.on('complete', (result: Object) => {
        try {
          const event: UploadCompleteEvent = result as UploadCompleteEvent;
          const code: number = Number(event.responseCode);
          if (code < 200 || code >= 300) {
            reject(new Error(`upload failed, status=${code}`));
            return;
          }
          const parsed: UploadFileResp = this.parseUploadResponse(event.data);
          if (parsed.fileUrl.length === 0) {
            reject(new Error('upload response missing fileUrl'));
            return;
          }
          resolve(parsed);
        } catch (e) {
          const err: Error = e instanceof Error ? e : new Error(String(e));
          reject(new Error(String(err.message)));
        }
      });

      uploadTask.on('fail', (eventObj: Object) => {
        const event: UploadFailEvent = eventObj as UploadFailEvent;
        reject(new Error(`upload task fail: ${event.code}-${event.message}`));
      });
    });
  }

  private parseUploadResponse(text: string): UploadFileResp {
    const parsedObj: Object = JSON.parse(text) as Object;
    const parsed: UploadFileResp = parsedObj as UploadFileResp;
    return {
      fileHash: parsed.fileHash || '',
      fileUrl: parsed.fileUrl || ''
    };
  }

  private toInternalCacheUri(cachePath: string): string {
    const normalizedPath: string = cachePath.replace(/\\/g, '/');
    const normalizedCacheDir: string = this.context.cacheDir.replace(/\\/g, '/');
    const relative: string = normalizedPath.replace(`${normalizedCacheDir}/`, '');
    return `internal://cache/${relative}`;
  }

  private ensureDir(dirPath: string): void {
    try {
      fs.accessSync(dirPath);
      return;
    } catch (_) {
      fs.mkdirSync(dirPath);
    }
  }

  private copyFile(src: string, dst: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      fs.copyFile(src, dst, (err: Object | undefined) => {
        if (err) {
          reject(new Error(String(err)));
          return;
        }
        resolve();
      });
    });
  }
}
