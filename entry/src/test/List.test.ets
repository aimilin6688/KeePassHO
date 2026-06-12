import FilenameUtilsTest from './FilenameUtils.test';
import LocalUnitTest from './LocalUnitTest.test';
import s3MultipartTest from './storage/s3/S3ClientMultipartTest';
import s3StorageIntegrationTest from './storage/s3/S3StorageIntegrationTest';


export default function testsuite() {
  LocalUnitTest();
  FilenameUtilsTest();
  s3MultipartTest();
  s3StorageIntegrationTest();
}