import { describe, expect, it } from '@ohos/hypium';
import { IconUtils } from '../../../../main/ets/common/utils/IconUtils';
import { IconResource, Icons } from '../../../../main/ets/services/TypeDefined';

function resourceId(iconId: number): number {
  return (IconUtils.getIconResourcePath(iconId) as Resource).id;
}

export default function IconUtilsTest() {
  describe('IconUtils', () => {
    // ---------------- getIconResourcePath (numeric ids) ----------------
    it('getIconResourcePath returns a Resource for valid ids', 0, () => {
      const first = IconUtils.getIconResourcePath(Icons.Key) as Resource;
      const last = IconUtils.getIconResourcePath(Icons.BlackBerry) as Resource;
      expect(first).not().assertNull();
      expect(last).not().assertNull();
      expect(typeof first.id).assertEqual('number');
      expect(typeof last.id).assertEqual('number');
    });

    it('different icon ids map to different resources', 0, () => {
      expect(resourceId(Icons.Key) !== resourceId(Icons.World)).assertTrue();
      expect(resourceId(Icons.World) !== resourceId(Icons.Folder)).assertTrue();
      expect(resourceId(Icons.Key) !== resourceId(Icons.BlackBerry)).assertTrue();
      expect(resourceId(Icons.Folder) !== resourceId(Icons.FolderOpen)).assertTrue();
    });

    it('same icon id maps to the same resource repeatedly', 0, () => {
      expect(resourceId(Icons.Key)).assertEqual(resourceId(Icons.Key));
      expect(resourceId(Icons.Star)).assertEqual(resourceId(Icons.Star));
    });

    it('unknown icon id falls back to the Folder default icon', 0, () => {
      expect(resourceId(999)).assertEqual(resourceId(Icons.Folder));
      expect(resourceId(-1)).assertEqual(resourceId(Icons.Folder));
    });

    it('boundary ids 0 and 68 are mapped (not fallback)', 0, () => {
      expect(resourceId(0)).assertEqual(resourceId(Icons.Key));
      expect(resourceId(68)).assertEqual(resourceId(Icons.BlackBerry));
      expect(resourceId(68) !== resourceId(Icons.Folder)).assertTrue();
    });

    // ---------------- getAllIcons ----------------
    it('getAllIcons returns all 69 system icons in order', 0, () => {
      const icons: Array<IconResource> = IconUtils.getAllIcons();
      expect(icons.length >= 69).assertTrue();
      expect(icons[0].id).assertEqual(0);
      expect(icons[68].id).assertEqual(68);
      for (let i = 0; i < 69; i++) {
        expect(typeof icons[i].id).assertEqual('number');
      }
    });

    it('getAllIcons with onlyCustom=true never throws and returns an array', 0, () => {
      let noThrow = true;
      let icons: Array<IconResource> = [];
      try {
        icons = IconUtils.getAllIcons(true);
      } catch {
        noThrow = false;
      }
      expect(noThrow).assertTrue();
      expect(icons.length >= 0).assertTrue();
    });

    // NOTE: string icon ids resolve custom icons through the loaded database
    // meta (FileService) and are exercised by the database UI flows instead.
  });
}
