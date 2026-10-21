//! SFTP 文件元数据模型：Rust 核心层与 napi 绑定层共用的 `FileStat`。
//!
//! 字段语义与 ArkTS 侧 `index.d.ts` 的 `FileStat` 接口一致：
//! `mtime` 为 Unix 秒（ArkTS 侧再按需转毫秒）。

use russh_sftp::protocol::FileAttributes;

/// 远端文件/目录条目信息。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileStat {
    /// 文件名（不含路径；`sftp_stat` 时取自路径末段）
    pub name: String,
    /// 字节数
    pub size: u64,
    /// 修改时间（Unix 秒；未知为 0）
    pub mtime: u32,
    /// 是否目录
    pub is_dir: bool,
    /// POSIX 权限位（未知为 0）
    pub permissions: u32,
}

impl FileStat {
    /// 由 russh-sftp 的 `FileAttributes` 构造。
    pub fn from_attrs(name: impl Into<String>, attrs: &FileAttributes) -> Self {
        Self {
            name: name.into(),
            size: attrs.size.unwrap_or(0),
            mtime: attrs.mtime.unwrap_or(0),
            is_dir: attrs.is_dir(),
            permissions: attrs.permissions.unwrap_or(0),
        }
    }

    /// 从路径提取末段文件名（`/a/b.txt` → `b.txt`，`/` → `/`）。
    pub fn name_of_path(path: &str) -> String {
        let trimmed = path.trim_end_matches('/');
        if trimmed.is_empty() {
            return "/".to_string();
        }
        match trimmed.rsplit('/').next() {
            Some(seg) if !seg.is_empty() => seg.to_string(),
            _ => trimmed.to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_stat_from_attrs() {
        let mut attrs = FileAttributes::default();
        attrs.size = Some(1024);
        attrs.mtime = Some(1_700_000_000);
        attrs.permissions = Some(0o100644);
        let stat = FileStat::from_attrs("a.txt", &attrs);
        assert_eq!(stat.size, 1024);
        assert_eq!(stat.mtime, 1_700_000_000);
        assert!(!stat.is_dir);
        assert_eq!(stat.permissions, 0o100644);
    }

    #[test]
    fn file_stat_dir_flag() {
        let mut attrs = FileAttributes::default();
        attrs.set_dir(true);
        let stat = FileStat::from_attrs("dir", &attrs);
        assert!(stat.is_dir);
    }

    #[test]
    fn name_of_path() {
        assert_eq!(FileStat::name_of_path("/a/b.txt"), "b.txt");
        assert_eq!(FileStat::name_of_path("b.txt"), "b.txt");
        assert_eq!(FileStat::name_of_path("/a/b/"), "b");
        assert_eq!(FileStat::name_of_path("/"), "/");
        assert_eq!(FileStat::name_of_path(""), "/");
    }
}
