# bindSheet 双向绑定问题解决方案

## 问题描述

在使用 `bindSheet` 实现底部弹框时，发现需要点击两次才能弹出弹框。第一次点击没有反应，第二次点击才能正常显示。

## 问题原因

当使用 `bindSheet($$this.isSheetShow, ...)` 双向绑定时，如果在 `onDisappear` 回调中重置状态，会导致状态冲突：

```typescript
// ❌ 错误做法
.bindSheet($$this.isSheetShow, this.DialogBuilder(), {
  onDisappear: () => {
    // 问题：当快速连续显示弹框时，前一个弹框的 onDisappear 
    // 可能在新弹框显示过程中被触发，导致状态被重置
    this.currentDialogType = DialogType.NONE;
    this.isSheetShow = false;
  }
})
```

**触发流程**：
1. 用户点击显示弹框A
2. 弹框A显示动画开始
3. 用户关闭弹框A，消失动画开始
4. 用户立即点击显示弹框B
5. 弹框B开始显示（isSheetShow = true）
6. 弹框A的消失动画完成，触发 onDisappear
7. onDisappear 将 isSheetShow 重置为 false
8. 弹框B立即被关闭

## 解决方案

### 核心原则

1. **不要在 `onDisappear` 中重置状态**：避免状态冲突
2. **使用 `setTimeout` 延迟设置**：确保状态更新顺序正确
3. **在主动关闭时重置状态**：而不是在回调中被动重置

### 代码示例

```typescript
@Component
struct SettingDatabasePage {
  @State currentDialogType: DialogType = DialogType.NONE;
  @State isSheetShow: boolean = false;

  private showDialog(type: DialogType) {
    // 先设置类型
    this.currentDialogType = type;
    // 延迟设置 isSheetShow，确保状态更新顺序正确
    setTimeout(() => {
      this.isSheetShow = true;
    }, 50);
  }

  private closeDialog() {
    this.isSheetShow = false;
    // 延迟重置类型，确保弹框关闭动画完成
    setTimeout(() => {
      this.currentDialogType = DialogType.NONE;
    }, 100);
  }

  build() {
    NavDestination() {
      SettingDatabaseContent({
        onShowDialog: (type: DialogType): void => this.showDialog(type)
      })
    }
    .bindSheet($$this.isSheetShow, this.DialogBuilder(), {
      preferType: SheetType.BOTTOM,
      mode: SheetMode.OVERLAY,
      height: SheetSize.FIT_CONTENT,
      // ✅ 正确做法：不在 onDisappear 中重置状态
      onDisappear: () => {
        // 可以在这里添加日志，但不要重置状态
      }
    })
  }
}
```

### 子组件调用方式

使用回调函数方式，而不是 `@Link` 双向绑定：

```typescript
@Component
struct SettingDatabaseContent {
  // 使用回调函数
  onShowDialog?: (type: DialogType) => void;

  build() {
    List() {
      ListItem() {
        Row() {
          Text("设置数据库元数据")
        }
        .onClick(() => {
          // 直接调用回调
          if (this.onShowDialog) {
            this.onShowDialog(DialogType.META);
          }
        })
      }
    }
  }
}
```

## 避免的做法

### ❌ 使用 @Watch 和 @Link

```typescript
// ❌ 这种方式可能导致状态同步问题
@Component
struct SettingDatabasePage {
  @State @Watch('onDialogTypeChange') currentDialogType: DialogType = DialogType.NONE;
  @State isSheetShow: boolean = false;

  onDialogTypeChange() {
    if (this.currentDialogType !== DialogType.NONE) {
      this.isSheetShow = true;  // 可能不会立即生效
    }
  }
}

@Component
struct SettingDatabaseContent {
  @Link currentDialogType: DialogType;  // 子组件修改可能不会触发父组件的 @Watch
  
  private showDialog(type: DialogType) {
    this.currentDialogType = type;  // 可能需要点击两次
  }
}
```

### ❌ 在 onDisappear 中重置状态

```typescript
// ❌ 这会导致连续显示弹框时出现问题
.bindSheet($$this.isSheetShow, this.DialogBuilder(), {
  onDisappear: () => {
    this.currentDialogType = DialogType.NONE;
    this.isSheetShow = false;  // 这会关闭正在显示的新弹框
  }
})
```

## 总结

| 场景 | 推荐做法 | 避免做法 |
|------|---------|---------|
| 显示弹框 | 延迟设置 `isSheetShow` | 直接设置 |
| 关闭弹框 | 在主动关闭时重置状态 | 在 `onDisappear` 中重置 |
| 父子组件通信 | 使用回调函数 | 使用 `@Link` + `@Watch` |
| 状态管理 | 集中在父组件管理 | 分散在多个组件中 |

## 相关文档

- [HarmonyOS 官方文档 - bindSheet](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-sheet-page)
- [弹框与窗口拖拽能力调研报告](./弹框与窗口拖拽能力调研报告.md)
