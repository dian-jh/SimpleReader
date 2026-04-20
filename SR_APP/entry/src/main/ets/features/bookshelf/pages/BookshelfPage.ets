import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { webview } from '@kit.ArkWeb';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { BookDao } from '../../../database/dao/BookDao';
import { LocalBook, LocalBookState, LocalBookSyncStatus } from '../../../database/entity/LocalBook';
import { BookImportUtil, BookSandboxFile } from '../utils/BookImportUtil';
import { SyncService } from '../services/SyncService';
import { BookListItem } from '../components/BookListItem';
import { BookGridItem } from '../components/BookGridItem';

interface EpubParsePayload {
  title: string;
  author: string;
  coverBase64: string;
  tocJson: string;
}

class BookshelfParseBridge {
  private owner: BookshelfPage;

  constructor(owner: BookshelfPage) {
    this.owner = owner;
  }

  onParseSuccess(jsonStr: string): void {
    this.owner.onParseSuccess(jsonStr);
  }

  onParseError(message: string): void {
    this.owner.onParseError(message);
  }
}

enum ShelfViewMode {
  LIST = 'list',
  GRID = 'grid'
}

@Component
export struct BookshelfPage {
  @State private books: LocalBook[] = [];
  @State private viewMode: ShelfViewMode = ShelfViewMode.LIST;
  @State private loading: boolean = false;
  @State private parserReady: boolean = false;
  @State private parsingBook: boolean = false;

  private readonly bookDao: BookDao = BookDao.getInstance();
  private syncService?: SyncService;
  private parserController: webview.WebviewController = new webview.WebviewController();
  private parseBridge: BookshelfParseBridge = new BookshelfParseBridge(this);
  private pendingImportTask: BookSandboxFile | null = null;

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

      this.HiddenParserWebBuilder();
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .padding({ top: 18 });
  }

  @Builder
  private HeaderBuilder() {
    Row() {
      Text('书库')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF');

      Blank();

      Button('...')
        .fontSize(20)
        .fontColor('#DADADA')
        .backgroundColor('#1B1B1B')
        .width(36)
        .height(36)
        .borderRadius(18)
        .onClick(() => {
          this.showMoreMenu();
        });
    }
    .padding({ left: 16, right: 16 })
    .width('100%');
  }

  @Builder
  private ShelfEntryBuilder() {
    Row() {
      Text('藏书')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#EDEDED');

      Blank();

      Text('>')
        .fontSize(18)
        .fontColor('#8D8D8D');
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 10 })
    .border({
      width: { bottom: 1 },
      color: '#1A1A1A'
    });
  }

  @Builder
  private ViewSwitcherBuilder() {
    Row({ space: 10 }) {
      Button('列表')
        .height(30)
        .fontSize(13)
        .fontColor(this.viewMode === ShelfViewMode.LIST ? '#101010' : '#DADADA')
        .backgroundColor(this.viewMode === ShelfViewMode.LIST ? '#E7E7E7' : '#1F1F1F')
        .borderRadius(15)
        .onClick(() => {
          this.switchView(ShelfViewMode.LIST);
        });

      Button('网格')
        .height(30)
        .fontSize(13)
        .fontColor(this.viewMode === ShelfViewMode.GRID ? '#101010' : '#DADADA')
        .backgroundColor(this.viewMode === ShelfViewMode.GRID ? '#E7E7E7' : '#1F1F1F')
        .borderRadius(15)
        .onClick(() => {
          this.switchView(ShelfViewMode.GRID);
        });

      Blank();
    }
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .width('100%');
  }

  @Builder
  private ListBuilder() {
    List({ space: 2 }) {
      ForEach(this.books, (book: LocalBook) => {
        ListItem() {
          BookListItem({ book: book });
        }
        .backgroundColor('#000000')
        .onClick(() => {
          this.openReader(book);
        });
      }, (book: LocalBook) => this.keyOf(book));
    }
    .layoutWeight(1)
    .width('100%');
  }

  @Builder
  private GridBuilder() {
    Grid() {
      ForEach(this.books, (book: LocalBook) => {
        GridItem() {
          BookGridItem({ book: book });
        }
        .onClick(() => {
          this.openReader(book);
        });
      }, (book: LocalBook) => this.keyOf(book));
    }
    .layoutWeight(1)
    .width('100%')
    .columnsTemplate('1fr 1fr')
    .columnsGap(14)
    .rowsGap(18)
    .padding({ left: 16, right: 16, top: 8, bottom: 16 });
  }

  @Builder
  private EmptyBuilder() {
    Column({ space: 10 }) {
      Text('暂无图书')
        .fontSize(18)
        .fontColor('#B0B0B0');
      Text('点击右上角 ... 导入本地图书')
        .fontSize(13)
        .fontColor('#6E6E6E');
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .width('100%');
  }

  @Builder
  private HiddenParserWebBuilder() {
    Web({
      src: $rawfile('reader/index.html'),
      controller: this.parserController
    })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(true)
      .onPageEnd(() => {
        this.parserReady = true;
        this.tryStartHeadlessParse();
      })
      .javaScriptProxy({
        object: this.parseBridge,
        name: 'ArkTSBridge',
        methodList: ['onParseSuccess', 'onParseError'],
        controller: this.parserController
      })
      .width(1)
      .height(1)
      .opacity(0)
      .position({ x: -1000, y: -1000 })
      .hitTestBehavior(HitTestMode.None);
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

  private switchView(mode: ShelfViewMode): void {
    if (this.viewMode === mode) {
      return;
    }
    animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.viewMode = mode;
    });
  }

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
      title: '更多',
      buttons: [
        { text: '导入本地图书', color: '#111111' },
        {
          text: this.viewMode === ShelfViewMode.LIST
            ? '切换为网格视图'
            : '切换为列表视图',
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
    if (this.parsingBook) {
      promptAction.showToast({ message: '已有图书正在解析，请稍候' });
      return;
    }

    try {
      const context: common.UIAbilityContext = this.getAbilityContext();
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['Books(.epub)|.epub'];

      const uris: string[] = await docPicker.select(options);
      if (uris.length === 0) {
        return;
      }

      const sandboxFile: BookSandboxFile = await BookImportUtil.prepareSandboxFile(context, uris[0]);
      const duplicated: LocalBook | null = await this.bookDao.findByFileHash(sandboxFile.fileHash);
      if (duplicated) {
        promptAction.showToast({ message: '该图书已导入书架' });
        return;
      }

      this.pendingImportTask = sandboxFile;
      this.parsingBook = true;
      promptAction.showToast({ message: '正在解析图书信息...' });
      this.tryStartHeadlessParse();
    } catch (e) {
      const err: Error = e instanceof Error ? e : new Error(String(e));
      this.parsingBook = false;
      this.pendingImportTask = null;
      promptAction.showToast({ message: `导入失败: ${err.message}` });
    }
  }

  onParseSuccess(jsonStr: string): void {
    void this.finishImportByParsedMetadata(jsonStr);
  }

  onParseError(message: string): void {
    this.parsingBook = false;
    this.pendingImportTask = null;
    const text: string = message.trim().length > 0 ? message : 'EPUB 解析失败';
    promptAction.showToast({ message: `导入失败: ${text}` });
  }

  private tryStartHeadlessParse(): void {
    if (!this.parserReady || !this.pendingImportTask || !this.parsingBook) {
      return;
    }

    try {
      const realPath: string = this.pendingImportTask.sandboxPath;
      const file: fs.File = fs.openSync(realPath, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);

      if (Number(stat.size) <= 0) {
        fs.closeSync(file);
        throw new Error('沙箱文件大小为 0，文件复制失败');
      }

      const buf: ArrayBuffer = new ArrayBuffer(Number(stat.size));
      fs.readSync(file.fd, buf);
      fs.closeSync(file);

      const base64Helper: util.Base64Helper = new util.Base64Helper();
      const base64Str: string = base64Helper.encodeToStringSync(new Uint8Array(buf));
      const script: string = `window.parseEpubBase64("${base64Str}")`;
      this.parserController.runJavaScript(script);
    } catch (e) {
      const err: Error = e instanceof Error ? e : new Error(String(e));
      this.onParseError(`读取文件转码失败: ${err.message}`);
    }
  }

  private async finishImportByParsedMetadata(jsonStr: string): Promise<void> {
    const task: BookSandboxFile | null = this.pendingImportTask;
    if (!task) {
      this.parsingBook = false;
      return;
    }

    try {
      const parsed: EpubParsePayload = this.parsePayload(jsonStr);
      const now: number = Date.now();
      const finalTitle: string = parsed.title.length > 0 ? parsed.title : task.fallbackTitle;
      const totalCatalogCount: number = this.countTocItems(parsed.tocJson);

      const localBook: LocalBook = {
        title: finalTitle,
        author: parsed.author,
        coverUrl: parsed.coverBase64,
        localCoverPath: '',
        fileHash: task.fileHash,
        fileUrl: '',
        format: task.format,
        fileName: task.fileName,
        fileSize: task.fileSize,
        totalCatalogCount: totalCatalogCount,
        readerBookKey: task.readerBookKey,
        localPath: task.sandboxPath,
        localState: LocalBookState.LOCAL_AVAILABLE,
        syncStatus: LocalBookSyncStatus.PENDING,
        bookId: '',
        createdAt: now,
        updatedAt: now,
        toc: parsed.tocJson
      };

      await this.bookDao.insert(localBook);
      this.books = await this.bookDao.listAll(true);
      promptAction.showToast({ message: '导入成功' });
      this.triggerBackgroundReconcile();
    } catch (e) {
      const err: Error = e instanceof Error ? e : new Error(String(e));
      promptAction.showToast({ message: `导入失败: ${err.message}` });
    } finally {
      this.pendingImportTask = null;
      this.parsingBook = false;
    }
  }

  private parsePayload(jsonStr: string): EpubParsePayload {
    const raw: Record<string, string | number | boolean | null> =
      JSON.parse(jsonStr) as Record<string, string | number | boolean | null>;

    const title: string = typeof raw.title === 'string' ? raw.title.trim() : '';
    const author: string = typeof raw.author === 'string' ? raw.author.trim() : '';
    const coverBase64: string = typeof raw.coverBase64 === 'string' ? raw.coverBase64 : '';
    const tocJson: string = typeof raw.tocJson === 'string' ? raw.tocJson : '';

    return {
      title: title,
      author: author,
      coverBase64: coverBase64,
      tocJson: tocJson
    };
  }

  private countTocItems(tocJson: string): number {
    if (tocJson.trim().length === 0) {
      return 0;
    }
    try {
      const parsed: Object = JSON.parse(tocJson) as Object;
      if (Array.isArray(parsed)) {
        return parsed.length;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  private openReader(book: LocalBook): void {
    const path: string = book.localPath ? book.localPath.trim() : '';
    if (path.length === 0 || book.localState !== LocalBookState.LOCAL_AVAILABLE) {
      promptAction.showToast({ message: '该图书本地文件不可用' });
      return;
    }

    try {
      fs.accessSync(path);
    } catch (_) {
      promptAction.showToast({ message: '本地图书文件不存在，请重新导入' });
      return;
    }

    router.pushUrl({
      url: 'pages/Reader',
      params: {
        localPath: path,
        lastLocator: ''
      }
    }).catch(() => {
      promptAction.showToast({ message: '打开阅读页失败' });
    });
  }

  private getSyncService(): SyncService {
    if (!this.syncService) {
      this.syncService = new SyncService(this.getAbilityContext(), '');
    }
    return this.syncService;
  }

  private getAbilityContext(): common.UIAbilityContext {
    const hostContext: Object | undefined = this.getUIContext().getHostContext();
    if (!hostContext) {
      throw new Error('host context is undefined');
    }
    return hostContext as common.UIAbilityContext;
  }

  private keyOf(book: LocalBook): string {
    return String(book.id ?? book.fileHash ?? `${book.fileName}_${book.createdAt}`);
  }
}
