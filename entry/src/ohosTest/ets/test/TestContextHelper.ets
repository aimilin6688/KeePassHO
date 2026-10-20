import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';

/**
 * 测试上下文辅助：获取当前顶部 Ability 的真实 UIAbilityContext。
 *
 * 首选 getCurrentTopAbility()（官方推荐，其 context 可安全传入 preferences 等数据接口）；
 * 顶部 Ability 暂不可得（如系统授权弹窗占据前台）时回退 getAppContext()：
 * 其返回的 ApplicationContext 传入 preferences.getPreferences 等数据接口时
 * 可能报 401 "Parameter error. The context is invalid."，仅作兜底避免 beforeAll 整体失败。
 */
export class TestContextHelper {
  public static async getUIAbilityContext(): Promise<common.UIAbilityContext> {
    try {
      const delegator: abilityDelegatorRegistry.AbilityDelegator =
        abilityDelegatorRegistry.getAbilityDelegator();
      const ability = await delegator.getCurrentTopAbility();
      return ability.context;
    } catch (e) {
      return abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.UIAbilityContext;
    }
  }
}
