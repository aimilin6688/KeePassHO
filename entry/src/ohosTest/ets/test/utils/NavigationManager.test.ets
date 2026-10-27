import { afterAll, describe, expect, it } from '@ohos/hypium';
import { NavigationManager } from '../../../../main/ets/common/utils/NavigationManager';
import { PageConfigManager } from '../../../../main/ets/common/utils/PageConfigManager';
import { NavigationModeType } from '../../../../main/ets/common/constants/PageConfig';
import { PageConstants } from '../../../../main/ets/common/constants/PageConstants';

export default function NavigationManagerTest() {
  describe('NavigationManager', () => {
    // ---------------- singleton ----------------
    it('getInstance returns the same instance', 0, () => {
      expect(NavigationManager.getInstance() === NavigationManager.getInstance()).assertTrue();
    });

    // ---------------- default root pages ----------------
    it('default current and previous root page are Index', 0, () => {
      expect(NavigationManager.getInstance().getCurrentRootPage()).assertEqual(PageConstants.PAGE_INDEX);
      expect(NavigationManager.getInstance().getPreviousRootPage()).assertEqual(PageConstants.PAGE_INDEX);
    });

    // ---------------- nav path stack registry ----------------
    it('getOrCreateNavPathStack returns same stack per root and null for unknown root', 0, () => {
      const mgr = NavigationManager.getInstance();
      const root = 'NMRegistryRoot';
      const stackA = mgr.getOrCreateNavPathStack(root);
      const stackB = mgr.getOrCreateNavPathStack(root);
      expect(stackA === stackB).assertTrue();
      expect(stackA === mgr.getNavPathStackByRoot(root)).assertTrue();
      expect(mgr.getNavPathStackByRoot('NMUnknownRoot')).assertNull();
      mgr.removeNavPathStack(root);
    });

    it('different roots get independent stacks', 0, () => {
      const mgr = NavigationManager.getInstance();
      const stackA = mgr.getOrCreateNavPathStack('NMRootA');
      const stackB = mgr.getOrCreateNavPathStack('NMRootB');
      expect(stackA === stackB).assertFalse();
      mgr.removeNavPathStack('NMRootA');
      mgr.removeNavPathStack('NMRootB');
    });

    // ---------------- current stack + push/pop ----------------
    it('setCurrentNavPathStack, navigateTo, pop and getStackSize work together', 0, () => {
      const mgr = NavigationManager.getInstance();
      mgr.setCurrentNavPathStack('NMCurrentRoot');
      const stack = mgr.getOrCreateNavPathStack('NMCurrentRoot');
      expect(mgr.getNavPathStack() === stack).assertTrue();
      expect(mgr.getStackSize()).assertEqual(0);
      mgr.navigateTo('NMDetailPage');
      expect(mgr.getStackSize()).assertEqual(1);
      mgr.pop();
      expect(mgr.getStackSize()).assertEqual(0);
      mgr.removeNavPathStack('NMCurrentRoot');
    });

    it('replaceAll leaves exactly one page on the stack', 0, () => {
      const mgr = NavigationManager.getInstance();
      mgr.setCurrentNavPathStack('NMReplaceRoot');
      mgr.navigateTo('PageOne');
      mgr.navigateTo('PageTwo');
      expect(mgr.getStackSize()).assertEqual(2);
      mgr.replaceAll('NMReplacementPage');
      expect(mgr.getStackSize()).assertEqual(1);
      mgr.removeNavPathStack('NMReplaceRoot');
    });

    // ---------------- clear / remove stack ----------------
    it('clearNavPathStack empties the stack and removeNavPathStack deletes it', 0, () => {
      const mgr = NavigationManager.getInstance();
      const root = 'NMClearRoot';
      mgr.setCurrentNavPathStack(root);
      mgr.navigateTo('PageOne');
      expect(mgr.getStackSize()).assertEqual(1);
      mgr.clearNavPathStack(root);
      expect(mgr.getStackSize()).assertEqual(0);
      mgr.removeNavPathStack(root);
      expect(mgr.getNavPathStackByRoot(root)).assertNull();
      // re-created stack is fresh and empty
      expect(mgr.getOrCreateNavPathStack(root).size()).assertEqual(0);
      mgr.removeNavPathStack(root);
    });

    // ---------------- navigateBackToRoot ----------------
    it('navigateBackToRoot updates current/previous roots and notifies root page listeners', 0, () => {
      const mgr = NavigationManager.getInstance();
      const roots: string[] = [];
      const listener = (rootPage: string): void => {
        roots.push(rootPage);
      };
      mgr.addRootPageChangeListener(listener);
      mgr.navigateBackToRoot(PageConstants.PAGE_SETTINGS);
      expect(mgr.getCurrentRootPage()).assertEqual(PageConstants.PAGE_SETTINGS);
      expect(mgr.getPreviousRootPage()).assertEqual(PageConstants.PAGE_INDEX);
      // switching back to the same root does not notify again
      mgr.navigateBackToRoot(PageConstants.PAGE_SETTINGS);
      expect(roots.length).assertEqual(1);
      mgr.removeRootPageChangeListener(listener);
      mgr.navigateBackToRoot(PageConstants.PAGE_INDEX);
      expect(mgr.getCurrentRootPage()).assertEqual(PageConstants.PAGE_INDEX);
    });

    it('navigateBackToRoot uses fallback config for unknown root', 0, () => {
      const mgr = NavigationManager.getInstance();
      const unknownRoot = 'NMNoConfigRoot';
      mgr.navigateBackToRoot(unknownRoot);
      expect(mgr.getCurrentRootPage()).assertEqual(unknownRoot);
      expect(mgr.getPreviousRootPage()).assertEqual(PageConstants.PAGE_INDEX);
      const config = mgr.getCurrentPageConfig();
      expect(config.name).assertEqual(unknownRoot);
      expect(config.navigationMode).assertEqual(NavigationModeType.EXCLUSIVE);
      expect(config.constrainMaxWidth).assertTrue();
      expect(config.maxWidth).assertEqual(700);
      expect(config.padding).assertEqual(16);
      expect(mgr.getCurrentStackMode()).assertEqual(NavigationModeType.EXCLUSIVE);
      mgr.navigateBackToRoot(PageConstants.PAGE_INDEX);
    });

    // ---------------- mode change listeners ----------------
    it('mode change listener is notified when navigation mode flips', 0, () => {
      const mgr = NavigationManager.getInstance();
      const modes: NavigationModeType[] = [];
      const listener = (mode: NavigationModeType): void => {
        modes.push(mode);
      };
      mgr.addModeChangeListener(listener);
      mgr.navigateBackToRoot(PageConstants.PAGE_SETTINGS);
      mgr.navigateBackToRoot(PageConstants.PAGE_INDEX);
      mgr.removeModeChangeListener(listener);
      expect(modes.length).assertEqual(2);
      expect(modes[0]).assertEqual(NavigationModeType.SPLIT);
      expect(modes[1]).assertEqual(NavigationModeType.EXCLUSIVE);
    });

    it('removed mode change listener is not notified', 0, () => {
      const mgr = NavigationManager.getInstance();
      let notified = 0;
      const listener = (mode: NavigationModeType): void => {
        notified++;
      };
      mgr.addModeChangeListener(listener);
      mgr.removeModeChangeListener(listener);
      mgr.navigateBackToRoot(PageConstants.PAGE_SETTINGS);
      mgr.navigateBackToRoot(PageConstants.PAGE_INDEX);
      expect(notified).assertEqual(0);
    });

    it('root page change listener is notified on root switch', 0, () => {
      const mgr = NavigationManager.getInstance();
      const roots: string[] = [];
      const listener = (rootPage: string): void => {
        roots.push(rootPage);
      };
      mgr.addRootPageChangeListener(listener);
      mgr.navigateBackToRoot(PageConstants.PAGE_SETTINGS);
      mgr.removeRootPageChangeListener(listener);
      mgr.navigateBackToRoot(PageConstants.PAGE_INDEX);
      expect(roots.length).assertEqual(1);
      expect(roots[0]).assertEqual(PageConstants.PAGE_SETTINGS);
    });

    // ---------------- handleSystemBack ----------------
    it('handleSystemBack returns false on Index root without handler', 0, () => {
      const mgr = NavigationManager.getInstance();
      mgr.navigateBackToRoot(PageConstants.PAGE_INDEX);
      expect(mgr.handleSystemBack()).assertFalse();
    });

    it('handleSystemBack navigates back from secondary root and returns true', 0, () => {
      const mgr = NavigationManager.getInstance();
      mgr.navigateBackToRoot(PageConstants.PAGE_SETTINGS);
      expect(mgr.getCurrentRootPage()).assertEqual(PageConstants.PAGE_SETTINGS);
      expect(mgr.handleSystemBack()).assertTrue();
      expect(mgr.getCurrentRootPage()).assertEqual(PageConstants.PAGE_INDEX);
      // back on Index: default exit behaviour is preserved
      expect(mgr.handleSystemBack()).assertFalse();
    });

    it('systemBackHandler consumes back event before root fallback', 0, () => {
      const mgr = NavigationManager.getInstance();
      let invoked = 0;
      const handler = (): boolean => {
        invoked++;
        return true;
      };
      mgr.setSystemBackHandler(handler);
      expect(mgr.handleSystemBack()).assertTrue();
      expect(invoked).assertEqual(1);

      // non-consuming handler falls through to the root fallback logic
      mgr.navigateBackToRoot(PageConstants.PAGE_SETTINGS);
      mgr.setSystemBackHandler((): boolean => false);
      expect(mgr.handleSystemBack()).assertTrue();
      expect(mgr.getCurrentRootPage()).assertEqual(PageConstants.PAGE_INDEX);

      mgr.setSystemBackHandler(null);
      expect(mgr.handleSystemBack()).assertFalse();
    });

    // ---------------- NavigationModeType values ----------------
    it('NavigationModeType enum values are stable', 0, () => {
      expect(NavigationModeType.EXCLUSIVE).assertEqual('exclusive');
      expect(NavigationModeType.SPLIT).assertEqual('split');
    });

    // ---------------- PageConfigManager wiring ----------------
    it('getCurrentPageConfig for known root comes from PageConfigManager', 0, () => {
      const mgr = NavigationManager.getInstance();
      mgr.navigateBackToRoot(PageConstants.PAGE_SETTINGS);
      const config = mgr.getCurrentPageConfig();
      expect(config.name).assertEqual(PageConstants.PAGE_SETTINGS);
      expect(config.navigationMode).assertEqual(NavigationModeType.SPLIT);
      expect(config === PageConfigManager.getInstance().getPageConfig(PageConstants.PAGE_SETTINGS)).assertTrue();
      mgr.navigateBackToRoot(PageConstants.PAGE_INDEX);
    });

    // ---------------- 单例状态收尾清理 ----------------
    // setCurrentNavPathStack 会写入进程级单例的 currentNavPathStack；
    // 若不清理，后续套件（CSV 导入向导等）会拿到游离栈导致用例挂起。
    afterAll(() => {
      NavigationManager.getInstance().clearCurrentNavPathStack();
    });
  });
}
