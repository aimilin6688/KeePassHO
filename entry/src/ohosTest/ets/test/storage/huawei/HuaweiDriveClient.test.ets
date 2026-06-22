import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { HuaweiDriveClient, HuaweiDriveClientOptions, HuaweiDriveFile, HttpResponse } from '../../../../../main/ets/storage/huawei/HuaweiDriveClient';
import { HuaweiDriveTestConfig } from './HuaweiDriveTestConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { HuaweiDriveOAuth2Provider } from '../../../../../main/ets/storage/huawei/HuaweiDriveOAuth2Provider';
import { OAuth2AuthRequest, OAuth2RefreshRequest } from '../../../../../main/ets/common/oauth2/OAuth2Types';

const DOMAIN = 0x0000;
const TAG = 'HuaweiDriveClientTest';

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
        hilog.info(DOMAIN, TAG, '========================================');
        hilog.info(DOMAIN, TAG, 'Huawei Drive OAuth2 Authentication');
        hilog.info(DOMAIN, TAG, '========================================');

        // 创建OAuth2提供者
        const config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveTestConfig.SCOPE_FULL);
        config.clientId = HuaweiDriveTestConfig.CLIENT_ID;
        config.clientSecret = HuaweiDriveTestConfig.CLIENT_SECRET;
        config.redirectUri = HuaweiDriveTestConfig.REDIRECT_URI;
        const provider = new HuaweiDriveOAuth2Provider(config);

        // 获取授权URL
        const authUrl = provider.getAuthorizationUrl();
        hilog.info(DOMAIN, TAG, 'Step 1: Get Authorization URL');
        hilog.info(DOMAIN, TAG, 'Authorization URL: %{public}s', authUrl);
        hilog.info(DOMAIN, TAG, '');
        hilog.info(DOMAIN, TAG, 'Step 2: Manual Action Required');
        hilog.info(DOMAIN, TAG, 'Please visit the above URL in your browser');
        hilog.info(DOMAIN, TAG, 'After authorization, you will be redirected to:');
        hilog.info(DOMAIN, TAG, '  %{public}s', HuaweiDriveTestConfig.REDIRECT_URI);
        hilog.info(DOMAIN, TAG, 'Copy the "code" parameter from the redirect URL');
        hilog.info(DOMAIN, TAG, '');
        hilog.info(DOMAIN, TAG, 'Step 3: Use Authorization Code to Get Token');
        hilog.info(DOMAIN, TAG, 'Example: If redirect URL is:');
        hilog.info(DOMAIN, TAG, '  %{public}s?code=ABC123&state=xyz', HuaweiDriveTestConfig.REDIRECT_URI);
        hilog.info(DOMAIN, TAG, 'Then the authorization code is: ABC123');
        hilog.info(DOMAIN, TAG, '========================================');

        // 验证授权URL包含必要参数
        expect(authUrl).not().assertUndefined();
        expect(authUrl.length).assertLarger(0);
        expect(authUrl).assertContain('client_id');
        expect(authUrl).assertContain('redirect_uri');
        expect(authUrl).assertContain('response_type=code');
        expect(authUrl).assertContain(HuaweiDriveTestConfig.CLIENT_ID);

        hilog.info(DOMAIN, TAG, 'Authorization URL validation passed');

      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'OAuth2 authentication error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

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
        hilog.info(DOMAIN, TAG, '========================================');
        hilog.info(DOMAIN, TAG, 'Exchange Authorization Code for Token');
        hilog.info(DOMAIN, TAG, '========================================');

        // 创建OAuth2提供者
        const config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveTestConfig.SCOPE_FULL);
        config.clientId = HuaweiDriveTestConfig.CLIENT_ID;
        config.clientSecret = HuaweiDriveTestConfig.CLIENT_SECRET;
        config.redirectUri = HuaweiDriveTestConfig.REDIRECT_URI;
        const provider = new HuaweiDriveOAuth2Provider(config);

        // 从HuaweiDriveTestConfig获取授权码（测试时需要手动设置）
        // 注意：授权码是一次性的，使用后会失效
        // 测试前请在 HuaweiDriveTestConfig 中设置有效的授权码
        const authCode = "EQEEADecUXRZ5ORXDj9umw7yVH%2BE1A1VV472VBksRbwBTIi42tnqImQgeFzPJi8i2UHk9mvljlX1aGoU4jhUzYN8NfZrKLquySJai1yHHVBPGcvr%2F6WGVG5bjB74bH1jp9ZuQOusWEcwmgSEQkT5Wc8lHtw1Qo%2FuxLLdGwJyr2woPIeRt4ic0Xaf57zPYRNvajv7uqKyEDxXMYDt6y8yNrtbBm9AKgyY8ljdPljIVmgEqdc2ujpI38D35yiZQlGMm5r7dmwMhGTjMccfVeFtYzI%3D"; // 临时使用，实际应该是授权码

        hilog.info(DOMAIN, TAG, 'Using authorization code to get token...');
        hilog.info(DOMAIN, TAG, 'Token Endpoint: %{public}s', config.tokenEndpoint);
        hilog.info(DOMAIN, TAG, 'Client ID: %{public}s', config.clientId);

        // 创建授权请求
        const authRequest: OAuth2AuthRequest = {
          code: decodeURIComponent(authCode),
          state: config.state || ''
        };

        hilog.info(DOMAIN, TAG, 'Sending token request...');

        // 调用authorize方法交换Token
        const token = await provider.authorize(authRequest);

        hilog.info(DOMAIN, TAG, '========================================');
        hilog.info(DOMAIN, TAG, 'Token Exchange Successful!');
        hilog.info(DOMAIN, TAG, '========================================');
        hilog.info(DOMAIN, TAG, 'ACCESS_TOKEN: %{public}s', token.accessToken);
        hilog.info(DOMAIN, TAG, 'TOKEN_TYPE: %{public}s', token.tokenType);
        hilog.info(DOMAIN, TAG, 'REFRESH_TOKEN: %{public}s', token.refreshToken || 'N/A');
        hilog.info(DOMAIN, TAG, 'EXPIRES_IN: %{public}d', token.expiresAt || 0);
        hilog.info(DOMAIN, TAG, 'SCOPE: %{public}s', token.scope || 'N/A');
        hilog.info(DOMAIN, TAG, '========================================');

        // 验证Token
        expect(token).not().assertUndefined();
        expect(token.accessToken).not().assertUndefined();
        expect(token.accessToken.length).assertLarger(0);

        hilog.info(DOMAIN, TAG, 'Token validation passed');

      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Token exchange failed: %{public}s', err.message);
        hilog.info(DOMAIN, TAG, '');
        hilog.info(DOMAIN, TAG, 'Possible reasons:');
        hilog.info(DOMAIN, TAG, '1. Authorization code is invalid or expired');
        hilog.info(DOMAIN, TAG, '2. Authorization code has already been used');
        hilog.info(DOMAIN, TAG, '3. Client credentials are incorrect');
        hilog.info(DOMAIN, TAG, '');
        hilog.info(DOMAIN, TAG, 'Please get a new authorization code from:');
        hilog.info(DOMAIN, TAG, '  Run test: should_get_authorization_url_for_token');
        // 不抛出异常，允许测试失败但继续执行
        expect(false).assertTrue(); // 标记测试失败
      }
    });

    /**
     * 测试使用REFRESH_TOKEN刷新ACCESS_TOKEN
     */
    it('should_refresh_access_token', 0, async () => {
      try {
        hilog.info(DOMAIN, TAG, '========================================');
        hilog.info(DOMAIN, TAG, 'Refresh Access Token');
        hilog.info(DOMAIN, TAG, '========================================');

        // 创建OAuth2提供者
        const config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveTestConfig.SCOPE_FULL);
        config.clientId = HuaweiDriveTestConfig.CLIENT_ID;
        config.clientSecret = HuaweiDriveTestConfig.CLIENT_SECRET;
        config.redirectUri = HuaweiDriveTestConfig.REDIRECT_URI;
        const provider = new HuaweiDriveOAuth2Provider(config);

        // 从配置获取刷新令牌
        const refreshToken = HuaweiDriveTestConfig.REFRESH_TOKEN;

        hilog.info(DOMAIN, TAG, 'Using refresh token to get new access token...');
        hilog.info(DOMAIN, TAG, 'Token Endpoint: %{public}s', config.tokenEndpoint);

        // 创建刷新令牌请求
        const refreshRequest: OAuth2RefreshRequest = {
          refreshToken: refreshToken,
          scope: HuaweiDriveTestConfig.SCOPE_FULL
        };

        hilog.info(DOMAIN, TAG, 'Sending refresh token request...');

        // 刷新令牌
        const token = await provider.refreshToken(refreshRequest);

        hilog.info(DOMAIN, TAG, '========================================');
        hilog.info(DOMAIN, TAG, 'Token Refresh Successful!');
        hilog.info(DOMAIN, TAG, '========================================');
        hilog.info(DOMAIN, TAG, 'NEW ACCESS_TOKEN: %{public}s', token.accessToken);
        hilog.info(DOMAIN, TAG, 'TOKEN_TYPE: %{public}s', token.tokenType);
        hilog.info(DOMAIN, TAG, 'NEW REFRESH_TOKEN: %{public}s', token.refreshToken || 'N/A');
        hilog.info(DOMAIN, TAG, 'EXPIRES_IN: %{public}d', token.expiresAt || 0);
        hilog.info(DOMAIN, TAG, 'SCOPE: %{public}s', token.scope || 'N/A');
        hilog.info(DOMAIN, TAG, '========================================');

        // 验证Token
        expect(token).not().assertUndefined();
        expect(token.accessToken).not().assertUndefined();
        expect(token.accessToken.length).assertLarger(0);

        hilog.info(DOMAIN, TAG, 'Token refresh validation passed');

      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Token refresh failed: %{public}s', err.message);
        hilog.info(DOMAIN, TAG, '');
        hilog.info(DOMAIN, TAG, 'Possible reasons:');
        hilog.info(DOMAIN, TAG, '1. Refresh token is invalid or expired');
        hilog.info(DOMAIN, TAG, '2. Client credentials are incorrect');
        hilog.info(DOMAIN, TAG, '');
        hilog.info(DOMAIN, TAG, 'Please get a new token from:');
        hilog.info(DOMAIN, TAG, '  Run test: should_exchange_code_for_token');
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

        hilog.info(DOMAIN, TAG, 'Validation response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response).not().assertUndefined();
        expect(response.success).assertTrue(); // 验证请求必须成功
        expect(response.statusCode).assertEqual(200);
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Validation error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试获取根目录信息
     */
    it('should_get_root_directory_info', 0, async () => {
      try {
        const response: HttpResponse = await client.getInfo('root');

        hilog.info(DOMAIN, TAG, 'Root info response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response).not().assertUndefined();
        expect(response.success).assertTrue(); // 验证请求必须成功

        if (response.body) {
          const jsonStr = arrayBufferToString(response.body);
          const data = JSON.parse(jsonStr) as Record<string, Object>;

          hilog.info(DOMAIN, TAG, 'Root directory: %{public}s', JSON.stringify(data));

          const file: HuaweiDriveFile = client.parseFile(data);

          expect(file.id).not().assertUndefined();
          hilog.info(DOMAIN, TAG, 'Root directory ID: %{public}s', file.id);
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Get root info error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试列出根目录文件
     */
    it('should_list_files_in_root', 0, async () => {
      try {
        const response: HttpResponse = await client.list('root');

        hilog.info(DOMAIN, TAG, 'List files response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response).not().assertUndefined();
        expect(response.success).assertTrue(); // 验证请求必须成功

        if (response.body) {
          const jsonStr = arrayBufferToString(response.body);
          const data = JSON.parse(jsonStr) as Record<string, Object>;

          const files: HuaweiDriveFile[] = client.parseFileList(data);

          hilog.info(DOMAIN, TAG, 'Found %{public}d files in root directory', files.length);

          expect(Array.isArray(files)).assertTrue();

          // 打印前几个文件
          for (let i = 0; i < Math.min(5, files.length); i++) {
            hilog.info(DOMAIN, TAG, 'File %{public}d: %{public}s, Type: %{public}s, Size: %{public}d',
              i + 1, files[i].fileName, files[i].mimeType, files[i].size);
          }
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'List files error: %{public}s', err.message);
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

        hilog.info(DOMAIN, TAG, 'Upload response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response).not().assertUndefined();
        expect(response.success).assertTrue(); // 验证请求必须成功

        if (response.body) {
          const jsonStr = arrayBufferToString(response.body);
          const data = JSON.parse(jsonStr) as Record<string, Object>;

          hilog.info(DOMAIN, TAG, 'Uploaded file data: %{public}s', jsonStr);

          const file: HuaweiDriveFile = client.parseFile(data);

          expect(file.fileName).not().assertUndefined();
          hilog.info(DOMAIN, TAG, 'Uploaded file ID: %{public}s', file.id);
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Upload error: %{public}s', err.message);
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

          hilog.info(DOMAIN, TAG, 'Download response: status=%{public}d, success=%{public}s',
            downloadResponse.statusCode, downloadResponse.success.toString());

          expect(downloadResponse).not().assertUndefined();
          expect(downloadResponse.success).assertTrue(); // 验证下载必须成功
          expect(downloadResponse.body).not().assertUndefined();

          if (downloadResponse.body) {
            const downloadedContent = arrayBufferToString(downloadResponse.body);

            hilog.info(DOMAIN, TAG, 'Downloaded content length: %{public}d', downloadedContent.length);

            expect(downloadedContent).assertEqual(testContent);
          }
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Download error: %{public}s', err.message);
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

          hilog.info(DOMAIN, TAG, 'Get info response: status=%{public}d, success=%{public}s',
            infoResponse.statusCode, infoResponse.success.toString());

          expect(infoResponse).not().assertUndefined();
          expect(infoResponse.success).assertTrue(); // 验证获取信息必须成功

          if (infoResponse.body) {
            const infoJsonStr = arrayBufferToString(infoResponse.body);
            const infoData = JSON.parse(infoJsonStr) as Record<string, Object>;

            const fileInfo: HuaweiDriveFile = client.parseFile(infoData);

            hilog.info(DOMAIN, TAG, 'File info: name=%{public}s, size=%{public}d',
              fileInfo.fileName, fileInfo.size);

            expect(fileInfo.id).assertEqual(uploadedFile.id);
            expect(fileInfo.size).assertLarger(0);
          }
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Get file info error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试错误处理 - 不存在的文件
     */
    it('should_handle_nonexistent_file_error', 0, async () => {
      try {
        const response: HttpResponse = await client.getInfo('nonexistent-file-id-12345');

        hilog.info(DOMAIN, TAG, 'Nonexistent file response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response.success).assertFalse();
        expect(response.statusCode).assertEqual(404);
      } catch (error) {
        const err = error as Error;
        hilog.info(DOMAIN, TAG, 'Expected error for nonexistent file: %{public}s', err.message);
        expect(err).not().assertUndefined();
      }
    });
  });
}
