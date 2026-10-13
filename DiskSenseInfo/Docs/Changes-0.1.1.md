# DiskSenseInfo 0.1.1

修正製造商與傳輸版本未顯示的問題。

- NVMe PCI Vendor ID 對照 Apple Inc. (0x106B) 與 Micron/Crucial Technology (0xC0A9)。沒有 IOKit Vendor Name 時，欄位改為「廠商（PCI 識別）」，不把控制器廠商冒充 SSD 零售品牌；其他識別碼保留原始數值。
- NVMe / SATA / ATA 協定版本與連線速率分開顯示。保留 Apple 真實回報 `<1.2`，不強行改成精確版本。
- 系統報告 SPNVMeDataType 的 linkspeed / linkwidth 經装置名稱、型號及可取得序號核對；SMART 序號不一致時丟棄連線資訊。
- 外接 SSD 的 OS 回報連線為 8.0 GT/s、x4；這是 PCIe 連線參數，不能視為實際檔案傳輸測速結果，也不能視為整個外接盒端到端速率。
- 內建 Apple SSD 未提供 link rate/width，繼續顯示無法取得。
- 48 項測試通過；新增 PCI ID、未知識別碼、NVMe legacy version、SATA version/speed 分離及系統 profile parser 測試。

識別碼來源：[pciutils PCI ID repository](https://github.com/pciutils/pciids/blob/master/pci.ids)。只收錄核對過的兩個事實對照，App 不需要連線查詢。
