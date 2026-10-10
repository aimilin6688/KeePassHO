import { describe, expect, it } from '@ohos/hypium';
import { LoadMessage, MessageType, toErrorMessage } from '../../../../main/ets/workers/WorkerParam';
import { DatabaseSave } from '../../../../main/ets/workers/DatabaseSave';
import { SaveDatabaseCallback } from '../../../../main/ets/workers/callback/SaveDatabaseCallback';

/**
 * 保存错误明细展示链路单元测试。
 *
 * 覆盖：LoadMessage.detail 字段（三参构造 / 两参兼容）、toErrorMessage 明细透传、
 * DatabaseSave.postErrorMessage 前缀+明细拼接（同步路径错误提示展示详细错误，
 * 如"文件损坏: bad argon2 version"）。
 */
export default function SaveErrorDetailTest() {
  describe('SaveErrorDetailTest', () => {
    /**
     * toErrorMessage 不带明细：detail 保持 undefined
     */
    it('toErrorMessage without detail keeps detail undefined', 0, () => {
      const message = toErrorMessage('save_detail_prefix');
      expect(message.type).assertEqual(MessageType.ERROR);
      expect(message.message).assertEqual('save_detail_prefix');
      expect(message.detail === undefined).assertTrue();
    });

    /**
     * toErrorMessage 携带明细：detail 原样透传
     */
    it('toErrorMessage with detail carries detail', 0, () => {
      const message = toErrorMessage('save_detail_prefix', 'bad argon2 version');
      expect(message.type).assertEqual(MessageType.ERROR);
      expect(message.message).assertEqual('save_detail_prefix');
      expect(message.detail).assertEqual('bad argon2 version');
    });

    /**
     * LoadMessage 两参构造（旧调用方兼容）：detail 保持 undefined
     */
    it('LoadMessage two-arg constructor keeps detail undefined', 0, () => {
      const message = new LoadMessage(MessageType.ERROR, 'legacy_error');
      expect(message.type).assertEqual(MessageType.ERROR);
      expect(message.message).assertEqual('legacy_error');
      expect(message.detail === undefined).assertTrue();
    });

    /**
     * LoadMessage 三参构造：detail 正确赋值
     */
    it('LoadMessage three-arg constructor sets detail', 0, () => {
      const message = new LoadMessage(MessageType.ERROR, 'save_detail_prefix', 'detail text');
      expect(message.detail).assertEqual('detail text');
    });

    /**
     * postErrorMessage 拼接前缀与明细（同步路径详细错误展示）
     */
    it('postErrorMessage composes prefix and detail', 0, () => {
      const captured: string[] = [];
      const callback: SaveDatabaseCallback = {
        onError: (message: string): void => {
          captured.push(message);
        }
      };
      new DatabaseSave(callback).postErrorMessage('save_detail_prefix', 'bad argon2 version');
      expect(captured.length).assertEqual(1);
      expect(captured[0]).assertEqual('save_detail_prefix: bad argon2 version');
    });

    /**
     * postErrorMessage 无明细：仅展示前缀
     */
    it('postErrorMessage without detail passes prefix only', 0, () => {
      const captured: string[] = [];
      const callback: SaveDatabaseCallback = {
        onError: (message: string): void => {
          captured.push(message);
        }
      };
      new DatabaseSave(callback).postErrorMessage('save_detail_prefix_only');
      expect(captured.length).assertEqual(1);
      expect(captured[0]).assertEqual('save_detail_prefix_only');
    });
  });
}
