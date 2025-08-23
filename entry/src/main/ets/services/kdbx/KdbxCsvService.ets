import { Kdbx } from "kdbxweb";

export enum CsvTitle {
  Group = "Group",
  Title = "Title",
  Username = "Username",
  Password = "Password",
  URL = "URL",
  Notes = "Notes",
  TOTP = "TOTP",
  Icon = "Icon",
  Last_Modified = "Last Modified",
  Created = "Created"
}

export class KdbxCsvService {

  /**
   * 导出数据库到csv文件格式
   * @param database
   * @returns
   */
  public static async export(database:Kdbx): Promise<ArrayBuffer> {
  }
}