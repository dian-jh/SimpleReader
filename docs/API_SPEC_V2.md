# AppleReader API 文档（V2-RK 简化冻结版）

> 生效日期：2026-04-18  
> 适用端：ArkTS（HarmonyOS NEXT）+ Reader Kit + 后端 CRUD 服务  
> 状态：Frozen（7 人并发开发按此执行）



**整体需求**

用户可以自行上传EPUB格式书籍。并且切换设备之后将本账号的书籍同步到新设备。

本地优先、云端同步

- 用户在app上进行上传，使用Reader Kit进行解析，直接进行阅读
- 在后台进行异步的上传到后端的服务器中
- 用户切换设备，进入书架查询拥有书籍，点击云端同步到前端
- 使用Reader Kit并通过后端的接口，直接操纵本地书籍文件

---

## 1. 变更背景与边界

1. 书籍解析、排版、翻页交互、目录跳转改为前端 Reader Kit 完成。
2. 后端不再负责 EPUB 解压与章节正文解析，不再维护解析任务状态机。
3. 后端仅负责：用户、书架元数据、目录快照、阅读进度、标注、目标统计等 CRUD。

Reader Kit 参考（官方）：

- [Reader Kit 介绍](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/reader-introduction)
- [Reader Kit 书籍信息](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/reader-book-info)
- [Reader Kit 目录列表](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/reader-catalog-list)

说明：本 API 不绑定 Reader Kit 具体函数名，以官方文档和 SDK 实际版本为准。

---

## 2. 通用规范

### 2.1 基础

- Base URL：`/api/v1`
- 鉴权：`Authorization: Bearer <accessToken>`（登录/注册接口除外）
- Content-Type：`application/json`（上传图片可用 `multipart/form-data`）

### 2.2 幂等头（仅必要接口）

- `Idempotency-Key` 必传接口：
  - `POST /api/v1/read-sessions/finish`
  - `POST /api/v1/library/books`
  - `POST /api/v1/books/{bookId}/annotations/sync`

### 2.3 响应约定（不做统一包装）

1. 成功：直接返回业务对象。
2. 失败：HTTP 状态码 + 错误体。

错误体示例：

```json
{
  "errorCode": "READ_PROGRESS_CONFLICT",
  "message": "version mismatch"
}
```

### 2.4 时间规则

1. 日统计统一按 `Asia/Shanghai`（北京时间）计算。
2. 时间字段使用 ISO 8601，示例：`2026-04-18T08:03:15+08:00`。

### 2.5 分页

请求参数：

- `pageNo`：从 1 开始
- `pageSize`：默认 20，最大 100

分页响应：

```json
{
  "items": [],
  "pageNo": 1,
  "pageSize": 20,
  "total": 200
}
```

### 2.6 错误码

- `UNAUTHORIZED`
- `FORBIDDEN`
- `VALIDATION_ERROR`
- `RESOURCE_NOT_FOUND`
- `RESOURCE_ALREADY_EXISTS`
- `IDEMPOTENCY_CONFLICT`
- `READ_PROGRESS_CONFLICT`
- `ANNOTATION_SYNC_CONFLICT`
- `RATE_LIMITED`
- `INTERNAL_ERROR`

### 2.7 HTTP 状态码

- `200` 成功
- `201` 创建成功
- `400` 参数错误
- `401` 未登录
- `403` 无权限
- `404` 资源不存在
- `409` 冲突
- `429` 频控
- `500` 服务异常

---

## 3. 表结构（原始PRD + Reader Kit实施版）

### 3.1 原始 PRD 表结构（保留，用于评审对照）

#### 3.1.1 用户模块

`User`：

- Id
- Username
- Account
- PasswordHash
- AvatarUrl
- CreateTime

#### 3.1.2 阅读目标与统计模块

`ReadingTimeDaily`：

- Id
- UserId
- Date
- Duration
- TargetDuration
- IsAchieved

`UserReadingStats`：

- Id
- UserId
- CurrentStreakCount
- LongestStreakCount
- LastAchieveDate

#### 3.1.3 云端书库与调度模块（PRD原始）

`Books`：

- Id
- Title
- Author
- CoverUrl
- Intro
- Status
- TotalChapters
- FileUri
- Format

`Chapters`：

- Id
- BookId
- Title
- OrderNum
- WordCount
- ResourcePath
- ParentId
- DepthLevel

`BookParsingTasks`：

- TaskId
- UserId
- OriginalFileName
- Status
- Progress
- BookId
- ErrorMessage
- CreateTime

`ReadingProgress`：

- UserId
- BookId
- LastCatalogId
- LastPosition
- UpdateTime

#### 3.1.4 多维藏书夹模块

`UserCollections`：

- Id
- UserId
- Name
- SortOrder
- CreateTime

`BookCollectionMapping`：

- CollectionId
- BookId
- UserId
- AddTime

#### 3.1.5 标注同步模块

`Annotations`：

- Id
- UserId
- BookId
- CatalogId
- Locator
- QuoteText
- NoteContent
- Style
- Type
- Status
- UpdatedAt
- CreateTime

### 3.2 Reader Kit 实施版表结构（本项目落地以此为准）

说明：前端使用 Reader Kit 负责书籍信息读取、目录读取、内容渲染与交互，后端只做元数据与业务数据 CRUD。

#### 3.2.1 需要废弃/替代

1. `Books.FileUri`：不再作为“后端解析入口”，仅可保留为客户端文件引用或同步标识字段。

#### 3.2.2 Books（调整后）

| 字段 | 类型 | 说明 |
|---|---|---|
| Id | UUID | 主键 |
| UserId | UUID | 所属用户 |
| Title | Varchar(500) | 书名（Reader Kit 书籍信息） |
| FileHash | VarChar(64) | 文件的MD5或SHA256哈希值(多个用户上传同一本书，可以对比FileHash实现秒传) |
| FileUrl | Varchar(256) | 云端书籍绝对地址 |
| Author | Varchar(256) | 作者 |
| CoverUrl | Text | 封面（可空） |
| Intro | Text | 简介（可空） |
| Format | Varchar(16) | EPUB/TXT/MOBI/AZW/AZW3 |
| ReaderBookKey | Varchar(128) | 客户端书籍唯一键（同一用户唯一） |
| FileName | Varchar(255) | 原文件名 |
| FileSize | BigInt | 文件大小 |
| TotalCatalogCount | Int | 目录项总数 |
| LastReadAt | DateTime | 最近阅读时间 |
| CreateTime | DateTime | 创建时间 |
| UpdateTime | DateTime | 更新时间 |
| DeletedAt | DateTime? | 软删时间 |

索引建议：

1. `UNIQUE(UserId, ReaderBookKey)` 防止重复导入。
2. `INDEX(UserId, LastReadAt DESC)` 支撑主页“之前读过”。

#### 3.2.3 BookCatalogs（新表，替代 Chapters）

| 字段 | 类型 | 说明 |
|---|---|---|
| Id | UUID | 主键 |
| BookId | UUID | 关联图书 |
| ParentId | UUID? | 父目录 |
| Title | Varchar(500) | 目录标题 |
| OrderNum | Int | 排序 |
| DepthLevel | Int | 层级 |
| Href | Varchar(500)? | Reader Kit 目录项定位（可空） |
| Locator | Varchar(1000)? | 客户端恢复定位值（可空） |
| CreateTime | DateTime | 创建时间 |
| UpdateTime | DateTime | 更新时间 |

索引建议：

1. `INDEX(BookId, OrderNum)`
2. `INDEX(BookId, ParentId)`

#### 3.2.4 ReadingProgress（保留并标准化）

| 字段 | 类型 | 说明 |
|---|---|---|
| UserId | UUID | 复合主键 |
| BookId | UUID | 复合主键 |
| LocatorType | Varchar(32) | `CFI`/`DOM_POS`/`PAGE_INDEX` |
| LocatorValue | Varchar(1000) | 定位值 |
| CatalogId | UUID? | 当前章节 |
| ProgressRatio | Decimal(5,4) | 0~1 |
| Version | Int | 乐观锁版本 |
| UpdateTime | DateTime | 更新时间 |

> LocatorType：不同的书籍格式，定位方式是完全不同的。前端定位字符串时，先查看LocatorType的类型，从而决定调用Reader kit的哪个API去跳转。



#### 3.2.5 UserCollections / BookCollectionMapping（保持）

`UserCollections` 与 `BookCollectionMapping` 保持原始设计，字段不变。

```
UserCollections：
Id、UserID、Name、SortOrder(藏书排序顺序)、CreateTime

BookCollectionMapping：
CollectionId、BookId、UserId、AddTime
```



#### 3.2.6 Annotations（保留，补充枚举）

```
Annotations(标注表):
Id、UserId、BookId、CatalogId、Locator (Varchar 500)、QuoteText、NoteContent(用户写的笔记内容（如果只是纯划线，则为空）)、 style(Varchar 20)、Type(0-纯划线，1-带笔记)、Status(0-正常，1-已删除)、UpdatedAt、CreateTime
```

`Type` 枚举：

- `HIGHLIGHT`：纯划线
- `NOTE`：划线+笔记
- `BOOKMARK`：书签

---

## 4. 用户与鉴权模块

**关联表结构**

```
User：
Id、Username、Account、PasswordHash、AvatarUrl、CreateTime
```



### 4.1 注册

- 路由：`POST /api/v1/auth/register`

入参：

```json
{
  "account": "13800000000",
  "username": "张三",
  "password": "PlainTextOnlyForTransport"
}
```

出参：

```json
{
  "userId": "uuid"
}
```

### 4.2 登录

- 路由：`POST /api/v1/auth/login`

入参：

```json
{
  "account": "13800000000",
  "password": "PlainTextOnlyForTransport"
}
```

出参：

```json
{
  "accessToken": "jwt",
  "refreshToken": "jwt",
  "expiresInSec": 7200,
  "user": {
    "id": "uuid",
    "username": "张三",
    "account": "13800000000",
    "avatarUrl": "https://..."
  }
}
```

### 4.4 退出登录

- 路由：`POST /api/v1/auth/logout`

入参：无

出参：

```json
{
  "loggedOut": true
}
```

### 4.5 获取当前用户

- 路由：`GET /api/v1/users/me`

入参：无

出参：

```json
{
  "id": "uuid",
  "username": "张三",
  "account": "13800000000",
  "avatarUrl": "https://...",
  "createTime": "2026-04-18T08:00:00+08:00"
}
```

### 4.6 更新当前用户

- 路由：`PUT /api/v1/users/me`

入参：

```json
{
  "username": "张三",
  "avatarUrl": "https://..."
}
```

出参：

```json
{
  "updated": true
}
```

## 5. 阅读目标与统计模块

### 5.1 获取今日阅读目标进度

- 路由：`GET /api/v1/read-goal/today`
- 入参：无

出参：

```json
{
  "date": "2026-04-18",
  "durationSec": 64,
  "targetSec": 300,
  "remainingSec": 236,//remainingSec = TargetDuration - Duration
  "isAchieved": false
}
```

### 5.2 设置每日阅读目标

- 路由：`PUT /api/v1/read-goal/target`

入参：

```json
{
  "targetSec": 300
}
```

出参：

```json
{
  "updated": true
}
```

### 5.3 获取连续阅读统计

- 路由：`GET /api/v1/read-goal/streak`
- 入参：无

出参：

```json
{
  "currentStreakCount": 3,
  "longestStreakCount": 9,
  "lastAchieveDate": "2026-04-17"
}
```

### 5.4 获取年度阅读摘要（对应主页_2）

- 路由：`GET /api/v1/read-goal/year-summary?year=2026`

查询参数：

- `year`（int，必填）

出参：

```json
{
  "year": 2026,
  "booksReadCount": 2,
  "booksTarget": 5,
  "booksRemaining": 3
}
```

### 5.5 阅读会话结束上报（强幂等）

- 路由：`POST /api/v1/read-sessions/finish`
- Header：`Idempotency-Key`（必填）

入参：

```json
{
  "sessionId": "uuid",
  "bookId": "uuid",
  "startedAt": "2026-04-18T07:58:01+08:00",
  "endedAt": "2026-04-18T08:03:15+08:00",
  "durationSec": 314,
  "position": {
    "locatorType": "CFI",
    "locatorValue": "epubcfi(/6/4!/4/2/14/1:0)",
    "catalogId": "uuid",
    "progressRatio": 0.2431
  }
}
```

出参：

```json
{
  "accepted": true
}
```

校验规则：

1. `durationSec >= 0`
2. 单次会话 `durationSec <= 43200`（12 小时）
3. 相同 `sessionId + Idempotency-Key` 只能累计一次

---

## 6. 云端书库模块（Reader Kit 简化 CRUD）

> 本模块不再包含“解析任务、章节正文解析、解析进度轮询”。

### 6.1 注册本地图书（由 Reader Kit 提供书籍信息）

- 路由：`POST /api/v1/library/books`
- Header：`Idempotency-Key`（必填）

入参：

```json
{
  "readerBookKey": "sha256:xxxx",
  "fileHash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "fileUrl": "https://oss-xxx.com/books/mao.epub",
  "title": "毛泽东选集",
  "author": "毛泽东",
  "coverUrl": "https://...",
  "format": "EPUB",
  "fileName": "mao.epub",
  "fileSize": 12993211,
  "totalCatalogCount": 120
}
```

出参：

```json
{
  "bookId": "uuid",
  "isNew": true,
  "createdAt": "2026-04-18T08:00:00+08:00"
}
```

说明：同一用户 `readerBookKey` 唯一，重复导入返回既有 `bookId`。

**校验服务器是否存在上传的文件**

- 路由 `POST /api/v1/files/check`（入参：`fileHash`）

  入参:

  ```json
  {
    "fileHash": "e3b0c4429..."
  }
  ```

  出参：

  ```json
  { "exists": true或者false, "fileUrl": "https://..."或者null }
  ```

  如果exists为false，调用upload上传图书文件

**上传图书文件(异步/后台)**

- 路由 POST /api/v1/files/upload

入参：`multipart/form-data`，包含 `file` (文件流) 和 `type` (例如 `epub`, `cover`)。

出参：

```json
{
  "fileHash": "e3b0c4429..."，
   "fileUrl": "https://..."
}
```



### 6.3 上报目录快照（由 Reader Kit 提供目录列表）

- 路由：`PUT /api/v1/library/books/{bookId}/catalogs`

路径参数：

- `bookId`（UUID，必填）

入参：

```json
{
  "replaceAll": true,
  "items": [
    {
      "catalogId": "rk-catalog-1",
      "parentCatalogId": null,
      "title": "第一章",
      "orderNum": 1,
      "depthLevel": 0,
      "href": "Text/chapter1.xhtml",
      "locator": "epubcfi(/6/2[chapter1]!/4/1:0)"
    }
  ]
}
```

出参：

```json
{
  "bookId": "uuid",
  "catalogVersion": 3,
  "totalCatalogCount": 120,
  "updatedAt": "2026-04-18T08:00:00+08:00"
}
```

### 6.4 获取书库列表

- 路由：`GET /api/v1/library/books?pageNo=1&pageSize=20&keyword=&sortBy=lastReadAt&sortOrder=desc`

查询参数：

- `pageNo`（int，可选）
- `pageSize`（int，可选）
- `keyword`（string，可选，匹配书名/作者）
- `sortBy`（`lastReadAt`/`createTime`/`title`，可选）
- `sortOrder`（`asc`/`desc`，可选）

出参：

```json
{
  "items": [
    {
      "id": "uuid",
      "title": "毛泽东选集",
      "author": "毛泽东",
      "coverUrl": "https://...",
      "format": "EPUB",
      "totalCatalogCount": 120,
      "progressRatio": 0.5,
      "lastReadAt": "2026-04-18T08:03:15+08:00"
    }
  ],
  "pageNo": 1,
  "pageSize": 20,
  "total": 2
}
```

### 6.5 获取图书详情（完整）

- 路由：`GET /api/v1/library/books/{bookId}`

路径参数：

- `bookId`（UUID，必填）

查询参数：无

出参：

```json
{
  "id": "uuid",
  "readerBookKey": "sha256:xxxx",
  "fileUrl": "https://oss-xxx.com/books/mao.epub",
  "title": "毛泽东选集",
  "author": "毛泽东",
  "coverUrl": "https://...",
  "format": "EPUB",
  "fileName": "mao.epub",
  "fileSize": 12993211,
  "totalCatalogCount": 120,
  "catalogVersion": 3,
  "progress": {
    "progressRatio": 0.5,
    "locatorType": "CFI",
    "locatorValue": "epubcfi(/6/4!/4/2/14/1:0)",
    "updatedAt": "2026-04-18T08:03:15+08:00"
  },
  "createTime": "2026-04-16T10:00:00+08:00",
  "updateTime": "2026-04-18T08:03:15+08:00"
}
```

### 6.6 获取目录树（完整）

- 路由：`GET /api/v1/library/books/{bookId}/catalogs?tree=true`

路径参数：

- `bookId`（UUID，必填）

查询参数：

- `tree`（bool，可选，默认 `true`）

出参：

```json
{
  "bookId": "uuid",
  "tree": true,
  "catalogVersion": 3,
  "items": [
    {
      "id": "uuid",
      "title": "第一章",
      "parentId": null,
      "orderNum": 1,
      "depthLevel": 0,
      "href": "Text/chapter1.xhtml",
      "locator": "epubcfi(/6/2[chapter1]!/4/1:0)",
      "children": []
    }
  ],
  "total": 120
}
```

### 6.7 删除图书（仅删除云端记录）

- 路由：`DELETE /api/v1/library/books/{bookId}`

路径参数：

- `bookId`（UUID，必填）

入参：无

出参：

```json
{
  "deleted": true
}
```

### 6.8 获取最近阅读图书

- 路由：`GET /api/v1/library/recent?limit=10`

查询参数：

- `limit`（int，可选，默认 10，最大 50）

出参：

```json
{
  "items": [
    {
      "id": "uuid",
      "title": "以日为鉴：衰退时代生存指南",
      "author": "分析师Boden",
      "coverUrl": "https://...",
      "progressRatio": 0.5,
      "lastReadAt": "2026-04-18T08:03:15+08:00"
    }
  ]
}
```

---

## 7. 阅读进度模块

### 7.1 获取某本书阅读进度（完整）

- 路由：`GET /api/v1/reading-progress/{bookId}`

路径参数：

- `bookId`（UUID，必填）

查询参数：无

出参（有记录）：

```json
{
  "bookId": "uuid",
  "hasProgress": true,
  "position": {
    "locatorType": "CFI",
    "locatorValue": "epubcfi(/6/4!/4/2/14/1:0)",
    "catalogId": "uuid",
    "progressRatio": 0.2315
  },
  "version": 19,
  "updatedAt": "2026-04-18T08:03:15+08:00"
}
```

出参（无记录）：

```json
{
  "bookId": "uuid",
  "hasProgress": false,
  "position": null,
  "version": 0,
  "updatedAt": null
}
```

### 7.2 保存阅读进度（乐观锁）

- 路由：`PUT /api/v1/reading-progress/{bookId}`

路径参数：

- `bookId`（UUID，必填）

入参：

```json
{
  "position": {
    "locatorType": "CFI",
    "locatorValue": "epubcfi(/6/4!/4/2/14/1:12)",
    "catalogId": "uuid",
    "progressRatio": 0.2431
  },
  "version": 19
}
```

出参：

```json
{
  "saved": true,
  "newVersion": 20,
  "updatedAt": "2026-04-18T08:04:00+08:00"
}
```

冲突：`409 + READ_PROGRESS_CONFLICT`

```json
{
  "errorCode": "READ_PROGRESS_CONFLICT",
  "message": "version mismatch",
  "serverVersion": 22
}
```

---

## 8. 多维藏书夹模块

### 8.1 获取藏书夹列表

- 路由：`GET /api/v1/collections`
- 入参：无

出参：

```json
{
  "items": [
    {
      "id": "uuid",
      "name": "图书",
      "sortOrder": 3,
      "bookCount": 2,
      "isBuiltIn": true
    }
  ]
}
```

### 8.2 新建藏书夹

- 路由：`POST /api/v1/collections`

入参：

```json
{
  "name": "历史类"
}
```

出参：

```json
{
  "id": "uuid",
  "name": "历史类",
  "sortOrder": 8
}
```

### 8.3 修改藏书夹

- 路由：`PATCH /api/v1/collections/{collectionId}`

路径参数：

- `collectionId`（UUID，必填）

入参：

```json
{
  "name": "历史与政治"
}
```

出参：

```json
{
  "updated": true
}
```

### 8.4 删除藏书夹

- 路由：`DELETE /api/v1/collections/{collectionId}`

路径参数：

- `collectionId`（UUID，必填）

入参：无

出参：

```json
{
  "deleted": true
}
```

### 8.5 调整藏书夹排序

- 路由：`PATCH /api/v1/collections/order`

入参：

```json
{
  "orders": [
    { "collectionId": "uuid-1", "sortOrder": 1 },
    { "collectionId": "uuid-2", "sortOrder": 2 }
  ]
}
```

出参：

```json
{
  "updated": true
}
```

### 8.6 查看某藏书夹图书

- 路由：`GET /api/v1/collections/{collectionId}/books?pageNo=1&pageSize=20`

路径参数：

- `collectionId`（UUID，必填）

查询参数：

- `pageNo`、`pageSize`

出参：

```json
{
  "items": [
    {
      "id": "uuid",
      "title": "毛泽东选集",
      "author": "毛泽东",
      "coverUrl": "https://...",
      "progressRatio": 0.02
    }
  ],
  "pageNo": 1,
  "pageSize": 20,
  "total": 2
}
```

### 8.7 向藏书夹添加图书

- 路由：`POST /api/v1/collections/{collectionId}/books`

路径参数：

- `collectionId`（UUID，必填）

入参：

```json
{
  "bookId": "uuid"
}
```

出参：

```json
{
  "added": true
}
```

### 8.8 从藏书夹移除图书

- 路由：`DELETE /api/v1/collections/{collectionId}/books/{bookId}`

路径参数：

- `collectionId`（UUID，必填）
- `bookId`（UUID，必填）

入参：无

出参：

```json
{
  "removed": true
}
```

---

## 9. 标注同步模块

### 9.1 获取全书标注（增量）

- 路由：`GET /api/v1/books/{bookId}/annotations?updatedAfter=2026-04-18T00:00:00+08:00&pageNo=1&pageSize=100`

路径参数：

- `bookId`（UUID，必填）

查询参数：

- `updatedAfter`（可选）
- `pageNo`、`pageSize`

出参：

```json
{
  "items": [
    {
      "id": "uuid",
      "catalogId": "uuid",
      "quoteText": "游民生活。如打春...",
      "noteContent": "这里说明了地方禁令",
      "style": "YELLOW",
      "type": "NOTE",
      "status": "ACTIVE",
      "locator": {
        "start": "epubcfi(...)",
        "end": "epubcfi(...)"
      },
      "updatedAt": "2026-04-18T08:03:15+08:00"
    }
  ],
  "pageNo": 1,
  "pageSize": 100,
  "total": 1
}
```

### 9.2 批量同步标注

- 路由：`POST /api/v1/books/{bookId}/annotations/sync`
- Header：`Idempotency-Key`（必填）

路径参数：

- `bookId`（UUID，必填）

入参：

```json
{
  "clientSyncId": "uuid",
  "upserts": [
    {
      "id": "uuid",
      "catalogId": "uuid",
      "quoteText": "游民生活。如打春...",
      "noteContent": "",
      "style": "YELLOW",
      "type": "HIGHLIGHT",
      "locator": {
        "start": "epubcfi(...)",
        "end": "epubcfi(...)"
      },
      "updatedAt": "2026-04-18T08:03:15+08:00"
    }
  ],
  "deletes": [
    {
      "id": "uuid",
      "updatedAt": "2026-04-18T08:05:00+08:00"
    }
  ]
}
```

出参：

```json
{
  "acceptedIds": ["uuid"],
  "conflicts": [
    {
      "id": "uuid",
      "reason": "server_newer",
      "serverUpdatedAt": "2026-04-18T08:06:00+08:00"
    }
  ]
}
```

冲突策略：默认 `LastWriteWins`（按 `updatedAt`）。

---

## 10. 搜索模块

### 10.1 搜索书库

- 路由：`GET /api/v1/search/library?q=毛泽东&pageNo=1&pageSize=20`

查询参数：

- `q`（必填）
- `pageNo`、`pageSize`

出参：

```json
{
  "items": [
    {
      "id": "uuid",
      "title": "毛泽东选集",
      "author": "毛泽东",
      "coverUrl": "https://...",
      "progressRatio": 0.02
    }
  ],
  "pageNo": 1,
  "pageSize": 20,
  "total": 1
}
```

### 10.2 书内搜索（Reader Kit 菜单对应）

- 路由：`GET /api/v1/search/books/{bookId}/content?q=流民&pageNo=1&pageSize=20`

路径参数：

- `bookId`（UUID，必填）

查询参数：

- `q`（必填）
- `pageNo`、`pageSize`

出参：

```json
{
  "items": [
    {
      "catalogId": "uuid",
      "catalogTitle": "第117章",
      "snippet": "...有一种“强告化”又叫“流民”者...",
      "locator": {
        "locatorType": "CFI",
        "locatorValue": "epubcfi(...)"
      }
    }
  ],
  "pageNo": 1,
  "pageSize": 20,
  "total": 12
}
```

---

## 11. Reader Kit 页面时序与原型映射

### 11.1 打开图书（阅读页）

1. `GET /api/v1/library/books/{bookId}`（拿书籍元信息）
2. `GET /api/v1/library/books/{bookId}/catalogs?tree=true`（拿目录树）
3. `GET /api/v1/reading-progress/{bookId}`（拿上次进度）
4. Reader Kit 在本地打开图书文件并跳转到 `locator`
5. `GET /api/v1/books/{bookId}/annotations?...`（加载标注层）

### 11.2 阅读中

1. Reader Kit 分页回调/位置变化
2. 节流调用 `PUT /api/v1/reading-progress/{bookId}`

### 11.3 选中内容

1. Reader Kit 返回选区定位
2. 调用 `POST /api/v1/books/{bookId}/annotations/sync`

### 11.4 退出阅读页

1. `POST /api/v1/read-sessions/finish`
2. 最后一次 `PUT /api/v1/reading-progress/{bookId}`

### 11.5 原型页面对照

1. 主页（`主页_1/主页_2`）
   - `GET /api/v1/library/recent`
   - `GET /api/v1/read-goal/today`
   - `GET /api/v1/read-goal/streak`
   - `GET /api/v1/read-goal/year-summary`
   - `PUT /api/v1/read-goal/target`
2. 书库（`书库_1/书库_2`）
   - `GET /api/v1/library/books`
   - `GET /api/v1/library/books/{bookId}`
3. 藏书（`书库_藏书_1/书库_藏书_2`）
   - `GET /api/v1/collections`
   - `POST/PATCH/DELETE /api/v1/collections...`
   - `POST/DELETE /api/v1/collections/{collectionId}/books...`
4. 搜索（`搜索`）
   - `GET /api/v1/search/library`
5. 账户（`账户`）
   - `GET /api/v1/users/me`
   - `GET/PUT /api/v1/users/me/notification-settings`
   - `PUT /api/v1/users/me`
   - `POST /api/v1/auth/logout`
6. 阅读页（`阅读页_1/2/3`）
   - `GET /api/v1/library/books/{bookId}/catalogs?tree=true`
   - `GET /api/v1/search/books/{bookId}/content`
   - `GET/PUT /api/v1/reading-progress/{bookId}`
   - `GET /api/v1/books/{bookId}/annotations`
   - `POST /api/v1/books/{bookId}/annotations/sync`
   - `POST /api/v1/read-sessions/finish`

---

## 12. 路由迁移（旧 PRD -> 当前）

| 旧路由 | 当前路由 |
|---|---|
| `POST api/library/upload` | `POST /api/v1/library/books`（注册本地图书元信息） |
| `GET api/library/tasks/{TaskId}` | 删除（不再有解析任务） |
| `GET /api/v1/library/books/{bookId}/catalogs/{catalogId}/content` | 删除（正文由 Reader Kit 本地读取） |
| `GET api/readtime/today` | `GET /api/v1/read-goal/today` |
| `PUT api/readtime/setTarget` | `PUT /api/v1/read-goal/target` |
| `GET api/readtime/longestStreak` | `GET /api/v1/read-goal/streak` |
| `POST api/readtime/totaltime` | `POST /api/v1/read-sessions/finish` |
| `GET api/annotation/{bookId}` | `GET /api/v1/books/{bookId}/annotations` |
| `POST api/annotation/add` | `POST /api/v1/books/{bookId}/annotations/sync` |

---

## 13. 7 人并发分工建议

1. FE-Reader：Reader Kit 页面、目录、定位恢复、选区交互
2. FE-App：主页/书库/藏书/搜索/账户
3. FE-Sync：进度与标注同步、离线重试
4. BE-Auth：登录鉴权
5. BE-Library：图书元信息与目录快照 CRUD
6. BE-Reading：目标统计与会话汇总
7. BE-Annotation：标注增量同步

前端大致代码结构

```
/entry/src/main/ets
 ├── /appability          # [系统级] UIAbility 生命周期入口 (仅限负责人修改)
 ├── /common              # [公共禁飞区] 核心基建
 │   ├── /http            # 统一网络请求封装 (自动带Token、统一错误拦截)
 │   ├── /utils           # 工具类 (如 Hash计算、时区转换)
 │   └── /theme           # 全局样式 (主题色、统一字体大小常量)
 ├── /database            # [前端 A 专属] 本地 SQLite 核心
 │   ├── /entity          # 本地表结构模型 (LocalBooks, SyncQueue)
 │   └── /dao             # 数据库增删改查方法与离线队列逻辑
 ├── /features            # [核心战场 - 业务模块区]
 │   ├── /bookshelf       # [前端 C 专属] 书库页面、书架网格组件
 │   ├── /reader          # [前端 B、D 共享与隔离]
 │   │   ├── /engine      # [前端 B 专属] Reader Kit 核心接入层
 │   │   └── /ui          # [前端 D 专属] 标注菜单、目录抽屉、设置面板
 │   └── /dashboard       # [前端 E 专属] 目标统计图表与账户页面
 └── /pages               # [路由中转站]
     └── Index.ets        # 全局根页面 (建议使用 Navigation 承载子模块)
```

