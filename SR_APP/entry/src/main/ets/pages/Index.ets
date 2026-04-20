import { BookshelfPage } from '../features/bookshelf/pages/BookshelfPage';
import { MockDataInjector } from '../features/bookshelf/mock/MockDataInjector';

@Entry
@Component
struct Index {
  // 当前选中的 Tab 索引，默认设为 1（直接显示书库页方便我们测试）
  @State currentIndex: number = 1;

  // 🌟 开发调试开关：上线前改为 false
  private readonly IS_DEBUG: boolean = false;

  // 组件即将出现时触发的生命周期函数
  aboutToAppear() {
    if (this.IS_DEBUG) {
      console.info('【App Init】调试模式已开启，正在注入 Mock 假数据...');
      MockDataInjector.injectMockBooks();
    }
  }

  // 自定义底部的 Tab 按钮样式
  @Builder TabBuilder(title: string, targetIndex: number) {
    Column() {
      // 真实项目中这里应该是一个 Image 图标和一个 Text，这里做简化展示
      Text(title)
        .fontColor(this.currentIndex === targetIndex ? '#E5E5EA' : '#8E8E93') // 苹果暗黑模式的经典灰白色
        .fontSize(12)
        .fontWeight(this.currentIndex === targetIndex ? FontWeight.Medium : FontWeight.Normal)
        .margin({ top: 4 })
    }
    .width('100%')
    .height(50)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentIndex = targetIndex;
    })
  }

  build() {
    // BarPosition.End 表示导航栏在底部
    Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {

      // 1. 主页 (前端 E 的领地，目前是占位符)
      TabContent() {
        Column() {
          Text('主页模块 (待开发)')
            .fontSize(20).fontColor(Color.White)
        }.width('100%').height('100%').backgroundColor(Color.Black).justifyContent(FlexAlign.Center)
      }
      .tabBar(this.TabBuilder('主页', 0))

      // 2. 书库 (前端 C 的领地，挂载我们刚写好的真实页面！)
      TabContent() {
        BookshelfPage()
      }
      .tabBar(this.TabBuilder('书库', 1))

      // 3. 搜索 (待开发)
      TabContent() {
        Column() {
          Text('搜索模块 (待开发)')
            .fontSize(20).fontColor(Color.White)
        }.width('100%').height('100%').backgroundColor(Color.Black).justifyContent(FlexAlign.Center)
      }
      .tabBar(this.TabBuilder('搜索', 2))

    }
    .scrollable(false) // 苹果风格通常不允许左右滑动切换主 Tab
    .backgroundColor(Color.Black)
    .onChange((index: number) => {
      this.currentIndex = index;
    })
  }
}