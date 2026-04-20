import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import fs from '@ohos.file.fs';
import util from '@ohos.util';

interface ReaderRouteParams {
  localPath?: string;
  lastLocator?: string;
  bookTitle?: string; // 新增：接收书架传来的书名
}

class ArkTSBridge {
  private owner: ReaderPage;
  constructor(owner: ReaderPage) { this.owner = owner; }
  onReady(): void { this.owner.onWebReady(); }
  onProgressChange(cfi: string, percentage: number): void { this.owner.onProgressChanged(cfi, percentage); }
  onError(message: string): void { this.owner.onWebError(message); }
}

@Component
export struct ReaderPage {
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: ArkTSBridge = new ArkTSBridge(this);

  @State private localPath: string = '';
  @State private lastLocator: string = '';
  @State private bookTitle: string = '阅读';

  @State private progressText: string = '';
  @State private readPercentage: number = 0; // 0 - 100 的数字，用于进度条
  @State private errorText: string = '';
  @State private pageReady: boolean = false;

  // 【核心状态】：控制上下菜单栏的显隐
  @State private showMenu: boolean = false;

  aboutToAppear(): void {
    const params: ReaderRouteParams = router.getParams() as Object as ReaderRouteParams;
    this.localPath = params.localPath ?? '';
    this.lastLocator = params.lastLocator ?? '';
    this.bookTitle = params.bookTitle ?? '阅读';
  }

  build() {
    Stack() {
      // ==========================================
      // 第一层：阅读器核心引擎 (最底层)
      // ==========================================
      Web({
        src: $rawfile('reader/viewer.html'),
        controller: this.controller
      })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        // 【新增】：强制 Web 组件的背景变为透明，让下层的 #F4F4F4 透上来
        .backgroundColor(Color.White)
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
        .height('100%')

      // ==========================================
      // 第二层：隐形交互控制层 (覆盖在 Web 之上)
      // ==========================================
      Row() {
        // 左侧 30%：上一页
        Column().width('30%').height('100%')
          .onClick(() => this.controller.runJavaScript('prevPage()'))

        // 中间 40%：呼出/隐藏菜单
        Column().width('40%').height('100%')
          .onClick(() => {
            // 加入平滑过渡动画
            animateTo({ duration: 250, curve: Curve.FastOutSlowIn }, () => {
              this.showMenu = !this.showMenu;
            });
          })

        // 右侧 30%：下一页
        Column().width('30%').height('100%')
          .onClick(() => this.controller.runJavaScript('nextPage()'))
      }
      .width('100%')
      .height('100%')
      // 【新增 1】：明确指定为透明，防止系统自动填充黑色
      .backgroundColor(Color.Transparent)
      // 【新增 2】：强制 Z-Index 提升，确保它盖在 Web 组件上方
      .zIndex(10)

      // ==========================================
      // 第三层：沉浸式阅读时的底部小进度水印
      // ==========================================
      if (!this.showMenu && this.progressText.length > 0) {
        Text(this.progressText)
          .fontSize(10)
          .fontColor('#999999')
          .position({ x: 16, y: '100%' })
          .translate({ y: '-28px' }) // 距离底部留点缝隙
      }

      // ==========================================
      // 第四层：顶部系统菜单栏
      // ==========================================
      if (this.showMenu) {
        Row() {
          Text('〈 返回')
            .fontSize(16).fontColor('#333333').padding(16)
            .onClick(() => router.back())

          Text(this.bookTitle)
            .fontSize(16).fontColor('#333333').fontWeight(FontWeight.Medium)
            .layoutWeight(1).textAlign(TextAlign.Center)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

          // 占位符，保证标题绝对居中
          Text('        ').padding(16)
        }
        .width('100%').height(60)
        .backgroundColor('#F9F9F9')
        .alignItems(VerticalAlign.Center)
        .position({ x: 0, y: 0 })
        // 入场和出场动画：向上滑动 60px
        .transition(TransitionEffect.translate({ y: -60 }).animation({ duration: 250 }))
      }

      // ==========================================
      // 第五层：底部设置与控制菜单栏
      // ==========================================
      if (this.showMenu) {
        Column() {
          // 1. 进度条区域
          Row({ space: 12 }) {
            Text('上一章').fontSize(12).fontColor('#666666')
            Slider({ value: this.readPercentage, min: 0, max: 100, style: SliderStyle.OutSet })
              .layoutWeight(1)
              .blockColor('#FFFFFF')
              .trackColor('#EAEAEA')
              .selectedColor('#333333')
              .onChange((value: number, mode: SliderChangeMode) => {
                // TODO: 拖动松手时，调用 js 跳转到对应百分比
              })
            Text('下一章').fontSize(12).fontColor('#666666')
          }
          .width('100%').padding({ left: 20, right: 20, top: 16, bottom: 8 })

          // 2. 功能按钮区域 (使用字符图标模拟 UI)
          Row() {
            this.MenuButton('≡', '目录', () => { /* TODO: 展开侧边目录 */ })
            this.MenuButton('☼', '亮度', () => { /* TODO: 弹出亮度面板 */ })
            this.MenuButton('Aa', '设置', () => { /* TODO: 弹出字体/排版面板 */ })
            this.MenuButton('☾', '夜间', () => { /* TODO: 切换 Web 的 CSS 主题 */ })
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceAround)
          .padding({ bottom: 32, top: 8 }) // bottom 留足空间适配全面屏手势
        }
        .width('100%')
        .backgroundColor('#F9F9F9')
        .position({ x: 0, y: '100%' })
        .translate({ y: '-100%' })
        // 入场和出场动画：向下滑动退出
        .transition(TransitionEffect.translate({ y: 150 }).animation({ duration: 250 }))
      }

      // 错误提示蒙层
      if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontSize(12).fontColor('#FF9C9C').backgroundColor('#88000000')
          .padding(8).borderRadius(4)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }

  // 辅助构建器：菜单图标按钮
  @Builder
  MenuButton(icon: string, text: string, action: () => void) {
    Column({ space: 6 }) {
      Text(icon).fontSize(22).fontColor('#333333').fontWeight(FontWeight.Bold)
      Text(text).fontSize(10).fontColor('#666666')
    }
    .onClick(action)
    .padding(8)
  }

  onWebReady(): void { this.errorText = ''; }
  onWebError(message: string): void { this.errorText = message; }

  onProgressChanged(cfi: string, percentage: number): void {
    const pct: string = `${(percentage * 100).toFixed(1)}%`;
    this.progressText = `${pct}`;
    this.readPercentage = percentage * 100;
    this.lastLocator = cfi;
  }

  private callWebInit(): void {
    if (!this.pageReady || !this.localPath) return;
    try {
      // ArkTS 侧读取文件转 Base64 (纯原生高性能方案)
      const file: fs.File = fs.openSync(this.localPath, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);

      const base64Helper = new util.Base64Helper();
      const base64Str = base64Helper.encodeToStringSync(new Uint8Array(buf));

      const locatorEscaped: string = this.escapeJsString(this.lastLocator);

      // 注意：请确保你的队友在 viewer.html 里写了 initReaderWithBase64 方法！
      const script: string = `window.initReaderWithBase64("${base64Str}", "${locatorEscaped}")`;
      this.controller.runJavaScript(script);
    } catch (e) {
      this.onWebError("书籍加载失败");
    }
  }

  private escapeJsString(raw: string): string {
    return raw.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\r/g, '').replace(/\n/g, '\\n');
  }
}