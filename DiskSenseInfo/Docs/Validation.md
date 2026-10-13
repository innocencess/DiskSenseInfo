# 驗證結果與限制

日期：2026-10-13，Asia/Taipei。環境：Apple Silicon、macOS Darwin 27.0.0、Swift 6.4、Command Line Tools，沒有完整 Xcode。

## 已實作並驗證

- 使用真實採集資料在 App 自己的 NSHostingView 離屏渲染總覽、SMART、歷史、診斷、設定、深色與英文畫面並視覺檢查；預覽 PNG 存於 Docs。這不是整台電腦的螢幕錄影，也不取代真人操作與 VoiceOver 驗證。
- SwiftUI App 使用 swiftc 實際編譯、連結並啟動；Universal Mach-O 包含 arm64 / x86_64。兩個架構分別啟動並維持執行，x86_64 是在 Apple Silicon 的 Rosetta 環境測試，不能代表 Intel 真機相容性。
- 隨附 smartctl 7.5 為 Universal；僅動態連結 macOS 系統 framework / libc++ / libSystem，不需要 Homebrew。
- App 與內嵌執行檔 ad-hoc 簽署，`codesign --verify --deep --strict` 通過。
- DMG 建立成功、hdiutil checksum 驗證通過。
- Xcode project.pbxproj 與 Info.plist 通過 plutil 語法驗證。
- 本機真实 APPLE SSD AP2048Z（內建，17 個指標）與 CT2000X8SSD8（外接 PCIe，18 個指標）讀取成功，overall health 均 normal。此結果只代表採样當時裝置回報。
- Apple SSD error information log page 失敗仍保留可讀 NVMe health log；外接 SSD 回傳 error information 與 self-test log。沒有執行硬體自我測試。
- 本機 discovery 只列出 2 顆實體磁碟，沒有把 disk1/2/3 的 APFS 合成容器、磁碟映像與卷宗誤認成更多實體磁碟。內建建立 16 個分割區／APFS 卷宗對應、外接建立 1 個卷宗對應。
- 去識別化真實報告：[LiveValidation-redacted.json](LiveValidation-redacted.json)。沒有使用 fixture 當正式資料。
- `test.sh` 55 項測試通過，詳見 [TestResults.txt](TestResults.txt)。

測試涵蓋：NVMe 512000 bytes 單位、超 UInt64 字串計數、不截斷 hex、缺少 overall 不誤判正常、critical warning／spare／ATA normalized 門檻、pending sectors、未知廠商 wear 不猜測、permission denial、部分 log 錯誤、壞 JSON、APFS store prefix 邊界、完整匯出去識別化、CSV 公式注入、通知冷卻／持久化、history roundtrip／retention／壞檔、命令逾時／取消／literal arguments、重編號／拔除／新裝置重用 node、sleep/wake polling、外接 HDD 省電與手動更新、非有限數、ATA test capability／離線／NVMe backend／command allowlist。

## 已實作但未完整驗證

- Disk Arbitration 真實熱插拔與 NSWorkspace sleep/wake：回呼已連接；狀態與策略 fixture 通過，未為測試拔除使用者磁碟或使整台 Mac 睡眠。
- UNUserNotificationCenter：通知 API、條件增量與冷卻已實作；未製造高溫或故障，未擅自啟用使用者的系統通知。
- SMAppService 登入啟動：編譯及 API 整合完成，未修改使用者登入項目或重啟測試。
- ATA self-test：只在明確 capability 支援時呈現確認操作，測試白名單與 identity preflight 已實作；無 SATA 裝置實測，也未送出狀態變更命令。
- SATA／USB／RAID／多 physical stores Fusion：解析與映射部分有 fixture，沒有對應完整硬體測試。
- 完整 Xcode scheme build：此環境無 Xcode，僅驗證 project 結構；本機產物由 build.sh 建置。
- 繁中／英文主要 UI、淺深色與 SwiftUI accessibility 元件已實作，離屏預覽已檢查；未完成 VoiceOver 人工操作與所有 OS 的版面測試。底層 SMART 與診斷內容保留英文。
- 螢幕 UI 互動檢查受目前 Computer Use 的 Accessibility / Screen Recording 尚未授權影響，不能宣稱完成螢幕操作測試。

## 受平台或硬體限制／尚未實作

- Darwin smartmontools 7.5 NVMe backend 只傳 identify/get-log-page，不能執行 NVMe Device Self-test，即使裝置能力中包含 self_test。
- AAM 控制不可用；APM 只有部分 ATA driver 支援、可能需要管理員；本版未提供相關修改及自動套用。
- USB SMART passthrough 依 bridge/driver，不保證可取得；未附帶舊 kernel driver，不要求關閉 SIP。
- RAID 成員若 OS 不暴露，無 controller-specific backend。
- 部分 Apple SSD log page 由系統拒絕；未知資料顯示限制，不猜健康。
- ATA 廠商專屬壽命／讀寫計數對照、Email 通知、外部程式觸發、自動更新服務、特權 helper 尚未實作。
- macOS 13–26 與 Intel 真機仍需測試。SDK 的 x86_64 link 發出 compatibility packs 缺 arch 警告，但 universal link 成功且 x86_64 startup 通过；較舊 OS runtime 仍需驗證。
- 未具備 Developer ID 憑證，沒有正式簽章或 Apple 公證。

## 後續工作優先順序

1. 真實 SATA、常見 USB 外接盒、Intel、macOS 13 起的測試矩陣。
2. 使用者授權後的通知、登入啟動、睡眠與熱插拔、VoiceOver／深淺色人工驗證。
3. 需要時新增簽章 XPC helper；以 SMAppService 管理、限定可用操作、驗證 client code signature，不執行任意命令。
4. 正式簽章、公證、安裝驗證，並改善歷史大型資料的儲存效率。
5. 經證據確認的 ATA vendor wear map、Email notification 與安全更新機制。

## 0.1.3 USB 補充驗證

前述兩顆 NVMe 的實機結果為初版採样。此版本目前連接的是 APPLE SSD AP2048Z 與 USB TUF Gaming A2。真實採集確認 Gaming A2 的 USB 系統回報速率為 10 Gb/s，SMART access = usbUnavailable，原始錯誤 Operation not supported by device。介面明確標示当前 macOS USB 診斷存取路徑限制，沒有判定 SSD 故障或硬體不支援 SMART。最新 LiveValidation-redacted.json 已反映目前裝置。

55 項測試與真實 USBPreview.png 離屏視覺檢查完成。外接盒在 Windows 支援 SMART 是使用者回報，沒有替使用者執行 Windows 驗證；本版仍未提供使此外接盒在 macOS 可讀 SMART 的新後端。

## 0.1.4 改名與圖示驗證

App、執行檔、Xcode product/scheme、通知與匯出檔名改為 DiskSenseInfo。C 款圖示由內建 imagegen 生成，以 AppKit 保留透明度轉成標準 iconset，iconutil 打包 icns；源 PNG 與轉換腳本隨附。bundle identifier 與舊 Application Support/DiskPulse 資料路徑保留，程式沒有搬移／刪除既有資料。55 項測試再次通過。
