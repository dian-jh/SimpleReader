import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';

@Component
export struct Reader {
  @Prop bookFileName: string = '';
  controller: webview.WebviewController = new webview.WebviewController();

  build() {
    Stack() {
      Web({ src: $rawfile('viewer.html'), controller: this.controller })
        .domStorageAccess(true)
        .fileAccess(true)
        .javaScriptAccess(true) // 确保 JS 权限开启
        // 关键：监听 HTML 里的 console.log，直接输出到 DevEco 控制台
        .onConsole((event) => {
          console.info('WebView_Console: ' + event?.message);
          return false;
        })
        .onPageEnd(() => {
          if (this.bookFileName) {
            // 延迟 800ms 确保 HTML 里的 epub.js 脚本完全解析完毕
            setTimeout(() => {
              this.initEpubData(this.bookFileName);
            }, 800)
          }
        })
        .width('100%')
        .height('100%')

      // 交互层：左右透明点击
      Row() {
        Column().width('30%').height('100%')
          .onClick(() => this.controller.runJavaScript('prevPage()'))
        Column().width('40%').height('100%')
        Column().width('30%').height('100%')
          .onClick(() => this.controller.runJavaScript('nextPage()'))
      }
      .width('100%').height('100%')
    }
    .width('100%')
    .height('100%')
  }

  async initEpubData(fileName: string) {
    try {
      const resourceMgr = getContext(this).resourceManager;
      const fileData = await resourceMgr.getRawFileContent(fileName);
      console.info(`SimpleReader_Log: 文件读取成功，大小: ${fileData.byteLength}`);

      let base64Helper = new util.Base64Helper();
      let base64Str = base64Helper.encodeToStringSync(fileData);

      this.controller.runJavaScript(`loadBook("${base64Str}")`);
    } catch (err) {
      console.error(`SimpleReader_Log: 加载 [${fileName}] 失败，错误码: ${err.code}`);
    }
  }
}