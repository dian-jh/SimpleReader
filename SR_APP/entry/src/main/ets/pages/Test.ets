// 修正点：路径必须与你的目录完全一致，注意 features 的 s
import { Reader } from '../features/reader/engine/Reader';

@Entry
@Component
struct Index {
  // 确保 rawfile 目录下有这个文件
  @State currentBookPath: string = 'book.epub';

  build() {
    Column() {
      // 顶部原生状态栏
      Row() {
        Text("SimpleReader")
          .fontSize(18)
          .fontColor('#E6E6E6')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .height(50)
      .backgroundColor('#2C2C2C')
      .padding({ left: 15 })

      // 核心阅读组件
      Column() {
        // 调用 Reader 组件
        Reader({ bookFileName: this.currentBookPath })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}