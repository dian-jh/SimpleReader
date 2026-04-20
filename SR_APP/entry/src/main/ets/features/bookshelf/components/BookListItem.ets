import { LocalBook, LocalBookState } from '../../../database/entity/LocalBook';

@Component
export struct BookListItem {
  @Prop book: LocalBook = {} as LocalBook;

  build() {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(this.resolveCover())
          .width(56)
          .height(76)
          .borderRadius(6)
          .objectFit(ImageFit.Cover)

        if (this.book.localState === LocalBookState.CLOUD_ONLY) {
          Text('\u2601')
            .fontSize(12)
            .fontColor(Color.White)
            .width(20)
            .height(20)
            .textAlign(TextAlign.Center)
            .backgroundColor('#88000000')
            .borderRadius(10)
            .margin({ top: 4, right: 4 })
        }
      }

      Column({ space: 4 }) {
        Text(this.book.title || 'Untitled')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor('#FFFFFF')

        Text(this.book.author || 'Unknown Author')
          .fontSize(14)
          .fontColor('#A7A7A7')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`${this.book.totalCatalogCount || 0} chapters`)
          .fontSize(13)
          .fontColor('#7A7A7A')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('...')
        .fontSize(20)
        .fontColor('#8C8C8C')
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  private resolveCover(): ResourceStr {
    const cover: string = this.book.localCoverPath || this.book.coverUrl || '';
    return cover.length > 0 ? cover : $r('app.media.startIcon');
  }
}
