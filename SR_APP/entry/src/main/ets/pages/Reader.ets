import { ReaderPage } from '../features/reader/pages/ReaderPage';

@Entry
@Component
struct ReaderRoutePage {
  build() {
    Column() {
      ReaderPage()
    }
    .width('100%')
    .height('100%')
  }
}
