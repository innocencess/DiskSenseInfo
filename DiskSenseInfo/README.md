# DiskSenseInfo 0.1.4

原生 macOS 磁碟健康監控，Swift / SwiftUI，macOS 13 以上。

## 安裝與使用

1. 開啟 `dist/DiskSenseInfo.dmg`，將 DiskSenseInfo 拖入 Applications；或直接開啟 `dist/DiskSenseInfo.app`。
2. 左側選擇實體磁碟。總覽、SMART、歷史與診斷分頁顯示真實採集結果。
3. `⌘R` 手動更新；手動查詢可能喚醒外接硬碟。
4. `⌘,` 開啟設定，可設定語言、更新頻率、通知門檻、登入啟動與歷史保留。
5. 工具列可匯出 JSON、CSV、文字診斷報告。預設隱藏識別資料；若要匯出序號與原始內容，先在設定取消去識別化。
6. 關閉視窗後仍在選單列監控；選單列「結束」才會退出。

App 與 smartctl 均包含 arm64 / x86_64。最低版本依 Charts、MenuBarExtra、SMAppService 為 macOS 13；本次實機驗證為 Apple Silicon 上的 macOS 27，其他 OS 與 Intel 硬體尚未實測。

這是可執行的第一版，**不宣稱完整取代 CrystalDiskInfo，也不保證所有硬體可讀取 SMART**。詳見 [功能對照與相容性](Docs/Capabilities.md) 和 [驗證結果](Docs/Validation.md)。

## 建置

不需要 Homebrew、網路套件或完整 Xcode。需 Apple Command Line Tools：

```sh
./test.sh
./build.sh --dmg
```

完整 Xcode 使用者可開啟 `DiskSenseInfo.xcodeproj`，選擇 DiskSenseInfo scheme 建置。此環境沒有 Xcode，因此 `.xcodeproj` 結構已驗證、但未以 xcodebuild 實測；本機 App 使用 swiftc 編譯。Tests 是獨立的 async 測試執行檔，以 `test.sh` 執行，不是 XCTest target。

`Resources/smartctl` 已隨附通用執行檔。`Resources/smartmontools-7.5-source.tar.gz` 是對應完整上游來源，`Resources/drivedb.h` 是同版本資料庫。重建方法：

```sh
./rebuild-smartctl.sh
./build.sh --dmg
```

## 權限與資料

預設非沙盒、一般使用者權限，不安裝核心擴充、不修改 SIP、不執行 sudo。實機兩顆 SSD 均可在一般權限下讀取。特定裝置若拒絕 IOKit 存取，會顯示錯誤；目前未提供需要簽署與驗證的特權輔助程式，不能保證管理員權限可解決橋接器限制。完整磁碟存取不等於 SMART passthrough 權限。

通知與登入啟動僅在使用者於設定啟用時請求 macOS 授權。

設定、歷史與通知冷卻紀錄儲存在 `~/Library/Application Support/DiskPulse/`。歷史保存正規化指標，沒有序號或卷宗名稱；裝置識別使用 SHA-256。原始 SMART 與 diskutil 結果在記憶體中保留，需在診斷頁手動展開。資料不會上傳，也不會自動檢查更新。匯出時預設略去完整原始資料和可能包含識別資訊的診斷文字。

## 簽章與公證

本機產物以 ad-hoc 簽署，**未經 Developer ID 簽署或 Apple 公證**。直接散布到其他 Mac 時需正式簽章、公證；請勿以關閉 Gatekeeper 或 SIP 作為安裝步驟。

持有 Developer ID 時，先簽署內嵌 smartctl，再簽署 App，重新建立 DMG，再使用 `xcrun notarytool submit --wait` 與 `xcrun stapler staple`；團隊及憑證由散布者提供。參考 [Apple 公證文件](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

專案採 GPL-2.0-or-later，見 `LICENSE` 與 [第三方聲明](Docs/ThirdParty.md)。

## 真實資料介面預覽

[總覽](Docs/LivePreview.png) · [SMART](Docs/SMARTPreview.png) · [歷史](Docs/HistoryPreview.png) · [診斷](Docs/DiagnosticsPreview.png) · [深色](Docs/DarkPreview.png) · [英文](Docs/EnglishPreview.png) · [設定](Docs/SettingsPreview.png)

預覽由 App 本身的 NSHostingView 以真實磁碟資料離屏渲染，沒有使用模擬磁碟。

## 支持開發

側邊欄底部的「請我喝杯咖啡」按鈕，會以預設瀏覽器開啟 https://buymeacoffee.com/kkrlife。

0.1.4 USB 速度與 SMART 限制說明：[真實外接盒畫面](Docs/USBPreview.png)。

## 0.1.4 改名說明

DiskPulse 更名為 DiskSenseInfo，採用 C 款極簡薰衣草色磁碟圖示。為延續舊版設定、通知授權與歷史，bundle identifier 保留 app.diskpulse.monitor，本機資料仍使用 ~/Library/Application Support/DiskPulse/。升級前退出並移除舊 DiskPulse.app，再將 DiskSenseInfo.app 放入 Applications；資料目錄不要刪除。
