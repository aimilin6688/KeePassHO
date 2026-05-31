// 存储测试公共配置基类
// 各存储后端的测试配置应继承此类，提供以下信息：
// - 测试用的配置对象（绕过生产环境的 SM4 加密）
// - 测试使用的共享常量
export class TestStorageConfig {
  // 测试存储类型标识
  storageType: string = '';

  // 是否启用真实API集成测试
  // 设为 false 时，集成测试应该跳过
  enableIntegrationTests: boolean = false;
}
