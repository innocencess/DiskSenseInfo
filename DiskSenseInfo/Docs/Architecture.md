# 架構與開發里程碑

## 資料流程

`Disk Arbitration events → DiskDiscovery → DiskCollector → SmartParser → HealthEngine → AppModel → SwiftUI / HistoryStore / UNUserNotificationCenter`

- **DiskDiscovery**：固定路徑 `/usr/sbin/diskutil list -plist physical` 篩選實體磁碟。`list -plist` 建立分割區與 APFS physical stores / containers / volumes 對應；不把合成容器列為額外實體磁碟。IOKit 公開 API 讀取可取得的裝置識別與特性；system_profiler SPNVMeDataType JSON 提供以 BSD node、型號及可取得序號核對的 PCIe link rate / lanes。APFS 空間按共享容器顯示，不能累加各卷宗容量。
- **DiskCollector**：執行 App 隨附 smartctl 7.5，以 `-x -j -B <bundled database> /dev/diskN` 讀取。Process.executableURL 與 arguments 分開，不執行 shell 字串。部分 log page 錯誤不丟棄可讀健康頁。僅原始資料保留 diskutil 未穩定文件化的 device-specific SMART keys，介面不依赖它們。
- **CommandRunner**：非同步啟動、每 50ms 檢查結束／取消，逾時先終止再必要時 SIGKILL。輸出到權限 0600 的私有暫存檔，避免管線滿造成死鎖；完成清除。
- **SmartParser**：NVMe 採標準欄位，Data Unit = 512,000 bytes。大計數優先保留 `*_s` 字串，原始值無精度損失；圖表與摘要使用 Double，超大值可能近似。ATA normalized / worst / threshold / raw 各自呈現；不根據未知廠商 ID 猜耗損。標準 ATA Device Statistics 的 Logical Sectors 依 logical_block_size 換算讀寫量，page 7 / offset 8 取得標準耗損；忽略 invalid statistics。NVMe protocol version 與 negotiated link rate 分開呈現。無 Vendor Name 時顯示 PCI ID 對照的廠商；未知 ID 顯示原碼，不猜品牌。未提供的欄位留空。
- **HealthEngine**：overall pass 才建立正常基準；SMART fail、NVMe critical warning、備援低於門檻、ATA normalized threshold failure 判危險；溫度、耗損、常見磁區／CRC／媒體錯誤達設定門檻判注意。只有正常溫度不足以建立正常健康。累積錯誤與新增錯誤皆有通知策略。非正常關機計數本身不直接判壞。
- **AppModel / PollingPolicy / DiskTopology**：在主 actor 更新 UI，採集 await；磁碟事件去抖動、忙碌期間補做掃描；睡眠取消、喚醒重新掃描、拔除標離線並保留最後資料。序號優先，其次持久卷宗 UUID 組合做雜湊識別；缺少兩者時標示 session identity，不存歷史。格式化會改變 fallback UUID identity。
- **HistoryStore**：JSON 原子寫入、按保留天數修剪。損壞檔案移至 recovery copy 並呈現錯誤。高頻率／長保留期間資料量會增加，未實作 SQLite 分頁或歷史壓縮。
- **AlertGate**：依磁碟與條件 signature 冷卻，通知成功後保存狀態，重啟延續抑制。
- **Exporter**：JSON 包含採樣與磁碟、CSV 匯出指標序列、文字報告摘要。去識別化涵蓋序號、device node、volume 名稱／路徑、原始 payload、診斷文字與 history disk ID。CSV 避免公式注入。
- **DeviceOperationPolicy**：只有 ATA 裝置明確宣告自我測試支援才呈現 short / long / abort。固定指令白名單，使用者確認後重新核對 discovery identity 才送出。NVMe 的 Darwin 後端不支援 Device Self-test command，故停用。

## 散布選擇

本版採非沙盒直接散布。Disk Arbitration 可在 sandbox 接收事件，但裝置及 IOKit SMART 存取需另行评估；使用者選檔權限不能保證硬體 passthrough。Mac App Store 需要另外設計受限版本及審查，不把目前功能直接承諾可上架。

不需要提升權限即可驗證本機兩顆 SSD，故不預先安裝特權 daemon。遇到 permission denied 保留可診斷錯誤；未實作自動提權。後續若擴增 helper，需使用 SMAppService / XPC、限定 read-only request、驗證客戶端簽章與裝置身份，並在正式簽章環境實測。

## 里程碑及現況

1. 能力調查：官方功能文件、CDI AtaSmart.cpp 健康規則與 smartmontools Darwin 後端查核完成。
2. 實體磁碟採集／正規化：實機兩顆 NVMe SSD 驗證。
3. SwiftUI、歷史、設定、選單列、匯出、通知與登入 API：程式已完成，部分 OS 互動尚未驗證。
4. 測試／通用建置／DMG：依 Validation.md 記錄結果。
5. 正式散布：Developer ID、公證、跨 OS／Intel／SATA／USB／RAID 測試及特權 helper 仍待後續完成。

## 官方依據

- [Apple Disk Arbitration guide](https://developer.apple.com/library/archive/documentation/DriversKernelHardware/Conceptual/DiskArbitrationProgGuide/Introduction/Introduction.html)
- [Disk properties and IOKit](https://developer.apple.com/library/archive/documentation/DriversKernelHardware/Conceptual/DiskArbitrationProgGuide/ManipulatingDisks/ManipulatingDisks.html)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [smartctl manual source](https://github.com/smartmontools/smartmontools/blob/main/src/smartctl.8.in)
- bundled 7.5 source `os_darwin.cpp`: ATA_CHECK_POWER_MODE 不支援；ATA APM enabled level 經 IORegistry property；NVMe opcode 僅 identify/get-log-page。
