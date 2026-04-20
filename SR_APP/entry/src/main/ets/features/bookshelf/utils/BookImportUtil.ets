import fs from '@ohos.file.fs';
import hash from '@ohos.file.hash';
import fileuri from '@ohos.file.fileuri';
import { common } from '@kit.AbilityKit';
import { bookParser } from '@kit.ReaderKit';
import { LocalBook, LocalBookState, LocalBookSyncStatus } from '../../../database/entity/LocalBook';

interface CopiedBookFile {
  fileName: string;
  sandboxPath: string;
  fileSize: number;
}

interface ParsedBookMeta {
  title: string;
  author: string;
  totalCatalogCount: number;
  coverBuffer?: ArrayBuffer;
  coverResourceName?: string;
}

interface ReaderBookInfo {
  bookTitle?: string;
  title?: string;
  name?: string;
  bookAuthor?: string;
  author?: string;
  creator?: string;
  bookCoverImage?: string;
  coverImage?: string;
  cover?: string;
}

export class BookImportUtil {
  public static async importBook(context: common.UIAbilityContext, pickedUri: string): Promise<LocalBook> {
    try {
      const copied: CopiedBookFile = await BookImportUtil.copyToSandbox(context, pickedUri);
      const fileHash: string = await BookImportUtil.calculateFileSha256(copied.sandboxPath);
      const parsed: ParsedBookMeta = await BookImportUtil.parseBookByReaderKit(copied.sandboxPath, copied.fileName);
      const localCoverPath: string = parsed.coverBuffer && parsed.coverBuffer.byteLength > 0
        ? await BookImportUtil.persistCover(context, fileHash, parsed.coverBuffer, parsed.coverResourceName ?? '')
        : '';

      const now: number = Date.now();
      const format: string = BookImportUtil.extractExtension(copied.fileName).toUpperCase() || 'EPUB';
      const title: string = parsed.title.length > 0 ? parsed.title : BookImportUtil.removeFileExt(copied.fileName);
      return {
        title: title,
        author: parsed.author,
        coverUrl: localCoverPath,
        localCoverPath: localCoverPath,
        fileHash: fileHash,
        fileUrl: '',
        format: format,
        fileName: copied.fileName,
        fileSize: copied.fileSize,
        totalCatalogCount: parsed.totalCatalogCount,
        readerBookKey: `sha256:${fileHash}`,
        localPath: copied.sandboxPath,
        localState: LocalBookState.LOCAL_AVAILABLE,
        syncStatus: LocalBookSyncStatus.PENDING,
        bookId: '',
        createdAt: now,
        updatedAt: now
      };
    } catch (e) {
      const err: Error = e instanceof Error ? e : new Error(String(e));
      throw new Error(String(err.message));
    }
  }

  /**
   * FilePicker returns a permission-scoped URI. It may expire and is not stable for long-term parser access.
   * Copying file into app sandbox gives stable path and permission so Reader Kit can parse reliably.
   * This differs from backend absolute-path reading where server process owns fixed filesystem permission.
   */
  private static async copyToSandbox(context: common.UIAbilityContext, pickedUri: string): Promise<CopiedBookFile> {
    const sourcePath: string = BookImportUtil.resolvePathFromUri(pickedUri);
    const booksDir: string = `${context.filesDir}/books`;
    BookImportUtil.ensureDir(booksDir);

    const originalName: string = BookImportUtil.extractFileName(sourcePath, pickedUri);
    const targetName: string = `${Date.now()}_${BookImportUtil.sanitizeFileName(originalName)}`;
    const targetPath: string = `${booksDir}/${targetName}`;
    await BookImportUtil.copyFileAsync(sourcePath, targetPath);

    const stat = fs.statSync(targetPath);
    return {
      fileName: originalName,
      sandboxPath: targetPath,
      fileSize: Number(stat.size)
    };
  }

  /**
   * Promise-based hash API keeps large-file hashing off UI render flow.
   * UI thread awaits result but does not execute heavy hash loop directly.
   */
  private static async calculateFileSha256(filePath: string): Promise<string> {
    return await hash.hash(filePath, 'sha256');
  }

  private static async persistCover(
    context: common.UIAbilityContext,
    fileHash: string,
    coverBuffer: ArrayBuffer,
    coverResourceName: string
  ): Promise<string> {
    const coversDir: string = `${context.filesDir}/covers`;
    BookImportUtil.ensureDir(coversDir);
    const ext: string = BookImportUtil.resolveCoverExtension(coverResourceName, coverBuffer);
    const coverPath: string = `${coversDir}/${fileHash}_${Date.now()}.${ext}`;
    const file = fs.openSync(coverPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    try {
      fs.writeSync(file.fd, coverBuffer);
    } finally {
      fs.closeSync(file);
    }
    return coverPath;
  }

  private static async parseBookByReaderKit(localBookPath: string, fileName: string): Promise<ParsedBookMeta> {
    try {
      const handler: bookParser.BookParserHandler = await bookParser.getDefaultHandler(localBookPath);
      const info: ReaderBookInfo = handler.getBookInfo() as Object as ReaderBookInfo;
      const catalogList: bookParser.CatalogItem[] = handler.getCatalogList() ?? [];

      const title: string = BookImportUtil.firstNonEmpty(
        info.bookTitle,
        info.title,
        info.name,
        BookImportUtil.removeFileExt(fileName)
      );
      const author: string = BookImportUtil.firstNonEmpty(
        info.bookAuthor,
        info.author,
        info.creator
      );
      const coverResourceName: string = BookImportUtil.firstNonEmpty(
        info.bookCoverImage,
        info.coverImage,
        info.cover
      );
      let coverBuffer: ArrayBuffer | undefined = undefined;

      if (coverResourceName.length > 0) {
        const rawCover: ArrayBuffer = handler.getResourceContent(-1, coverResourceName);
        if (rawCover.byteLength > 0) {
          coverBuffer = rawCover;
        }
      }

      return {
        title: title,
        author: author,
        totalCatalogCount: catalogList.length,
        coverBuffer: coverBuffer,
        coverResourceName: coverResourceName
      };
    } catch (e) {
      const err: Error = e instanceof Error ? e : new Error(String(e));
      throw new Error(String(err.message));
    }
  }

  private static ensureDir(dirPath: string): void {
    try {
      fs.accessSync(dirPath);
      return;
    } catch (_) {
      fs.mkdirSync(dirPath);
    }
  }

  private static copyFileAsync(sourcePath: string, targetPath: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      fs.copyFile(sourcePath, targetPath, (err: Object | undefined) => {
        if (err) {
          reject(new Error(String(err)));
          return;
        }
        resolve();
      });
    });
  }

  private static resolvePathFromUri(uriOrPath: string): string {
    if (uriOrPath.startsWith('/')) {
      return uriOrPath;
    }
    try {
      return new fileuri.FileUri(uriOrPath).path;
    } catch (_) {
      if (uriOrPath.startsWith('file://')) {
        return decodeURIComponent(uriOrPath.replace('file://', ''));
      }
      throw new Error(`invalid file uri: ${uriOrPath}`);
    }
  }

  private static extractFileName(path: string, rawUri: string): string {
    const fromPath: string = path.substring(path.lastIndexOf('/') + 1);
    if (fromPath.length > 0) {
      return fromPath;
    }
    const normalized: string = rawUri.replace(/\\/g, '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1) || `book_${Date.now()}.epub`;
  }

  private static sanitizeFileName(fileName: string): string {
    const safe: string = fileName.trim().replace(/[^a-zA-Z0-9._-]/g, '_');
    return safe.length > 0 ? safe : `book_${Date.now()}.epub`;
  }

  private static removeFileExt(fileName: string): string {
    const idx: number = fileName.lastIndexOf('.');
    return idx > 0 ? fileName.substring(0, idx) : fileName;
  }

  private static extractExtension(fileName: string): string {
    const idx: number = fileName.lastIndexOf('.');
    return idx > -1 && idx < fileName.length - 1 ? fileName.substring(idx + 1) : '';
  }

  private static resolveCoverExtension(resourceName: string, coverBuffer: ArrayBuffer): string {
    const extByName: string = BookImportUtil.extractExtension(resourceName).toLowerCase();
    if (extByName.length > 0) {
      return extByName;
    }
    const bytes: Uint8Array = new Uint8Array(coverBuffer);
    if (bytes.length >= 4 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) {
      return 'png';
    }
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xD8) {
      return 'jpg';
    }
    return 'img';
  }

  private static firstNonEmpty(...values: (string | undefined)[]): string {
    for (const value of values) {
      if (typeof value === 'string' && value.trim().length > 0) {
        return value.trim();
      }
    }
    return '';
  }
}
