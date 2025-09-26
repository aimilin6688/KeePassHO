import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { WebDavClient, ResultInfo } from '../../../../main/ets/common/utils/WebDavClient';


export default function WebDavTest() {
  describe('WebDavTest', () => {
    let client = new WebDavClient({url: 'https://dav.jianguoyun.com/', username: 'aimilin@yeah.net', password: 'a77u9ewde6gyaqxg'});
    beforeEach(() => {
       client.connection();
    });
    afterAll(() => {
      client.close();
    });

    it('file_url_list', 0, async () => {
      await client.list('/dav/MyFiles/').then((response: ResultInfo) => {
        console.log("-------------->", JSON.stringify(response));
        client.close();
      });
    })

    it('file_exists', 0, async () => {
      await client.exists('/dav/MyFiles/').then((response: boolean) => {
        console.log("MyFiles: -------------->", response);
        client.close();
      });

      client.connection();
      await client.exists('/dav/MyFiles_2').then((response: boolean) => {
        console.log("MyFiles_2:-------------->", response);
        client.close();
      });
    })

    it('get_file', 0, async () => {
      await client.get('/dav/MyFiles/test-1.kdbx').then((response: ResultInfo) => {
        console.log("test-1.kdbx: -------------->", JSON.stringify(response));
        client.close();
      });
    })
  })
}