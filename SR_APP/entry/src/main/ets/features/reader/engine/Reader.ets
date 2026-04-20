import { webview } from '@kit.ArkWeb';

class ReaderBridge {
  private owner: Reader;

  constructor(owner: Reader) {
    this.owner = owner;
  }

  onReady(): void {
    this.owner.onWebReady();
  }

  onProgressChange(cfi: string, percentage: number): void {
    this.owner.onProgressChange(cfi, percentage);
  }

  onError(message: string): void {
    this.owner.onWebError(message);
  }
}

@Component
export struct Reader {
  @Prop localPath: string = '';
  @Prop lastLocator: string = '';

  @State private pageReady: boolean = false;
  @State private errorText: string = '';
  @State private progressText: string = '';

  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: ReaderBridge = new ReaderBridge(this);

  build() {
    Stack() {
      Web({ src: $rawfile('reader/viewer.html'), controller: this.controller })
        .domStorageAccess(true)
        .fileAccess(true)
        .javaScriptAccess(true)
        .onPageEnd(() => {
          this.pageReady = true;
          this.callWebInit();
        })
        .javaScriptProxy({
          object: this.bridge,
          name: 'ArkTSBridge',
          methodList: ['onReady', 'onProgressChange', 'onError'],
          controller: this.controller
        })
        .width('100%')
        .height('100%');

      Row() {
        Column().width('30%').height('100%')
          .onClick(() => this.controller.runJavaScript('prevPage()'));
        Column().width('40%').height('100%');
        Column().width('30%').height('100%')
          .onClick(() => this.controller.runJavaScript('nextPage()'));
      }
      .width('100%')
      .height('100%');

      Column({ space: 6 }) {
        if (this.progressText.length > 0) {
          Text(this.progressText)
            .fontSize(12)
            .fontColor('#FFFFFF');
        }
        if (this.errorText.length > 0) {
          Text(this.errorText)
            .fontSize(12)
            .fontColor('#FF9C9C');
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .backgroundColor('#66000000')
      .borderRadius(8)
      .margin({ top: 16, left: 12, right: 12 })
      .visibility((this.progressText.length > 0 || this.errorText.length > 0) ? Visibility.Visible : Visibility.None);
    }
    .width('100%')
    .height('100%');
  }

  onWebReady(): void {
    this.errorText = '';
  }

  onProgressChange(cfi: string, percentage: number): void {
    const pct: string = `${(percentage * 100).toFixed(2)}%`;
    this.progressText = `${pct} | ${cfi}`;
  }

  onWebError(message: string): void {
    this.errorText = message;
  }

  private callWebInit(): void {
    if (!this.pageReady) {
      return;
    }
    const localPathEscaped: string = this.escapeJsString(this.localPath);
    const locatorEscaped: string = this.escapeJsString(this.lastLocator);
    const script: string = `window.initReader("${localPathEscaped}", "${locatorEscaped}")`;
    this.controller.runJavaScript(script);
  }

  private escapeJsString(raw: string): string {
    return raw
      .replace(/\\/g, '\\\\')
      .replace(/"/g, '\\"')
      .replace(/\r/g, '')
      .replace(/\n/g, '\\n');
  }
}
