import { KdbxContext, KdbxEntry } from "kdbxweb";
import { KdbxBaseTransfer } from "./KdbxBaseTransfer";
import { KdbxBinaryStream } from "./KdbxBinaryStream";


export class KdbxEntryTransfer implements KdbxBaseTransfer<KdbxEntry> {

  write(stream: KdbxBinaryStream, obj: KdbxEntry): void {
    throw new Error("Method not implemented.");
  }


  read(stream: KdbxBinaryStream, ctx: KdbxContext): KdbxEntry {
    throw new Error("Method not implemented.");
  }
}