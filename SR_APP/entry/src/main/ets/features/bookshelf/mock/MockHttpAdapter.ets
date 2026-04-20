interface MockErrorData {
  url: string;
  payloadText: string;
}

export interface MockHttpSuccess<T> {
  status: number;
  data: T;
}

export class MockHttpError extends Error {
  status: number;
  data?: MockErrorData;

  constructor(status: number, message: string, data?: MockErrorData) {
    super(message);
    this.status = status;
    this.data = data;
  }
}

export class MockHttpAdapter {
  /**
   * Pure mock POST router.
   *
   * How to use in SyncService test mode:
   * 1) replace `requestPost(url, payload)` with `MockHttpAdapter.mockPost(url, payload)`.
   * 2) for upload mock path call:
   *    `MockHttpAdapter.mockPost('/api/v1/files/upload', { type: 'epub', filePath: book.localPath })`.
   */
  public static async mockPost<T = Record<string, string | boolean>>(
    url: string,
    payload?: Object
  ): Promise<MockHttpSuccess<T>> {
    await MockHttpAdapter.mockDelay(60);

    if (url.endsWith('/api/v1/files/check')) {
      return {
        status: 200,
        data: {
          exists: false
        } as T
      };
    }

    if (url.endsWith('/api/v1/files/upload')) {
      return {
        status: 200,
        data: {
          fileUrl: 'https://mock.oss.com/test.epub'
        } as T
      };
    }

    if (url.endsWith('/api/v1/library/books')) {
      return {
        status: 201,
        data: {
          bookId: 'mock-uuid-9999'
        } as T
      };
    }

    const errData: MockErrorData = {
      url: url,
      payloadText: payload ? JSON.stringify(payload) : ''
    };
    throw new MockHttpError(404, `Mock route not found: ${url}`, errData);
  }

  private static async mockDelay(ms: number): Promise<void> {
    await new Promise<void>((resolve) => setTimeout(() => resolve(), ms));
  }
}
