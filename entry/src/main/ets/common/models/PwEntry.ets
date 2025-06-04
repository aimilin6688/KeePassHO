


// 密码项基础信息
export interface PwEntry {
  id: string;
  title: string;
  username?: string;
  password?: string;
  url?: string;
  notes?: string;
  createdAt: number;
  updatedAt: number;
  groupId?: string; // 所属组ID
}