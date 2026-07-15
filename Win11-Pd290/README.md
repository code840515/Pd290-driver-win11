# Pd290-Win11

Pd290 58 mm 熱感式印表機在 Windows 11 x64 上的相容驅動、PL2305 WinUSB 綁定與列印轉送服務。

## 目前版本

- 印表機名稱：`Pd290-Win11`
- 驅動名稱：`Pd290-Win11`
- 驅動版本：`2.0.0.2`
- 支援裝置：`USB\VID_067B&PID_2305`
- 測試憑證：`CN=Pd290-Win11 Driver Test`
- 不需要停用 Secure Boot、核心隔離或驅動程式簽章強制

## 安裝

1. 完整解壓縮發佈套件。
2. 開啟印表機並接上 USB-B 對 USB-A 線。
3. 執行 `Install-Pd290.cmd`，允許系統管理員權限。
4. 在 Windows 設定中選擇 `Pd290-Win11` 列印測試頁。

詳細步驟請參閱 [NEW-PC-INSTALL.zh-TW.md](NEW-PC-INSTALL.zh-TW.md)。

## 專案內容

- `Printer-Driver/`：已簽署 Pd290 Unidrv 套件
- `WinUSB-Relay/`：PL2305 WinUSB INF、CAT、憑證與診斷工具
- `Pd290Relay/`：Windows 列印轉送服務原始碼與執行檔
- `resource/`：T58 資源 DLL 原始檔與建置腳本
- 根目錄：一鍵安裝、CAT 建置、套件驗證、RAW 與硬體診斷工具
- 歷史 `.log` 與裝置綁定快照：完整保留先前除錯過程

## 安全性

本專案使用自簽測試憑證簽署兩個驅動 CAT。安裝腳本會將公開憑證加入目標電腦的受信任根憑證與受信任發行者。儲存庫不包含私密金鑰；正式大量部署建議改用 Microsoft Hardware Program／正式程式碼簽章。