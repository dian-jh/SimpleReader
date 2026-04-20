// 淇鐐癸細璺緞蹇呴』涓庝綘鐨勭洰褰曞畬鍏ㄤ竴鑷达紝娉ㄦ剰 features 鐨?s
import { Reader } from '../features/reader/engine/Reader';

@Entry
@Component
struct Index {
  // 纭繚 rawfile 鐩綍涓嬫湁杩欎釜鏂囦欢
  @State currentBookPath: string = 'book.epub';

  build() {
    Column() {
      // 椤堕儴鍘熺敓鐘舵€佹爮
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

      // 鏍稿績闃呰缁勪欢
      Column() {
        // 璋冪敤 Reader 缁勪欢
        Reader({ localPath: this.currentBookPath })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
