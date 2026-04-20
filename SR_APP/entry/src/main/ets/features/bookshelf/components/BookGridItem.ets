import { LocalBook, LocalBookState } from '../../../database/entity/LocalBook';

@Component
export struct BookGridItem {
  @Prop book: LocalBook = {} as LocalBook;

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(this.resolveCover())
          .width('100%')
          .aspectRatio(0.72)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)

        if (this.book.localState === LocalBookState.CLOUD_ONLY) {
          Text('\u2601')
            .fontSize(14)
            .fontColor(Color.White)
            .width(22)
            .height(22)
            .textAlign(TextAlign.Center)
            .backgroundColor('#88000000')
            .borderRadius(11)
            .margin({ top: 6, right: 6 })
        }
      }

      Text(this.book.title || 'Untitled')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // Keep a bottom progress slot in grid mode.
      Row({ space: 6 }) {
        Stack() {
          Row()
            .width('100%')
            .height(3)
            .backgroundColor('#2D2D2D')
            .borderRadius(2)

          Row()
            .width(this.book.localState === LocalBookState.LOCAL_AVAILABLE ? '12%' : '0%')
            .height(3)
            .backgroundColor('#A7A7A7')
            .borderRadius(2)
        }
        .layoutWeight(1)

        Text(`${this.book.totalCatalogCount || 0}`)
          .fontSize(11)
          .fontColor('#7A7A7A')
      }
      .width('100%')
    }
    .width('100%')
  }

  private resolveCover(): ResourceStr {
    const cover: string = this.book.localCoverPath || this.book.coverUrl || '';
    return cover.length > 0 ? cover : $r('app.media.startIcon');
  }
}
