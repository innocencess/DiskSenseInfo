# 授權與第三方來源

DiskSenseInfo 本身採 GNU GPL version 2 or later；完整授權見根目錄 LICENSE。無複製 CrystalDiskInfo 程式、圖像或品牌素材；僅研究功能與健康判定概念。

smartmontools 7.5：Bruce Allen、Christian Franke 及其貢獻者；GPL-2.0-or-later。隨附獨立 smartctl 執行檔、drivedb.h、COPYING 及完整對應原始碼 `Resources/smartmontools-7.5-source.tar.gz`。原始碼未修改，以 Apple clang/g++、universal flags 及 macOS 13 deployment target 建置；重建配置見 rebuild-smartctl.sh。smartctl 內嵌必要系統介面宣告，詳見同版各檔 copyright/SPDX 註記。

來源：[官方專案](https://www.smartmontools.org/)／[官方 7.5 release source](https://sourceforge.net/projects/smartmontools/files/smartmontools/7.5/smartmontools-7.5.tar.gz/download)。磁碟資料庫也包含其上游著作權聲明，不應去除。App 散布時持續附帶本頁、GPL 授權及完整對應來源；若修改 smartmontools，需交付對應修改版本的 source 與建置資料。

SwiftUI、Charts、AppKit、Foundation、CryptoKit、Disk Arbitration、IOKit、UserNotifications、ServiceManagement 是作業系統框架，未將 Apple framework 本體重新散布。App 圖示是由內建 imagegen 產生的 C 款原創極簡磁碟圖案，以 AppKit 轉換成 macOS 圖示尺寸並打包 icns。

正式外部散布前，另完成 Developer ID 簽章、公證與支援平台驗證；目前 ad-hoc signature 不表示 Apple 審核或公證。
