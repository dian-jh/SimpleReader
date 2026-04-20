import fs from '@ohos.file.fs';
import hash from '@ohos.file.hash';
import { common } from '@kit.AbilityKit';

export interface BookSandboxFile {
  fileName: string;
  sandboxPath: string;
  fileSize: number;
  fileHash: string;
  format: string;
  fallbackTitle: string;
  readerBookKey: string;
  webFileUrl: string;
}

export class BookImportUtil {
  static async prepareSandboxFile(context: common.UIAbilityContext, sourceUri: string): Promise<BookSandboxFile> {
    try {
      const booksDir = context.filesDir + '/books';

      // 【关键修复】：安全创建目录，兼容 accessSync 抛出异常的系统版本
      try {
        if (!fs.accessSync(booksDir)) {
          fs.mkdirSync(booksDir);
        }
      } catch (dirErr) {
        // 如果抛出异常，说明目录不存在，直接创建
        fs.mkdirSync(booksDir);
      }

      let safeName = 'book_' + Date.now();
      const lastSlash = sourceUri.lastIndexOf('/');
      if (lastSlash !== -1) {
        const rawName = decodeURIComponent(sourceUri.substring(lastSlash + 1));
        // 移除非法字符，保留中文、字母、数字
        safeName = Date.now() + '_' + rawName.replace(/[^a-zA-Z0-9.\u4e00-\u9fa5_-]/g, '');
      }
      if (!safeName.endsWith('.epub')) {
        safeName += '.epub';
      }

      const destPath = booksDir + '/' + safeName;

      // 【绝对核心】：原封不动使用 sourceUri 获取 FD 并底层拷贝
      const srcFile = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
      const destFile = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);

      fs.copyFileSync(srcFile.fd, destFile.fd);

      const stat = fs.statSync(destFile.fd);
      fs.closeSync(srcFile);
      fs.closeSync(destFile);

      const fileHash = await hash.hash(destPath, 'sha256');
      console.info('[BookImportUtil] 文件安全拷贝成功: ' + destPath);

      return {
        fileName: safeName,
        sandboxPath: destPath,
        fileSize: Number(stat.size),
        fileHash: fileHash,
        format: 'epub',
        fallbackTitle: safeName.replace('.epub', ''),
        readerBookKey: destPath,
        webFileUrl: ''
      };

    } catch (e) {
      const err: Error = e instanceof Error ? e : new Error(String(e));
      console.error('[BookImportUtil] 拷贝彻底失败: ' + err.message);
      throw new Error("跨沙箱拷贝失败: " + err.message);
    }
  }
}