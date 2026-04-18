# AppleReader

> API 冻结基线：请优先使用 [API_SPEC_V2.md](./API_SPEC_V2.md)。  
> 本文中的 API 段落为历史草案，若与 V2 冲突，一律以 V2 为准。

## 用户管理模块

### 关联实体表

```
User：
Id、Username、Account、PasswordHash、AvatarUrl、CreateTime
```



这模块主要负责登录注册、JWT颁发等。

## 阅读目标与统计模块

### 关联实体表

```
阅读时长统计模块 (ReadingTimeLogs)
阅读流水表 (ReadingTimeDaily):

Id, UserId, Date (日期，如 2026-04-16), Duration (当日阅读秒数), TargetDuration(目标阅读时间)、IsAchieved 。



UserReadingStats：
Id、UserId 、CurrentStreakCount(当前连续阅读达标记录)、LongestStreakCount(历史最长连续达标记录)、LastAchieveDate(上次达标日期)

```



### 界面原型

见imgs/主页_1、主页_2、阅读目标1、阅读目标2



### 业务需求

记录用户每日的阅读时间。

设立目标每日阅读时间。

记录最长连续阅读记录(需达到每日阅读时间才记录并不能连续)

前端显示半圆形记录条，记录当日阅读时间统计和目标时间，计算并涂相应进度的记录条



**阅读时间统计**

点击图书开始统计，退出本书结束统计，退出的时候将统计的时间数据发送给后端进行记录。



第二天凌晨统计连续阅读天数，并比较CurrentStreakCount是否大于LongestStreakCount，大于就修改



### API

**阅读时间统计**

```json
//路由 POST api/readtime/totaltime
//入参
{
    "BookId": "",
    "Date": "",
    "Duration": ""
}
//出参： Void
```



**获取今日阅读时间**

```json
//路由 GET api/readtime/today
//入参 Void
//出参
{
    "Duration": "",
    "TargetDuration": ""
}

```



**设置每日阅读目标**

```json
//路由 PUT api/readtime/setTarget
//入参
{
    "TargetDuration": ""
}
//出参 Void
```



**获取最长达标阅读天数**

```json
//路由 GET api/readtime/longestStreak
//入参 Void
//出参 
{
    "LongestStreakCount": ""
}
```



## 云端书库与调度模块

### 关联实体表

```
书籍表 (Books): Id, Title, Author, CoverUrl, Intro (简介), Status(上架状态), TotalChapters、FileUri(真实存储地址)、Format(书籍类型).

章节表 (Chapters): Id, BookId (索引), Title, OrderNum (章节排序), WordCount (字数)、ResourcePath(章节在EPUB中的相对地址)、ParentId(父节点ID，如果是顶级目录，为null)、DepthLevel(节点深度).
对于章节表的解析，要使用深度优先搜索算法，因为又可以是多级目录。
DepthLevel用于前端章节树的渲染逻辑优化


图书解析进度表BookParsingTasks
TaskId、UserId、OriginalFileName、Status、Progress(进度百分比)、BookId、ErrorMessage、CreateTime
Status (TinyInt): 解析状态机。

0: 待处理 (Pending)

1: 文件解压中 (Unzipping)

2: 元数据解析中 (Parsing Metadata)

3: 章节提取与入库中 (Extracting Chapters)

4: 解析完成 (Completed)

5: 解析失败 (Failed)



阅读进度表 (ReadingProgress):

UserId, BookId (复合主键/唯一索引).

LastChapterId: 上次阅读的章节 ID。

LastPosition: 记录上次读到的具体位置（如 JSON 字符串 {"paragraphIndex": 5, "offset": 10}）。

UpdateTime: 最后一次更新时间。
```

### 业务需求

- 用户上传图书
- 解析图书时的进度展示
- 进入阅读页面的查看
- 点击章节快速索引
- 阅读进度保存下次查看回到这里的进度
- 统计用户阅读本书的进度等

### API

**上传图书并解析**

```json
//路由 POST api/library/upload
//入参
{
    FormData(图书文件流)
}
//出参
{
    "TaskId": "a1b2c3d4-...",
    "Status": 0
}
```



**轮询解析进度**

```json
//路由 GET api/library/tasks/{TaskId}
//入参 Void
//出参
{
    "TaskId": "a1b2c3d4-...",
    "Status": 3,
    "Progress": 75,
    "Message": "正在提取章节结构...",
    "BookId": null // 如果 Status 变成 4，这里就会返回真实的 BookId
}
```



## 多维藏书夹管理模块

### 关联实体表

```
UserCollections：
Id、UserID、Name、SortOrder(藏书排序顺序)、CreateTime

BookCollectionMapping：
CollectionId、BookId、UserId、AddTime
```

**业务需求**

显示所有藏书类型

显示某一个藏书类型的所有图书

新建藏书

删除某藏书

将图书从藏书中删除

在藏书中新增图书



### API

**显示所有藏书列表**

```json
//路由 GET api/collection/all
//入参 Void
//出参
{
    "Id": "",
    "Name": "",
    "SortOrder": ""
}
```



**新增藏书**

```json
//路由 POST api/collection/add
//入参 
{
    "Name": "",
    "CreateTime": ""
}
//出参 Void
```



**删除藏书**

```json
//路由 DELETE api/collection/delete
//入参 
{
    "Name": ""
}
//出参 Void
```



**将书籍放到某一个藏书中**

```json
//路由 POST api/collection/add/{BookId}
//入参 
{
    "Name": ""(藏书名字)
}
//出参 Void
```



**将书籍从某一个藏书中移除**

```json
//路由 DELETE api/collection/delete/{BookId}
//入参 
{
    "Name": ""(藏书名字)
}
//出参 Void
```



**修改藏书排序**

```json
//路由 PUT api/collection/update
//入参 
{
    "Name": ""(藏书名字),
    "SortOrder": ""
}
//出参 Void
```



## 标注同步模块

### 关联实体表

```
Annotations(标注表):
Id、UserId、BookId、ChapterId、Locator (Varchar 500)、QuoteText、NoteContent(用户写的笔记内容（如果只是纯划线，则为空）)、 style(Varchar 20)、Type(0-纯划线，1-带笔记)、Status(0-正常，1-已删除)、UpdatedAt、CreateTime
```



### API

**获取全书标注**

```json
//路由 GET api/annotation/{bookId}
//入参 Void
//出参 
{
    {
    ChapterId，
    Locator，
    QuoteText，
    NoteContent,
    style,
    Type
	}
}
```



**标注同步**

```json
//路由 POST api/annotation/add
//入参
{
    "ChapterId": "",
    "Locator": "",
    "QuoteText": "",
    "NoteContent": "",
    "style": "",
    "Type": ""，
    "CreateTime": "",
    "UpdatedAt": ""
}
//出参 Void
```



