# DiskSenseInfo 0.1.3

- USB 裝置新增「USB 速率（系統回報）」。讀取新版 SPUSBHostDataType／舊版 SPUSBDataType，以 IOKit ancestry 的 locationID、VID、PID 核對實際所屬裝置，不抓父 Hub 或其他同型號裝置。
- 舊格式若回報 Up to，保留限定詞；速率不是實際磁碟測速值。SMART 中的 SATA 內部速率不覆蓋 USB 外部速率。
- SMART 無法讀取時顯示明確原因說明：目前 macOS USB 存取路徑、權限不足、一般失敗、尚未查詢或離線。USB 無法透傳診斷不表示 SSD 沒有 SMART 或故障。
- 改善未知欄位文案：SMART 未取得、裝置未回報、SSD 轉速不適用、Apple Fabric 沒有一般 PCIe 速率／通道資料。
- 重新連接後重新採集，不沿用離線健康判定與原因；連線速度也由新探索結果更新。
- 55 項測試通過。真實 TUF Gaming A2 已確認 USB 為 10 Gb/s；SMART 回報 Operation not supported by device，顯示 current macOS access path limitation。

未新增 USB 晶片專用 passthrough backend，並未聲稱本版能讀取此外接盒的 SMART。
