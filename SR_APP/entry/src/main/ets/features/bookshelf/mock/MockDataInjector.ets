import { common } from '@kit.AbilityKit';
import { BookDao } from '../../../database/dao/BookDao';
import { LocalBook, LocalBookState, LocalBookSyncStatus } from '../../../database/entity/LocalBook';

export class MockDataInjector {
  /**
   * Inject 3 representative books for local-first UI testing.
   * Safe to call repeatedly: existing records with same fileHash are skipped.
   */
  public static async injectMockBooks(): Promise<void> {
    const context: common.UIAbilityContext = getContext() as common.UIAbilityContext;
    const dao: BookDao = BookDao.getInstance();
    await dao.init(context);

    const now: number = Date.now();
    const mockBooks: LocalBook[] = [
      {
        title: 'Mock Book A - Local Synced',
        author: 'Mock Author A',
        coverUrl: '',
        localCoverPath: `${context.filesDir}/covers/mock_cover_a.jpg`,
        fileHash: 'mock_sha256_book_a_synced',
        fileUrl: 'https://mock.oss.com/book-a.epub',
        format: 'EPUB',
        fileName: 'mock-a.epub',
        fileSize: 1_200_321,
        totalCatalogCount: 42,
        readerBookKey: 'sha256:mock_sha256_book_a_synced',
        localPath: `${context.filesDir}/books/mock-a.epub`,
        localState: LocalBookState.LOCAL_AVAILABLE,
        syncStatus: LocalBookSyncStatus.SYNCED,
        bookId: 'mock-book-id-a',
        createdAt: now - 90_000,
        updatedAt: now - 60_000
      },
      {
        title: 'Mock Book B - Pending Sync',
        author: 'Mock Author B',
        coverUrl: '',
        localCoverPath: '',
        fileHash: 'mock_sha256_book_b_pending',
        fileUrl: '',
        format: 'EPUB',
        fileName: 'mock-b.epub',
        fileSize: 2_400_888,
        totalCatalogCount: 86,
        readerBookKey: 'sha256:mock_sha256_book_b_pending',
        localPath: `${context.filesDir}/books/mock-b.epub`,
        localState: LocalBookState.LOCAL_AVAILABLE,
        syncStatus: LocalBookSyncStatus.PENDING,
        bookId: '',
        createdAt: now - 50_000,
        updatedAt: now - 30_000
      },
      {
        title: 'Mock Book C - Cloud Only',
        author: 'Mock Author C',
        coverUrl: 'https://mock.oss.com/cover-c.jpg',
        localCoverPath: '',
        fileHash: 'mock_sha256_book_c_cloud',
        fileUrl: 'https://mock.oss.com/book-c.epub',
        format: 'EPUB',
        fileName: 'mock-c.epub',
        fileSize: 3_100_456,
        totalCatalogCount: 120,
        readerBookKey: 'sha256:mock_sha256_book_c_cloud',
        localPath: '',
        localState: LocalBookState.CLOUD_ONLY,
        syncStatus: LocalBookSyncStatus.SYNCED,
        bookId: 'mock-book-id-c',
        createdAt: now - 20_000,
        updatedAt: now - 10_000
      }
    ];

    for (const book of mockBooks) {
      const exists: LocalBook | null = await dao.findByFileHash(book.fileHash);
      if (!exists) {
        await dao.insert(book);
      }
    }
  }
}
