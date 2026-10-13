# 功能對照與硬體相容性

調查日期：2026-10-13（Asia/Taipei）。對標官方文件的功能類別與原始碼；Windows 專用整合不視為 macOS 可原封移植的能力。以下是實作與限制對照，並非完整相容保證。

分類：D＝可直接取得／實作；P＝可能需要權限或額外 driver/helper；H＝取決裝置與橋接器；U＝本後端無法可靠提供；N＝此版本尚未實作。

| CrystalDiskInfo 功能類別 | macOS 來源／策略 | 分類 | DiskSenseInfo 現況與限制 |
|---|---|---|---|
| 實體磁碟列表／自動偵測／重新掃描 | diskutil physical、Disk Arbitration | D | 已實作，不列出磁碟映像或合成 APFS 容器 |
| 型號／序號／韌體／容量 | diskutil、IOKit、smartctl identify | D/H | 已實作，缺少資料明確顯示 |
| 介面／傳输版本與速度／轉速 | IOKit、SATA interface_speed、rotation_rate | H | 已實作解析；NVMe 協定版本由 smartctl 取得，PCIe link rate / lanes 由 system_profiler 取得；未回報時留空 |
| 製造商／標準與支援功能 | IOKit、smartctl protocol/capability objects | H | 可取得內容呈現；不以型號字串猜製造商；無 Vendor Name 時另顯示 PCI 識別廠商，不當成零售品牌 |
| SMART 支援／啟用／健康總評 | diskutil overall、smartctl smart_status | H/P | 已實作；不自動啟用 SMART 或修改裝置 |
| 溫度／通電次數／通電時間 | SMART 標準欄位 | H | 已實作，ATA 非標準 raw 通電單位不猜測 |
| SSD 健康／剩餘壽命 | NVMe percentage_used | H | 呈現 NVMe 與標準 ATA Device Statistics 耗損；ATA 廠商專用 wear map 尚未實作 |
| Host Reads／Writes | NVMe Data Units、ATA Device Statistics | H | 標準換算；未知 ATA 廠商 raw 不當成 bytes |
| SATA SMART 表格與門檻 | smartctl ata_smart_attributes | H/P | ID/name/current/worst/threshold/raw/status；表格 fixture 驗證 |
| NVMe SMART health log | smartctl Darwin IOKit SMART interface | H/P | 本機兩顆裝置可讀標準欄位 |
| 溫度感測器 | NVMe temperature_sensors | H | 可取得時列出 |
| 重新配置／待處理／不可修正／CRC | ATA 5/197/198/199 | H | 門檻與計數提醒；須檢視廠商定義 |
| 健康門檻自訂 | HealthEngine、設定 | D | 溫度、耗損、異常計數與增量 |
| 十進位／十六進位 raw | 原始字串、UInt64 安全轉換 | D | 超大計數不截斷；保留十進位 |
| 自動更新／手動更新／省電策略 | Timer、PollingPolicy | D/H | 內外接分開間隔，外接 HDD/未知類型預設略過自動 SMART |
| 歷史曲線 | 本機 JSON、Swift Charts | D | 小時、天、週、月，溫度／耗損／讀寫／媒體錯誤 |
| 常駐／登入啟動／狀態區圖示 | MenuBarExtra、SMAppService | D | macOS 13+，登入項目需系統核准 |
| 溫度與健康提醒／音效 | UNUserNotificationCenter、default sound | D | 系統通知授權由使用者啟用；冷卻持久化 |
| Email 通知／外部程式觸發 | 需 SMTP/安全憑證與獨立配置 | N | 未實作；本版只提供 macOS 系統通知與音效 |
| 序號隱藏／複製或儲存報告 | 隱私設定、Exporter | D | JSON/CSV/txt，raw 展開另需明確動作 |
| 錯誤／自我測試紀錄 | ATA/NVMe log pages | H | 可讀頁顯示；Apple SSD 部分頁系統拒絕 |
| 自我測試啟動／中止 | ATA SMARTImmediateOffline | H/P | 僅 ATA 明確支持時顯示且要求確認，硬體尚未驗證 |
| NVMe 自我測試啟動 | Darwin backend 無相應 opcode | U | 即使裝置宣告支持，也不提供操作按鈕 |
| AAM 噪音管理 | Darwin 無對應可用 SET FEATURES 分支 | U | 不提供假控制項 |
| APM 省電設定／自動套用 | 部分 ATA IOKit APM Level，可能需管理員 | P/H/N | 未提供。需要簽章 helper 和支援硬體驗證；不推廣關閉 SIP |
| USB／IEEE1394 bridge 相容 | 驅動與 SMART passthrough 決定 | H/P | 基本裝置列表可讀；不能承諾 CrystalDiskInfo Windows bridge coverage |
| Intel RAID / CSMI / AMD RAID / VROC | Windows 驅動與控制器 backend | U/H | 沒有 Windows 命令的直接等價；OS 可見實體媒體才可監控 |
| 主題／多語言／高 DPI | SwiftUI、系統 appearance | D | 淺深色、繁中／英文 UI；低階診斷與 SMART 名稱保留英文 |
| 工作列／Windows gadget／WMI／裝置管理員 | Windows 專用 | U | macOS 用選單列與卷宗列表；不提供 Windows 整合 |
| 自動版本更新／廠商 wear map 更新 | 需安全更新管道／資料治理 | N | 本版離線使用，固定隨附資料庫 |

## 硬體矩陣

| 裝置／路徑 | 基本資訊 | 詳細 SMART | 本次驗證 |
|---|---|---|---|
| Apple Silicon APPLE SSD AP2048Z / Apple Fabric | D | H：NVMe health；部分 log U | 已讀取 17 項正規化指標，錯誤頁拒絕可見 |
| CT2000X8SSD8 / OS 回報 PCI-Express，外接 | D | H：NVMe health + error/self-test log | 已讀取 18 項；不推測外接盒實際晶片或拓樸 |
| Intel Mac 內建 SATA HDD/SSD | D/H | H/P：ATA IOKit SMART | 尚未實測，parser fixture 通過 |
| Intel Mac PCIe NVMe | D/H | H/P：NVMe IOKit SMART | 尚未實測，包含 x86_64 binary |
| Thunderbolt 暴露為 PCIe NVMe | D/H | H：取決控制器與 driver | 目前外接裝置呈 PCIe 可讀；其他盒子未驗證 |
| USB SATA / USB NVMe | D | H/P：橋接 passthrough 常受限 | TUF Gaming A2 USB 10 Gb/s 基本資訊已驗證；當前後端無法取得其 SMART，不附帶舊 SAT kernel driver |
| RAID 邏輯磁碟 | H | U/H：控制器後面實體成員可能不暴露 | 尚未實測；無 controller-specific RAID backend |
| APFS/Fusion 多 physical stores | D：對應每個 store | H：各底層實體媒體 | 映射規則已實作，多 store 硬體尚未驗證 |
| 磁碟映像／APFS 合成容器 | 不列為實體磁碟 | 不適用 | 本機列表排除成功 |

`SMART Verified` 表示裝置整體評估通過，並非完整的壽命預測。讀不到資料顯示未知／診斷原因，沒有補入 fixture 或 100% 健康。

## 來源

- [CrystalDiskInfo 官方功能](https://crystalmark.info/en/software/CrystalDiskInfo/)
- [官方一般資訊欄位](https://crystalmark.info/en/software/crystaldiskinfo/crystaldiskinfo-general-information/)
- [官方進階功能](https://crystalmark.info/en/software/crystaldiskinfo/crystaldiskinfo-advanced-features/)
- [CDI AtaSmart.cpp](https://github.com/hiyohiyo/CrystalDiskInfo/blob/master/AtaSmart.cpp)，查閱 `CheckDiskStatus` 與 Windows storage/USB/RAID command paths；未複製其程式。
- [smartctl manual](https://github.com/smartmontools/smartmontools/blob/main/src/smartctl.8.in)，Darwin 章節及 standby 行為；本次以隨附 7.5 原始碼核對實際後端。
- [Apple Disk Arbitration](https://developer.apple.com/library/archive/documentation/DriversKernelHardware/Conceptual/DiskArbitrationProgGuide/Introduction/Introduction.html)

0.1.3：USB 速度由 SPUSBHostDataType／舊版 SPUSBDataType 回報，按 IOKit ancestor VID/PID/location 匹配，保留系統報告的 Up to 限定詞；不當成磁碟測速值。USB SMART access error 不再顯示為硬體本身不支援。
