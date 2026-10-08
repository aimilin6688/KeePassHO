import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { HuaweiDriveClient, HuaweiDriveClientOptions, HuaweiDriveFile, HttpResponse } from '../../../../../main/ets/storage/huawei/HuaweiDriveClient';
import { HuaweiDriveTestConfig } from './HuaweiDriveTestConfig';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { HuaweiDriveOAuth2Provider } from '../../../../../main/ets/storage/huawei/HuaweiDriveOAuth2Provider';
import { OAuth2AuthRequest, OAuth2RefreshRequest } from '../../../../../main/ets/common/oauth2/OAuth2Types';

const DOMAIN = 0x0000;
const TAG = 'HuaweiDriveClientTest';

// resume 大文件用例总大小：>20M 且非分片大小整数倍（确保末尾存在不足一片的分片）
const RESUME_TEST_TOTAL_BYTES: number = 21 * 1024 * 1024 + 12345;
// 内容填充模式取模基数（素数，避免短周期掩盖分片错位）
const RESUME_TEST_PATTERN_MOD: number = 251;

// 辅助函数：将 ArrayBuffer 转换为字符串
function arrayBufferToString(buffer: ArrayBuffer): string {
  const uint8Array = new Uint8Array(buffer);
  const textDecoder = util.TextDecoder.create('utf-8');
  return textDecoder.decodeToString(uint8Array);
}

// 辅助函数：将字符串转换为 ArrayBuffer
function stringToArrayBuffer(str: string): ArrayBuffer {
  const textEncoder = new util.TextEncoder();
  const uint8Array = textEncoder.encodeInto(str);
  return uint8Array.buffer;
}

// 辅助函数：生成确定性字节模式缓冲区（第 i 字节 = i % 251），用于分片上传完整性校验
function createPatternBuffer(totalBytes: number): ArrayBuffer {
  const buffer = new ArrayBuffer(totalBytes);
  const view = new Uint8Array(buffer);
  for (let i = 0; i < view.length; i++) {
    view[i] = i % RESUME_TEST_PATTERN_MOD;
  }
  return buffer;
}

// 辅助函数：抽样校验字节模式（含总长度 + 分片边界附近偏移）
function verifyPattern(buffer: ArrayBuffer, totalBytes: number, samples: number[]): boolean {
  const view = new Uint8Array(buffer);
  if (view.length !== totalBytes) {
    console.error('Pattern verify: length mismatch, expected=%{public}d actual=%{public}d', totalBytes, view.length);
    return false;
  }
  for (let i = 0; i < samples.length; i++) {
    const offset = samples[i];
    if (offset < 0 || offset >= totalBytes) {
      continue;
    }
    if (view[offset] !== offset % RESUME_TEST_PATTERN_MOD) {
      console.error('Pattern verify: mismatch at offset %{public}d, expected=%{public}d actual=%{public}d',
        offset, offset % RESUME_TEST_PATTERN_MOD, view[offset]);
      return false;
    }
  }
  return true;
}

// 辅助函数：构建抽样偏移（首尾、中点、4M 分片边界前后各一字节）
function buildSampleOffsets(totalBytes: number): number[] {
  const samples: number[] = [0, 1, totalBytes - 1, totalBytes >> 1];
  const boundary = 4 * 1024 * 1024;
  for (let k = 1; k * boundary < totalBytes; k++) {
    samples.push(k * boundary - 1);
    samples.push(k * boundary);
    samples.push(k * boundary + 1);
  }
  return samples;
}

// 辅助函数：将字节模式分块写入本地文件（模拟真实大文件落盘）
function writePatternFile(path: string, totalBytes: number): void {
  const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    const chunkSize = 1024 * 1024;
    let written = 0;
    while (written < totalBytes) {
      const len = Math.min(chunkSize, totalBytes - written);
      const chunk = new ArrayBuffer(len);
      const view = new Uint8Array(chunk);
      for (let i = 0; i < len; i++) {
        view[i] = (written + i) % RESUME_TEST_PATTERN_MOD;
      }
      fs.writeSync(file.fd, chunk);
      written += len;
    }
  } finally {
    fs.closeSync(file.fd);
  }
}

// 辅助函数：从 HttpResponse.body 解析文件资源（body 缺失时抛错，避免非空断言）
function parseFileResponse(client: HuaweiDriveClient, response: HttpResponse): HuaweiDriveFile {
  if (!response.body) {
    throw new Error(`response has no body, status=${response.statusCode}, message=${response.message}`);
  }
  return client.parseFile(JSON.parse(arrayBufferToString(response.body)) as Record<string, Object>);
}

// 辅助函数：取回响应体（body 缺失时抛错，避免非空断言）
function requireBody(response: HttpResponse): ArrayBuffer {
  if (!response.body) {
    throw new Error(`response has no body, status=${response.statusCode}, message=${response.message}`);
  }
  return response.body;
}

export default function HuaweiDriveClientTest() {
  describe('HuaweiDriveClient', () => {
    let client: HuaweiDriveClient;

    beforeEach(() => {
      const options: HuaweiDriveClientOptions = {
        apiBaseUrl: HuaweiDriveTestConfig.API_BASE_URL,
        accessToken: HuaweiDriveTestConfig.ACCESS_TOKEN,
        timeout: HuaweiDriveTestConfig.TIMEOUT
      };
      client = new HuaweiDriveClient(options);
    });

    afterEach(() => {
      client.close();
    });

    /**
     * 测试OAuth2认证流程获取ACCESS_TOKEN
     * 步骤：
     * 1. 获取授权URL
     * 2. 打印授权URL供用户访问
     * 3. 用户需要手动访问授权URL并获取授权码
     * 4. 使用授权码获取ACCESS_TOKEN
     */
    it('should_get_authorization_url_for_token', 0, async () => {
      try {
        console.log('========================================');
        console.log('Huawei Drive OAuth2 Authentication');
        console.log('========================================');

        // 创建OAuth2提供者
        const config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveTestConfig.SCOPE_AUTH);
        config.clientId = HuaweiDriveTestConfig.CLIENT_ID;
        config.clientSecret = HuaweiDriveTestConfig.CLIENT_SECRET;
        config.redirectUri = HuaweiDriveTestConfig.REDIRECT_URI;
        const provider = new HuaweiDriveOAuth2Provider(config);

        // 获取授权URL
        const authUrl = provider.getAuthorizationUrl();
        console.log('Step 1: Get Authorization URL');
        console.log('Authorization URL: %{public}s', authUrl);
        console.log('');
        console.log('Step 2: Manual Action Required');
        console.log('Please visit the above URL in your browser');
        console.log('After authorization, you will be redirected to:');
        console.log('  %{public}s', HuaweiDriveTestConfig.REDIRECT_URI);
        console.log('Copy the "code" parameter from the redirect URL');
        console.log('');
        console.log('Step 3: Use Authorization Code to Get Token');
        console.log('Example: If redirect URL is:');
        console.log('  %{public}s?code=ABC123&state=xyz', HuaweiDriveTestConfig.REDIRECT_URI);
        console.log('Then the authorization code is: ABC123');
        console.log('========================================');

        // 验证授权URL包含必要参数
        expect(authUrl).not().assertUndefined();
        expect(authUrl.length).assertLarger(0);
        expect(authUrl).assertContain('client_id=' + HuaweiDriveTestConfig.CLIENT_ID);
        expect(authUrl).assertContain('redirect_uri=');
        expect(authUrl).assertContain('response_type=code');
        expect(authUrl).assertContain(encodeURIComponent(HuaweiDriveTestConfig.SCOPE_AUTH));

        console.log('Authorization URL validation passed');

      } catch (error) {
        const err = error as Error;
        console.error( 'OAuth2 authentication error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 生成认证授权URL（用于获取授权码 code）。
     * 文档要求：scope 为空格分隔的字符串数组，必须包含 "openid"。
     * 运行本用例会打印出授权URL，浏览器打开授权后，
     * 把重定向URL中 code= 的值填入 HuaweiDriveTestConfig.AUTHORIZATION_CODE，
     * 再运行 should_exchange_code_for_token 换取 Access Token。
     */
    it('should_generate_auth_url_to_obtain_code', 0, async () => {
      try {
        const config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveTestConfig.SCOPE_AUTH);
        config.clientId = HuaweiDriveTestConfig.CLIENT_ID;
        config.clientSecret = HuaweiDriveTestConfig.CLIENT_SECRET;
        config.redirectUri = HuaweiDriveTestConfig.REDIRECT_URI;
        const provider = new HuaweiDriveOAuth2Provider(config);

        const authUrl = provider.getAuthorizationUrl();
        console.log('========================================');
        console.log('【获取授权码】请用浏览器打开以下授权URL：');
        console.log('Authorization URL: %{public}s', authUrl);
        console.log('授权后将重定向到：%{public}s', HuaweiDriveTestConfig.REDIRECT_URI);
        console.log('请把重定向URL中 code= 的值填入 HuaweiDriveTestConfig.AUTHORIZATION_CODE，');
        console.log('然后再运行 should_exchange_code_for_token 换取 Token。');
        console.log('========================================');

        expect(authUrl).not().assertUndefined();
        expect(authUrl).assertContain('client_id=' + HuaweiDriveTestConfig.CLIENT_ID);
        expect(authUrl).assertContain('redirect_uri=');
        expect(authUrl).assertContain('scope=openid');
        expect(authUrl).assertContain('drive');
        expect(authUrl).assertContain('response_type=code');

        console.log('Auth URL generated successfully');
      } catch (error) {
        const err = error as Error;
        console.error( 'Generate auth URL error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    // ==================== 真实 API 用例 ====================
    // 华为云盘为专有云服务，无法本地自建；仅在配置了有效凭证时注册这些用例，
    // 未配置时整体不注册（诚实跳过，见 HuaweiDriveTestConfig.isRealApiEnabled 与 docs/storage-regression-test.md）
    if (HuaweiDriveTestConfig.isRealApiEnabled()) {

    /**
     * 测试通过授权码获取Token
     * 前提条件：需要先运行 should_get_authorization_url_for_token 获取授权码
     * 步骤：
     * 1. 设置授权码（从重定向URL中获取）
     * 2. 使用授权码调用OAuth2接口获取Token
     * 3. 打印ACCESS_TOKEN和REFRESH_TOKEN
     */
    it('should_exchange_code_for_token', 0, async () => {
      try {
        console.log('========================================');
        console.log('Exchange Authorization Code for Token');
        console.log('========================================');

        // 创建OAuth2提供者
        const config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveTestConfig.SCOPE_AUTH);
        config.clientId = HuaweiDriveTestConfig.CLIENT_ID;
        config.clientSecret = HuaweiDriveTestConfig.CLIENT_SECRET;
        config.redirectUri = HuaweiDriveTestConfig.REDIRECT_URI;
        const provider = new HuaweiDriveOAuth2Provider(config);

        // 授权码（一次性）。需先运行 should_generate_auth_url_to_obtain_code 生成授权URL并授权，
        // 把 code 填入 HuaweiDriveTestConfig.AUTHORIZATION_CODE 后再运行本用例。
        const authCode = HuaweiDriveTestConfig.AUTHORIZATION_CODE;
        if (!authCode || authCode.trim().length === 0) {
          console.log('未配置授权码，跳过本用例：请先运行 should_generate_auth_url_to_obtain_code 生成授权URL并进行授权，'
            + '再把 code 填入 HuaweiDriveTestConfig.AUTHORIZATION_CODE');
          return;
        }

        console.log('Using authorization code to get token...');
        console.log('Token Endpoint: %{public}s', config.tokenEndpoint);
        console.log('Client ID: %{public}s', config.clientId);

        // 创建授权请求
        const authRequest: OAuth2AuthRequest = {
          code: decodeURIComponent(authCode),
          state: config.state || ''
        };

        console.log('Sending token request...');

        // 调用authorize方法交换Token
        const token = await provider.authorize(authRequest);

        console.log('========================================');
        console.log('Token Exchange Successful!');
        console.log('========================================');
        console.log('ACCESS_TOKEN: %{public}s', token.accessToken);
        console.log('TOKEN_TYPE: %{public}s', token.tokenType);
        console.log('REFRESH_TOKEN: %{public}s', token.refreshToken || 'N/A');
        console.log('EXPIRES_IN: %{public}d', token.expiresAt || 0);
        console.log('SCOPE: %{public}s', token.scope || 'N/A');
        console.log('========================================');

        // 验证Token
        expect(token).not().assertUndefined();
        expect(token.accessToken).not().assertUndefined();
        expect(token.accessToken.length).assertLarger(0);

        console.log('Token validation passed');

      } catch (error) {
        const err = error as Error;
        console.error( 'Token exchange failed: %{public}s', err.message);
        console.log('');
        console.log('Possible reasons:');
        console.log('1. Authorization code is invalid or expired');
        console.log('2. Authorization code has already been used');
        console.log('3. Client credentials are incorrect');
        console.log('');
        console.log('Please get a new authorization code from:');
        console.log('  Run test: should_get_authorization_url_for_token');
        // 不抛出异常，允许测试失败但继续执行
        expect(false).assertTrue(); // 标记测试失败
      }
    });

    /**
     * 测试使用REFRESH_TOKEN刷新ACCESS_TOKEN
     */
    it('should_refresh_access_token', 0, async () => {
      try {
        console.log('========================================');
        console.log('Refresh Access Token');
        console.log('========================================');

        // 创建OAuth2提供者
        const config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveTestConfig.SCOPE_FULL);
        config.clientId = HuaweiDriveTestConfig.CLIENT_ID;
        config.clientSecret = HuaweiDriveTestConfig.CLIENT_SECRET;
        config.redirectUri = HuaweiDriveTestConfig.REDIRECT_URI;
        const provider = new HuaweiDriveOAuth2Provider(config);

        // 从配置获取刷新令牌
        const refreshToken = HuaweiDriveTestConfig.REFRESH_TOKEN;

        console.log('Using refresh token to get new access token...');
        console.log('Token Endpoint: %{public}s', config.tokenEndpoint);

        // 创建刷新令牌请求
        const refreshRequest: OAuth2RefreshRequest = {
          refreshToken: refreshToken,
          scope: HuaweiDriveTestConfig.SCOPE_FULL
        };

        console.log('Sending refresh token request...');

        // 刷新令牌
        const token = await provider.refreshToken(refreshRequest);

        console.log('========================================');
        console.log('Token Refresh Successful!');
        console.log('========================================');
        console.log('NEW ACCESS_TOKEN: %{public}s', token.accessToken);
        console.log('TOKEN_TYPE: %{public}s', token.tokenType);
        console.log('NEW REFRESH_TOKEN: %{public}s', token.refreshToken || 'N/A');
        console.log('EXPIRES_IN: %{public}d', token.expiresAt || 0);
        console.log('SCOPE: %{public}s', token.scope || 'N/A');
        console.log('========================================');

        // 验证Token
        expect(token).not().assertUndefined();
        expect(token.accessToken).not().assertUndefined();
        expect(token.accessToken.length).assertLarger(0);

        console.log('Token refresh validation passed');

      } catch (error) {
        const err = error as Error;
        console.error( 'Token refresh failed: %{public}s', err.message);
        console.log('');
        console.log('Possible reasons:');
        console.log('1. Refresh token is invalid or expired');
        console.log('2. Client credentials are incorrect');
        console.log('');
        console.log('Please get a new token from:');
        console.log('  Run test: should_exchange_code_for_token');
        // 不抛出异常，允许测试失败但继续执行
        expect(false).assertTrue(); // 标记测试失败
      }
    });

    /**
     * 测试验证连接
     */
    it('should_validate_connection', 0, async () => {
      try {
        const response: HttpResponse = await client.valid();

        console.log('Validation response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response).not().assertUndefined();
        expect(response.success).assertTrue(); // 验证请求必须成功
        expect(response.statusCode).assertEqual(200);
      } catch (error) {
        const err = error as Error;
        console.error( 'Validation error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试获取根目录信息
     */
    it('should_get_root_directory_info', 0, async () => {
      try {
        const response: HttpResponse = await client.getInfo('root');

        console.log('Root info response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response).not().assertUndefined();
        expect(response.success).assertTrue(); // 验证请求必须成功

        if (response.body) {
          const jsonStr = arrayBufferToString(response.body);
          const data = JSON.parse(jsonStr) as Record<string, Object>;

          console.log('Root directory: %{public}s', JSON.stringify(data));

          const file: HuaweiDriveFile = client.parseFile(data);

          expect(file.id).not().assertUndefined();
          console.log('Root directory ID: %{public}s', file.id);
        }
      } catch (error) {
        const err = error as Error;
        console.error( 'Get root info error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试列出根目录文件
     */
    it('should_list_files_in_root', 0, async () => {
      try {
        const response: HttpResponse = await client.list('root');

        console.log('List files response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response).not().assertUndefined();
        expect(response.success).assertTrue(); // 验证请求必须成功

        if (response.body) {
          const jsonStr = arrayBufferToString(response.body);
          const data = JSON.parse(jsonStr) as Record<string, Object>;

          const files: HuaweiDriveFile[] = client.parseFileList(data);

          console.log('Found %{public}d files in root directory', files.length);

          expect(Array.isArray(files)).assertTrue();

          // 打印前几个文件
          for (let i = 0; i < Math.min(5, files.length); i++) {
            console.log('File %{public}d: %{public}s, Type: %{public}s, Size: %{public}d',
              i + 1, files[i].fileName, files[i].mimeType, files[i].size);
          }
        }
      } catch (error) {
        const err = error as Error;
        console.error( 'List files error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试上传文件
     */
    it('should_upload_file', 0, async () => {
      try {
        const testContent = 'Test upload content ' + Date.now();
        const testData = stringToArrayBuffer(testContent);

        const response: HttpResponse = await client.upload(
          'root',
          `test-upload-${Date.now()}.txt`,
          testData
        );

        console.log('Upload response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response).not().assertUndefined();
        expect(response.success).assertTrue(); // 验证请求必须成功

        if (response.body) {
          const jsonStr = arrayBufferToString(response.body);
          const data = JSON.parse(jsonStr) as Record<string, Object>;

          console.log('Uploaded file data: %{public}s', jsonStr);

          const file: HuaweiDriveFile = client.parseFile(data);

          expect(file.fileName).not().assertUndefined();
          console.log('Uploaded file ID: %{public}s', file.id);
        }
      } catch (error) {
        const err = error as Error;
        console.error( 'Upload error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试下载文件
     */
    it('should_download_file', 0, async () => {
      try {
        // 先上传一个测试文件
        const testContent = 'Test download content ' + Date.now();
        const testData = stringToArrayBuffer(testContent);

        const uploadResponse: HttpResponse = await client.upload(
          'root',
          `test-download-${Date.now()}.txt`,
          testData
        );

        expect(uploadResponse.success).assertTrue(); // 验证上传必须成功

        if (uploadResponse.body) {
          const jsonStr = arrayBufferToString(uploadResponse.body);
          const data = JSON.parse(jsonStr) as Record<string, Object>;
          const uploadedFile: HuaweiDriveFile = client.parseFile(data);

          // 下载文件
          const downloadResponse: HttpResponse = await client.download(uploadedFile.id);

          console.log('Download response: status=%{public}d, success=%{public}s',
            downloadResponse.statusCode, downloadResponse.success.toString());

          expect(downloadResponse).not().assertUndefined();
          expect(downloadResponse.success).assertTrue(); // 验证下载必须成功
          expect(downloadResponse.body).not().assertUndefined();

          if (downloadResponse.body) {
            const downloadedContent = arrayBufferToString(downloadResponse.body);

            console.log('Downloaded content length: %{public}d', downloadedContent.length);

            expect(downloadedContent).assertEqual(testContent);
          }
        }
      } catch (error) {
        const err = error as Error;
        console.error( 'Download error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试获取文件信息
     */
    it('should_get_file_info', 0, async () => {
      try {
        // 先上传一个测试文件
        const testContent = 'Test file info ' + Date.now();
        const testData = stringToArrayBuffer(testContent);

        const uploadResponse: HttpResponse = await client.upload(
          'root',
          `test-info-${Date.now()}.txt`,
          testData
        );

        expect(uploadResponse.success).assertTrue(); // 验证上传必须成功

        if (uploadResponse.body) {
          const jsonStr = arrayBufferToString(uploadResponse.body);
          const data = JSON.parse(jsonStr) as Record<string, Object>;
          const uploadedFile: HuaweiDriveFile = client.parseFile(data);

          // 获取文件信息
          const infoResponse: HttpResponse = await client.getInfo(uploadedFile.id);

          console.log('Get info response: status=%{public}d, success=%{public}s',
            infoResponse.statusCode, infoResponse.success.toString());

          expect(infoResponse).not().assertUndefined();
          expect(infoResponse.success).assertTrue(); // 验证获取信息必须成功

          if (infoResponse.body) {
            const infoJsonStr = arrayBufferToString(infoResponse.body);
            const infoData = JSON.parse(infoJsonStr) as Record<string, Object>;

            const fileInfo: HuaweiDriveFile = client.parseFile(infoData);

            console.log('File info: name=%{public}s, size=%{public}d',
              fileInfo.fileName, fileInfo.size);

            expect(fileInfo.id).assertEqual(uploadedFile.id);
            expect(fileInfo.size).assertLarger(0);
          }
        }
      } catch (error) {
        const err = error as Error;
        console.error( 'Get file info error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试错误处理 - 不存在的文件
     */
    it('should_handle_nonexistent_file_error', 0, async () => {
      try {
        const response: HttpResponse = await client.getInfo('nonexistent-file-id-12345');

        console.log('Nonexistent file response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response.success).assertFalse();
        expect(response.statusCode >= 400 && response.statusCode < 500).assertTrue();
      } catch (error) {
        const err = error as Error;
        console.log('Expected error for nonexistent file: %{public}s', err.message);
        expect(err).not().assertUndefined();
      }
    });

    /**
     * 测试小文件更新（≤20M content 简单上传方式回归）
     * 步骤：创建文件 → update 小内容 → 下载校验内容一致 → 删除清理
     */
    it('should_update_small_file_via_content_mode', 0, async () => {
      try {
        // 创建占位文件
        const uploadResponse: HttpResponse = await client.upload(
          'root', `test-content-update-${Date.now()}.txt`, stringToArrayBuffer('placeholder'));
        expect(uploadResponse.success).assertTrue();
        const createdFile: HuaweiDriveFile =
          parseFileResponse(client, uploadResponse);

        // 小内容更新（≤20M 走 content 方式）
        const updatedContent = 'updated small content ' + Date.now();
        const updateResponse: HttpResponse =
          await client.update(createdFile.id, stringToArrayBuffer(updatedContent));
        console.log('Small update response: status=%{public}d, message=%{public}s',
          updateResponse.statusCode, updateResponse.message);
        expect(updateResponse.success).assertTrue();

        // 下载校验内容一致
        const downloadResponse: HttpResponse = await client.download(createdFile.id);
        expect(downloadResponse.success).assertTrue();
        expect(downloadResponse.body).not().assertUndefined();
        expect(arrayBufferToString(requireBody(downloadResponse))).assertEqual(updatedContent);

        // 清理
        await client.delete(createdFile.id);
      } catch (error) {
        const err = error as Error;
        console.error('Small content update error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    // ==================== resume 断点续传用例（>20M，流量较大） ====================
    if (HuaweiDriveTestConfig.isResumeUploadTestEnabled()) {

    /**
     * 测试大文件更新走 resume 断点续传（官方约束：content 方式仅支持 20M 以内）
     * 步骤：创建占位文件 → update 21M+ 模式数据（触发 resume 分片）→
     * getInfo 校验远端 size → 下载抽样校验字节模式（含分片边界）→ 删除清理
     * 注意：用例耗时较长，运行时建议调大 -s timeout
     */
    it('should_update_large_file_via_resume_mode', 0, async () => {
      try {
        const totalBytes = RESUME_TEST_TOTAL_BYTES;
        const bigData = createPatternBuffer(totalBytes);
        const sampleOffsets = buildSampleOffsets(totalBytes);

        // 创建占位文件
        const uploadResponse: HttpResponse = await client.upload(
          'root', `test-resume-update-${Date.now()}.txt`, stringToArrayBuffer('placeholder'));
        expect(uploadResponse.success).assertTrue();
        const createdFile: HuaweiDriveFile =
          parseFileResponse(client, uploadResponse);

        // 大内容更新（>20M 触发 Files.update.resume 分片上传）
        const updateResponse: HttpResponse = await client.update(createdFile.id, bigData);
        console.log('Resume update response: status=%{public}d, message=%{public}s',
          updateResponse.statusCode, updateResponse.message);
        expect(updateResponse.success).assertTrue();

        // 校验远端文件 size
        const infoResponse: HttpResponse = await client.getInfo(createdFile.id);
        expect(infoResponse.success).assertTrue();
        const remoteFile: HuaweiDriveFile =
          parseFileResponse(client, infoResponse);
        console.log('Remote size=%{public}d, expected=%{public}d', remoteFile.size, totalBytes);
        expect(remoteFile.size).assertEqual(totalBytes);

        // 下载抽样校验（总长度 + 分片边界附近字节模式）
        const downloadResponse: HttpResponse = await client.download(createdFile.id);
        expect(downloadResponse.success).assertTrue();
        expect(downloadResponse.body).not().assertUndefined();
        expect(verifyPattern(requireBody(downloadResponse), totalBytes, sampleOffsets)).assertTrue();

        // 清理
        await client.delete(createdFile.id);
      } catch (error) {
        const err = error as Error;
        console.error('Resume update error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试大文件 updateFromFile 流式断点续传（分片按需读自本地文件，内存基线为单个分片）
     * 步骤：本地写入 21M+ 模式临时文件 → 创建占位文件 → updateFromFile →
     * getInfo 校验 size → 下载抽样校验 → 删除远端文件并清理本地临时文件
     */
    it('should_update_large_file_from_local_via_resume_mode', 0, async () => {
      try {
        const totalBytes = RESUME_TEST_TOTAL_BYTES;
        const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
        const tempPath = `${appContext.cacheDir}/test-resume-file-${Date.now()}.bin`;
        writePatternFile(tempPath, totalBytes);

        try {
          // 创建占位文件
          const uploadResponse: HttpResponse = await client.upload(
            'root', `test-resume-from-file-${Date.now()}.txt`, stringToArrayBuffer('placeholder'));
          expect(uploadResponse.success).assertTrue();
          const createdFile: HuaweiDriveFile =
            parseFileResponse(client, uploadResponse);

          // 流式更新（>20M 触发 resume 分片，分片读自本地文件）
          const updateResponse: HttpResponse = await client.updateFromFile(createdFile.id, tempPath);
          console.log('Resume updateFromFile response: status=%{public}d, message=%{public}s',
            updateResponse.statusCode, updateResponse.message);
          expect(updateResponse.success).assertTrue();

          // 校验远端文件 size
          const infoResponse: HttpResponse = await client.getInfo(createdFile.id);
          expect(infoResponse.success).assertTrue();
          const remoteFile: HuaweiDriveFile =
            parseFileResponse(client, infoResponse);
          console.log('Remote size=%{public}d, expected=%{public}d', remoteFile.size, totalBytes);
          expect(remoteFile.size).assertEqual(totalBytes);

          // 下载抽样校验
          const downloadResponse: HttpResponse = await client.download(createdFile.id);
          expect(downloadResponse.success).assertTrue();
          expect(downloadResponse.body).not().assertUndefined();
          expect(verifyPattern(requireBody(downloadResponse), totalBytes, buildSampleOffsets(totalBytes))).assertTrue();

          // 清理远端
          await client.delete(createdFile.id);
        } finally {
          // 清理本地临时文件
          try {
            fs.unlinkSync(tempPath);
          } catch (e) {
            console.warn('Cleanup temp file failed: %{public}s', (e as Error).message);
          }
        }
      } catch (error) {
        const err = error as Error;
        console.error('Resume updateFromFile error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试新建大文件上传（upload 内部委托 update 按大小自动选择 resume）
     * 步骤：upload 直接携带 21M+ 内容 → getInfo 校验 size → 下载抽样校验 → 删除清理
     */
    it('should_upload_large_new_file_via_resume_mode', 0, async () => {
      try {
        const totalBytes = RESUME_TEST_TOTAL_BYTES;
        const bigData = createPatternBuffer(totalBytes);

        // 新建文件并上传大内容
        const uploadResponse: HttpResponse = await client.upload(
          'root', `test-resume-upload-new-${Date.now()}.txt`, bigData);
        console.log('Resume upload response: status=%{public}d, message=%{public}s',
          uploadResponse.statusCode, uploadResponse.message);
        expect(uploadResponse.success).assertTrue();
        const createdFile: HuaweiDriveFile =
          parseFileResponse(client, uploadResponse);

        // 校验远端 size + 下载抽样
        const infoResponse: HttpResponse = await client.getInfo(createdFile.id);
        expect(infoResponse.success).assertTrue();
        const remoteFile: HuaweiDriveFile =
          parseFileResponse(client, infoResponse);
        expect(remoteFile.size).assertEqual(totalBytes);

        const downloadResponse: HttpResponse = await client.download(createdFile.id);
        expect(downloadResponse.success).assertTrue();
        expect(downloadResponse.body).not().assertUndefined();
        expect(verifyPattern(requireBody(downloadResponse), totalBytes, buildSampleOffsets(totalBytes))).assertTrue();

        // 清理
        await client.delete(createdFile.id);
      } catch (error) {
        const err = error as Error;
        console.error('Resume upload new file error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    } // end isResumeUploadTestEnabled

    } // end isRealApiEnabled
  });
}
