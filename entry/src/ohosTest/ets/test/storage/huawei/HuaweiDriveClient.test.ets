import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { HuaweiDriveClient, HuaweiDriveClientOptions, HuaweiDriveFile, HttpResponse } from '../../../../../main/ets/storage/huawei/HuaweiDriveClient';
import { HuaweiDriveTestConfig } from './HuaweiDriveTestConfig';
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
  });
}
