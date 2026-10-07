import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';

/**
 * 测试上下文辅助：获取当前顶部 Ability 的真实 UIAbilityContext。
 *
 * 不使用 AbilityDelegator.getAppContext()：其返回的 ApplicationContext 传入
 * preferences.getPreferences 等数据接口时会报 401 "Parameter error. The context is invalid."，
 * 官方推荐通过 getCurrentTopAbility() 拿到 Ability 后使用其 context。
 */
export class TestContextHelper {
  public static async getUIAbilityContext(): Promise<common.UIAbilityContext> {
    const delegator: abilityDelegatorRegistry.AbilityDelegator =
      abilityDelegatorRegistry.getAbilityDelegator();
    const ability = await delegator.getCurrentTopAbility();
    return ability.context;
  }
}
