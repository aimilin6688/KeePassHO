import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { Client, FileInfo } from '@dove/webdav';
import { ByteUtils } from 'kdbxweb';

export default function WebDavTest() {
  describe('WebDavTest', () => {
    it('file_url_list', 0, async () => {
      let client = new Client('https://dav.jianguoyun.com/dav/', 'aimilin@yeah.net', 'a77u9ewde6gyaqxg');
      await client.connect().then(() => {
        console.log("--------------------------------------------:connect");
        client.list('').then((files: FileInfo[]) => {
          console.log("-------------->",JSON.stringify(files));
        }).catch((err: Error) => {
          console.log(err.message, err.stack);
        })
      }).catch((err: Error) => {
        console.log(err.message, err.stack);
      });


      console.log("--------------------------------------------: connect");
      client.list('').then((files: FileInfo[]) => {
        console.log("-------------->",JSON.stringify(files));
      }).catch((err: Error) => {
        console.log(err.message, err.stack);
      })

      client.get('/MyFiles/keepass.kdbx').then((result: ArrayBuffer | null) => {
        if(result == null){
          console.log("-------------->",result);
        }else{
          console.log("-------------->",ByteUtils.bytesToString(result));
        }
      }).catch((err: Error) => {
        console.log(err.message, err.stack);
      });
      client.close();
      console.log("--------------------------------------------:close");
    })
  })
}