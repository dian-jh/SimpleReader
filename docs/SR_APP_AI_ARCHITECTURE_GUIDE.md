# SR_APP 代码架构速览（AI 快速上手）

> 更新时间：2026-04-20  
> 扫描范围：`SR_APP/entry/src/main/ets` + `SR_APP/entry/src/main/resources/rawfile` + 配置文件  
> 说明：你在问题里写的是 `SA_APP`，仓库实际目录为 `SR_APP`，本文按 `SR_APP` 分析。

## 1. 顶层模块划分

### 1.1 应用入口层
- `SR_APP/entry/src/main/ets/entryability/EntryAbility.ets`
  - `onWindowStageCreate()`：加载主页面 `pages/Index`
- `SR_APP/entry/src/main/ets/entrybackupability/EntryBackupAbility.ets`
  - 备份扩展能力（`onBackup` / `onRestore`）

### 1.2 页面路由层（`ets/pages`）
- `Index.ets`：底部 Tab 容器（首页/书库/搜索），书库页挂载 `BookshelfPage`
- `Reader.ets`：阅读路由壳页，内部挂载 `ReaderPage`
- `Test.ets`：测试页，直接挂载 `Reader` 组件（开发用途）

### 1.3 业务功能层（`ets/features`）
- `features/bookshelf`
  - 页面：`BookshelfPage.ets`
  - 组件：`BookListItem.ets`、`BookGridItem.ets`
  - 工具：`BookImportUtil.ets`
  - 服务：`SyncService.ets`
  - Mock：`MockDataInjector.ets`、`MockHttpAdapter.ets`
- `features/reader`
  - 页面：`ReaderPage.ets`
  - 引擎组件：`engine/Reader.ets`

### 1.4 数据层（`ets/database`）
- 实体：`entity/LocalBook.ets`
- DAO：`dao/BookDao.ets`

### 1.5 Web 资源层（`resources/rawfile/reader`）
- `index.html`：无界面 EPUB 解析器（上传阶段）
- `viewer.html`：阅读渲染器（阅读阶段）
- `epub.min.js`：epub.js 库

---

## 2. 核心模块与关键函数

## 2.1 Bookshelf（书架 + 导入）

文件：`features/bookshelf/pages/BookshelfPage.ets`

### 关键状态
- `books`：书架列表数据
- `parserReady`：隐藏 Web 解析器是否就绪
- `parsingBook`：是否正在解析导入书
- `pendingImportTask`：待完成导入任务（沙箱路径、hash、格式等）

### 关键函数
- `aboutToAppear()`
  - 调用 `bootstrap()`，初始化本地书库并触发同步
- `bootstrap()`
  - `loadBooksFromLocal()` + `triggerBackgroundReconcile()`
- `handleImportBook()`
  - 打开 `DocumentViewPicker` 选 EPUB
  - 调 `BookImportUtil.prepareSandboxFile()` 拷贝到沙箱并生成 hash
  - 去重（`BookDao.findByFileHash`）
  - 调 `tryStartHeadlessParse()` 开始 Web 解析
- `HiddenParserWebBuilder()`
  - 创建隐藏 Web 组件，加载 `reader/index.html`
  - 注入 `ArkTSBridge`：`onParseSuccess` / `onParseError`
- `tryStartHeadlessParse()`
  - 读取沙箱 EPUB 文件 -> Base64
  - 执行 `window.parseEpubBase64(base64)`
- `finishImportByParsedMetadata(jsonStr)`
  - 解析元数据 payload（title/author/cover/toc）
  - 组装 `LocalBook` 并 `BookDao.insert()`
  - 刷新 UI + 异步同步
- `openReader(book)`
  - 校验本地文件可用
  - `router.pushUrl({ url: 'pages/Reader', params: { localPath, lastLocator } })`

## 2.2 Reader（阅读展示）

文件：`features/reader/pages/ReaderPage.ets`

### 关键状态
- `localPath` / `lastLocator` / `bookTitle`
- `showMenu`：上下阅读菜单显示开关
- `progressText` / `readPercentage` / `errorText`

### 关键函数
- `aboutToAppear()`：从路由参数读取阅读上下文
- `build()`：
  - Web 加载 `reader/viewer.html`
  - 覆盖透明点击层：左翻页/中部菜单/右翻页
  - 顶部/底部阅读菜单
- `callWebInit()`：
  - 读取本地 EPUB -> Base64
  - 执行 `window.initReaderWithBase64(base64, lastLocator)`
- `onProgressChanged(cfi, percentage)`：更新 UI 进度

另有文件：`features/reader/engine/Reader.ets`
- 独立阅读组件版本，接口为 `@Prop localPath / lastLocator`
- 目前调用 `window.initReader(localPath,lastLocator)`（与当前 `viewer.html` 暴露的 `initReaderWithBase64` 不一致，见第 7 节风险）

## 2.3 导入工具

文件：`features/bookshelf/utils/BookImportUtil.ets`

### 关键函数
- `prepareSandboxFile(context, sourceUri)`
  - 创建 `filesDir/books`
  - 通过 `fs.openSync + fs.copyFileSync(fd, fd)` 拷贝文件
  - 计算 SHA-256（`hash.hash(...,'sha256')`）
  - 返回 `BookSandboxFile`

## 2.4 本地数据库

文件：`database/entity/LocalBook.ets`
- `LocalBook`：本地书本模型（含 `localPath/fileHash/syncStatus/toc?` 等）
- `LocalBookEntity.CREATE_TABLE_SQL`：建表 SQL（当前未含 `toc` 列，见第 7 节）

文件：`database/dao/BookDao.ets`

### 关键函数
- `init(context)`：打开 `simple_reader.db`、建表建索引
- `insert(localBook)`：插入书籍
- `listAll(orderDescByUpdatedAt)`：书架列表查询
- `findByFileHash(fileHash)`：导入去重
- `listPendingSyncBooks(limit)`：待同步队列
- `markSyncSuccess(...) / markSyncPending(...) / updateLocalState(...)`

## 2.5 同步服务

文件：`features/bookshelf/services/SyncService.ets`

### 关键函数
- `syncPendingBooks()`：
  - 拉待同步本地书
  - 检查云端是否已有文件
  - 没有则上传文件
  - 注册书籍元信息到云端
  - 标记同步成功
- `fetchCloudBooksAndUpdateLocal()`
  - 当前仅调用 `syncPendingBooks()`（仍是本地优先策略）

### 备注
- `requestPost` 当前是 mock stub，不是真实网络实现

---

## 3. 页面/路由跳转逻辑

## 3.1 应用主启动
1. `EntryAbility.onWindowStageCreate()`
2. `windowStage.loadContent('pages/Index')`
3. 进入 `Index`（Tabs）

## 3.2 Tab 导航
- `Index.ets` 使用 `Tabs` 管理 3 个 Tab：
  - 首页（占位）
  - 书库（`BookshelfPage`）
  - 搜索（占位）

## 3.3 书架 -> 阅读页
1. `BookshelfPage.ListBuilder/GridBuilder` 点击书目
2. `openReader(book)` 校验本地文件
3. `router.pushUrl('pages/Reader', params)`
4. `pages/Reader.ets` 挂载 `ReaderPage`
5. `ReaderPage` 加载 `rawfile/reader/viewer.html` 进入阅读

路由配置位置：
- `resources/base/profile/main_pages.json`：`pages/Index`、`pages/Test`、`pages/Reader`

---

## 4. ArkTS <-> Web 桥接逻辑

## 4.1 上传解析桥（Bookshelf）
- ArkTS 发起：`window.parseEpubBase64(base64)`
- Web 页面：`rawfile/reader/index.html`
- Web 回调：
  - `ArkTSBridge.onParseSuccess(jsonStr)`
  - `ArkTSBridge.onParseError(message)`
- 回传 payload：
  - `title`
  - `author`
  - `coverBase64`
  - `tocJson`

## 4.2 阅读桥（Reader）
- ArkTS 发起：`window.initReaderWithBase64(base64,lastLocator)`（来自 `ReaderPage`）
- Web 页面：`rawfile/reader/viewer.html`
- Web 回调：
  - `onReady()`
  - `onProgressChange(cfi, percentage)`
  - `onError(message)`
- 翻页调用：`prevPage()` / `nextPage()`

---

## 5. 关键数据流（端到端）

## 5.1 本地导入与解析入库
1. 选文件（FilePicker）
2. `BookImportUtil` 拷贝到沙箱并计算 hash
3. `BookshelfPage` 读取文件为 Base64，交给 `index.html`
4. `index.html` 用 epub.js 解析 metadata + toc + cover
5. ArkTS 收到成功回调，构建 `LocalBook`
6. `BookDao.insert`
7. `books = listAll()`，书架刷新

## 5.2 点击阅读
1. 书架卡片点击
2. 校验 `localPath` 有效
3. 跳转 `pages/Reader`
4. `ReaderPage` 读取本地文件为 Base64
5. `viewer.html` 初始化 rendition 并显示
6. 翻页、进度回传 ArkTS

## 5.3 同步（当前实现）
1. `BookshelfPage.bootstrap -> triggerBackgroundReconcile`
2. `SyncService.fetchCloudBooksAndUpdateLocal`
3. `syncPendingBooks` 逐本处理上传/注册
4. `BookDao.markSyncSuccess`

---

## 6. 快速定位（下次 AI 可直接从这里进）

- 导入主链路入口：`BookshelfPage.handleImportBook()`
- Web 解析入口：`rawfile/reader/index.html -> parseEpubBase64`
- 入库入口：`BookshelfPage.finishImportByParsedMetadata()`
- 阅读跳转入口：`BookshelfPage.openReader()`
- 阅读页入口：`ReaderPage.aboutToAppear()` + `callWebInit()`
- 阅读 Web 入口：`rawfile/reader/viewer.html -> initReaderWithBase64`
- 本地数据读写：`BookDao`
- 同步入口：`SyncService.syncPendingBooks()`

---

## 7. 当前代码状态的“已知不一致/风险点”（很关键）

1. `LocalBook` 接口有 `toc?: string`，但 `CREATE_TABLE_SQL` 未定义 `toc` 列。  
   - 现状：`toc` 仅在内存对象存在，DB 不持久化。

2. `features/reader/engine/Reader.ets` 调用 `window.initReader(...)`，但 `viewer.html` 当前暴露的是 `initReaderWithBase64(...)`。  
   - 现状：`pages/Test` 使用 `Reader` 组件，可能运行异常；主链路 `pages/Reader -> ReaderPage` 正常。

3. `Index.ets`、`BookshelfPage.ets`、`ReaderPage.ets` 中存在中文乱码注释/文案。  
   - 现状：不影响核心逻辑，但影响可维护性。

4. `SyncService` 的 `requestPost` 是 mock stub，尚未接真实后端。  
   - 现状：同步流程“可跑逻辑”，但不是生产可用网络实现。

5. `main_pages.json` 同时包含 `pages/Test` 和 `pages/Reader`。  
   - 现状：测试入口与正式入口并存，发布前建议统一。

---

## 8. 建议的后续整理顺序（供下次 AI 执行）

1. 统一 Reader 入口：保留 `ReaderPage` 或 `engine/Reader` 其一，消除 `initReader` / `initReaderWithBase64` 分叉。  
2. 给 `local_books` 增加 `toc` 列并做迁移。  
3. 统一文本编码（UTF-8），清理乱码注释与字符串。  
4. 将 `SyncService.requestPost` 替换为真实 HTTP 封装并补失败重试。  
5. 视情况移除 `pages/Test` 或改为开发构建开关。

---

## 9. 参考文件清单（本次扫描）
- `ets/entryability/EntryAbility.ets`
- `ets/pages/Index.ets`
- `ets/pages/Reader.ets`
- `ets/pages/Test.ets`
- `ets/features/bookshelf/pages/BookshelfPage.ets`
- `ets/features/bookshelf/utils/BookImportUtil.ets`
- `ets/features/bookshelf/services/SyncService.ets`
- `ets/features/bookshelf/components/BookListItem.ets`
- `ets/features/bookshelf/components/BookGridItem.ets`
- `ets/features/bookshelf/mock/MockDataInjector.ets`
- `ets/features/bookshelf/mock/MockHttpAdapter.ets`
- `ets/features/reader/pages/ReaderPage.ets`
- `ets/features/reader/engine/Reader.ets`
- `ets/database/entity/LocalBook.ets`
- `ets/database/dao/BookDao.ets`
- `resources/rawfile/reader/index.html`
- `resources/rawfile/reader/viewer.html`
- `resources/base/profile/main_pages.json`
- `module.json5`
