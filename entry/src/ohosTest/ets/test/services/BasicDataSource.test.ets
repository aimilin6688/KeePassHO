import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { BasicDataSource } from '../../../../main/ets/services/beans/BasicDataSource';

class RecordingListener implements DataChangeListener {
  reloadCount: number = 0;
  addIndex: number = -1;
  changeIndex: number = -1;
  deleteIndex: number = -1;
  moveFrom: number = -1;
  moveTo: number = -1;
  datasetCount: number = 0;

  onDataReloaded(): void {
    this.reloadCount++;
  }
  onDataAdded(index: number): void {
    this.onDataAdd(index);
  }
  onDataAdd(index: number): void {
    this.addIndex = index;
  }
  onDataChange(index: number): void {
    this.changeIndex = index;
  }
  onDataChanged(index: number): void {
    this.onDataChange(index);
  }
  onDataDelete(index: number): void {
    this.deleteIndex = index;
  }
  onDataDeleted(index: number): void {
    this.onDataDelete(index);
  }
  onDataMove(from: number, to: number): void {
    this.moveFrom = from;
    this.moveTo = to;
  }
  onDataMoved(from: number, to: number): void {
    this.onDataMove(from, to);
  }
  onDatasetChange(operations: DataOperation[]): void {
    this.datasetCount++;
  }
}

export default function BasicDataSourceTest() {
  describe('BasicDataSource', () => {
    let ds: BasicDataSource<string>;

    beforeAll(() => {
    });

    beforeEach(() => {
      ds = new BasicDataSource<string>();
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    it('totalCount returns 0 for a fresh source', 0, () => {
      expect(ds.totalCount()).assertEqual(0);
    });

    it('getData returns undefined for out-of-range index on empty data', 0, () => {
      expect(ds.getData(0) === undefined).assertTrue();
    });

    it('registerDataChangeListener adds a listener (dedupe on repeat)', 0, () => {
      const l = new RecordingListener();
      ds.registerDataChangeListener(l);
      ds.registerDataChangeListener(l);
      ds.notifyDataReload();
      expect(l.reloadCount).assertEqual(1);
    });

    it('unregisterDataChangeListener removes the listener so it no longer fires', 0, () => {
      const l = new RecordingListener();
      ds.registerDataChangeListener(l);
      ds.notifyDataReload();
      expect(l.reloadCount).assertEqual(1);
      ds.unregisterDataChangeListener(l);
      ds.notifyDataReload();
      expect(l.reloadCount).assertEqual(1);
    });

    it('unregisterDataChangeListener for never-registered listener is a no-op', 0, () => {
      const l = new RecordingListener();
      let threw = false;
      try {
        ds.unregisterDataChangeListener(l);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('notifyDataReload fans out to all registered listeners', 0, () => {
      const a = new RecordingListener();
      const b = new RecordingListener();
      ds.registerDataChangeListener(a);
      ds.registerDataChangeListener(b);
      ds.notifyDataReload();
      expect(a.reloadCount).assertEqual(1);
      expect(b.reloadCount).assertEqual(1);
    });

    it('notifyDataAdd passes the index to listeners', 0, () => {
      const l = new RecordingListener();
      ds.registerDataChangeListener(l);
      ds.notifyDataAdd(3);
      expect(l.addIndex).assertEqual(3);
    });

    it('notifyDataChange passes the index to listeners', 0, () => {
      const l = new RecordingListener();
      ds.registerDataChangeListener(l);
      ds.notifyDataChange(7);
      expect(l.changeIndex).assertEqual(7);
    });

    it('notifyDataDelete passes the index to listeners', 0, () => {
      const l = new RecordingListener();
      ds.registerDataChangeListener(l);
      ds.notifyDataDelete(2);
      expect(l.deleteIndex).assertEqual(2);
    });

    it('notifyDataMove passes from and to to listeners', 0, () => {
      const l = new RecordingListener();
      ds.registerDataChangeListener(l);
      ds.notifyDataMove(1, 4);
      expect(l.moveFrom).assertEqual(1);
      expect(l.moveTo).assertEqual(4);
    });

    it('notifyDatasetChange forwards operations to listeners', 0, () => {
      const l = new RecordingListener();
      ds.registerDataChangeListener(l);
      const ops: DataOperation[] = [];
      ds.notifyDatasetChange(ops);
      expect(l.datasetCount).assertEqual(1);
    });

    it('notify* methods are safe when no listener registered', 0, () => {
      let threw = false;
      try {
        ds.notifyDataReload();
        ds.notifyDataAdd(0);
        ds.notifyDataChange(0);
        ds.notifyDataDelete(0);
        ds.notifyDataMove(0, 1);
        ds.notifyDatasetChange([]);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });
  });
}
