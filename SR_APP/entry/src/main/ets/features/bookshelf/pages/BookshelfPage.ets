import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { BookDao } from '../../../database/dao/BookDao';
import { LocalBook } from '../../../database/entity/LocalBook';
import { BookImportUtil } from '../utils/BookImportUtil';
import { SyncService } from '../services/SyncService';
import { BookListItem } from '../components/BookListItem';
import { BookGridItem } from '../components/BookGridItem';

enum ShelfViewMode {
  LIST = 'list',
  GRID = 'grid'
}

@Component
export struct BookshelfPage {
  @State private books: LocalBook[] = [];
  @State private viewMode: ShelfViewMode = ShelfViewMode.LIST;
  @State private loading: boolean = false;

  private readonly bookDao: BookDao = BookDao.getInstance();
  private syncService?: SyncService;

  aboutToAppear(): void {
    void this.bootstrap();
  }

  build() {
    Column() {
      this.HeaderBuilder();
      this.ShelfEntryBuilder();
      this.ViewSwitcherBuilder();

      if (this.books.length === 0 && !this.loading) {
        this.EmptyBuilder();
      } else if (this.viewMode === ShelfViewMode.LIST) {
        this.ListBuilder();
      } else {
        this.GridBuilder();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .padding({ top: 18 })
  }

  @Builder
  private HeaderBuilder() {
    Row() {
      Text('\u4E66\u5E93')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')

      Blank()

      Button('...')
        .fontSize(20)
        .fontColor('#DADADA')
        .backgroundColor('#1B1B1B')
        .width(36)
        .height(36)
        .borderRadius(18)
        .onClick(() => {
          this.showMoreMenu();
        })
    }
    .padding({ left: 16, right: 16 })
    .width('100%')
  }

  @Builder
  private ShelfEntryBuilder() {
    Row() {
      Text('\u85CF\u4E66')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#EDEDED')

      Blank()

      Text('>')
        .fontSize(18)
        .fontColor('#8D8D8D')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 10 })
    .border({
      width: { bottom: 1 },
      color: '#1A1A1A'
    })
  }

  @Builder
  private ViewSwitcherBuilder() {
    Row({ space: 10 }) {
      Button('\u5217\u8868')
        .height(30)
        .fontSize(13)
        .fontColor(this.viewMode === ShelfViewMode.LIST ? '#101010' : '#DADADA')
        .backgroundColor(this.viewMode === ShelfViewMode.LIST ? '#E7E7E7' : '#1F1F1F')
        .borderRadius(15)
        .onClick(() => {
          this.switchView(ShelfViewMode.LIST);
        })

      Button('\u7F51\u683C')
        .height(30)
        .fontSize(13)
        .fontColor(this.viewMode === ShelfViewMode.GRID ? '#101010' : '#DADADA')
        .backgroundColor(this.viewMode === ShelfViewMode.GRID ? '#E7E7E7' : '#1F1F1F')
        .borderRadius(15)
        .onClick(() => {
          this.switchView(ShelfViewMode.GRID);
        })

      Blank()
    }
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .width('100%')
  }

  @Builder
  private ListBuilder() {
    List({ space: 2 }) {
      ForEach(this.books, (book: LocalBook) => {
        ListItem() {
          BookListItem({ book: book })
        }
        .backgroundColor('#000000')
      }, (book: LocalBook) => this.keyOf(book))
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private GridBuilder() {
    Grid() {
      ForEach(this.books, (book: LocalBook) => {
        GridItem() {
          BookGridItem({ book: book })
        }
      }, (book: LocalBook) => this.keyOf(book))
    }
    .layoutWeight(1)
    .width('100%')
    .columnsTemplate('1fr 1fr')
    .columnsGap(14)
    .rowsGap(18)
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }

  @Builder
  private EmptyBuilder() {
    Column({ space: 10 }) {
      Text('\u6682\u65E0\u56FE\u4E66')
        .fontSize(18)
        .fontColor('#B0B0B0')
      Text('\u70B9\u51FB\u53F3\u4E0A\u89D2 ... \u5BFC\u5165\u672C\u5730\u56FE\u4E66')
        .fontSize(13)
        .fontColor('#6E6E6E')
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .width('100%')
  }

  private async bootstrap(): Promise<void> {
    await this.loadBooksFromLocal();
    this.triggerBackgroundReconcile();
  }

  private async loadBooksFromLocal(): Promise<void> {
    this.loading = true;
    try {
      await this.bookDao.init(this.getAbilityContext());
      this.books = await this.bookDao.listAll(true);
    } finally {
      this.loading = false;
    }
  }

  /**
   * Switch mode with conditional rendering and animateTo for smooth transition.
   * For structurally different trees (List vs Grid), conditional rendering is clearer and safer.
   */
  private switchView(mode: ShelfViewMode): void {
    if (this.viewMode === mode) {
      return;
    }
    animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.viewMode = mode;
    });
  }

  /**
   * UI reads from SQLite only:
   * - instant render in offline mode
   * - same rendering path before/after sync write-back
   */
  private triggerBackgroundReconcile(): void {
    const service: SyncService = this.getSyncService();
    void service.fetchCloudBooksAndUpdateLocal()
      .then(async () => {
        this.books = await this.bookDao.listAll(true);
      })
      .catch(() => {
      });
  }

  private showMoreMenu(): void {
    promptAction.showActionMenu({
      title: '\u66F4\u591A',
      buttons: [
        { text: '\u5BFC\u5165\u672C\u5730\u56FE\u4E66', color: '#111111' },
        {
          text: this.viewMode === ShelfViewMode.LIST
            ? '\u5207\u6362\u4E3A\u7F51\u683C\u89C6\u56FE'
            : '\u5207\u6362\u4E3A\u5217\u8868\u89C6\u56FE',
          color: '#111111'
        }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 0) {
        void this.handleImportBook();
      } else if (result.index === 1) {
        const target: ShelfViewMode = this.viewMode === ShelfViewMode.LIST ? ShelfViewMode.GRID : ShelfViewMode.LIST;
        this.switchView(target);
      }
    }).catch(() => {
    });
  }

  private async handleImportBook(): Promise<void> {
    try {
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.epub'];
      const uris: string[] = await docPicker.select(options);
      if (!uris || uris.length === 0) {
        return;
      }

      const localBook: LocalBook = await BookImportUtil.importBook(this.getAbilityContext(), uris[0]);
      await this.bookDao.insert(localBook);
      this.books = await this.bookDao.listAll(true);
      this.triggerBackgroundReconcile();
    } catch (e) {
      const err: Error = e instanceof Error ? e : new Error(String(e));
      promptAction.showToast({ message: `\u5BFC\u5165\u5931\u8D25: ${err.message}` });
    }
  }

  private getSyncService(): SyncService {
    if (!this.syncService) {
      this.syncService = new SyncService(this.getAbilityContext(), '');
    }
    return this.syncService;
  }

  private getAbilityContext(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private keyOf(book: LocalBook): string {
    return String(book.id ?? book.fileHash ?? `${book.fileName}_${book.createdAt}`);
  }
}
