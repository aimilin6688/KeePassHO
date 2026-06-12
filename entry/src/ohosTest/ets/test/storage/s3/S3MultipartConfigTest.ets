import { describe, it, expect } from '@ohos/hypium';
import { S3MultipartConfig } from '../../../../../main/ets/storage/s3/S3Config';

export default function s3MultipartConfigTest() {
  describe('S3MultipartConfig', () => {

    it('should_have_correct_min_part_size', () => {
      expect(S3MultipartConfig.MIN_PART_SIZE).assertEqual(5 * 1024 * 1024);
    });

    it('should_have_correct_recommended_part_size', () => {
      expect(S3MultipartConfig.RECOMMENDED_PART_SIZE).assertEqual(8 * 1024 * 1024);
    });

    it('should_have_correct_multipart_threshold', () => {
      expect(S3MultipartConfig.MULTIPART_THRESHOLD).assertEqual(5 * 1024 * 1024);
    });

    it('should_have_correct_max_retry_count', () => {
      expect(S3MultipartConfig.MAX_RETRY_COUNT).assertEqual(3);
    });

    it('should_recommended_part_size_be_larger_than_min', () => {
      expect(S3MultipartConfig.RECOMMENDED_PART_SIZE)
        .assertLarger(S3MultipartConfig.MIN_PART_SIZE);
    });
  });
}
