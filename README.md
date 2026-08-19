# Pd290-Win11

讓舊款 **Pd290 58 mm 熱感式印表機**在 Windows 11 x64 上正常列印的相容方案。

此版本已通過實機列印測試，適用於使用下列 USB 控制器的 Pd290：

```text
USB\VID_067B&PID_2305
```

安裝完成後，Windows 中的印表機與驅動名稱都是 `Pd290-Win11`。

## 最簡單的安裝方式

### 安裝前準備

1. 確認電腦是 **Windows 11 x64**。
2. 使用具有系統管理員權限的帳號。
3. 開啟 Pd290 電源，並使用 USB-B 對 USB-A 線接上電腦。
4. 到「設定 → 藍牙與裝置 → 印表機與掃描器」，確認 **Windows 受保護列印模式**沒有啟用。
5. 請先完整解壓縮套件，不要直接在 ZIP 裡執行安裝程式。

### 方法一：使用已整理好的安裝套件（推薦）

1. 下載本儲存庫最外層的 [`Pd290-Win11-working.zip`](./Pd290-Win11-working.zip)。
2. 將 ZIP 完整解壓縮。
3. 開啟解壓縮後的 `Pd290-Win11` 資料夾。
4. 按兩下 `Install-Pd290.cmd`。
5. Windows 詢問系統管理員權限時，選擇「是」。
6. 等待命令視窗顯示：

   ```text
   Installation completed
   ```

### 方法二：下載完整儲存庫

1. 在 GitHub 頁面按下 `Code` → `Download ZIP`。
2. 將下載的 ZIP 完整解壓縮。
3. 進入 `Win11-Pd290` 資料夾。
4. 按兩下 `Install-Pd290.cmd`，並允許系統管理員權限。

如果批次檔被 Windows 安全性設定阻擋，可以在 `Win11-Pd290` 資料夾內以系統管理員身分開啟 Windows PowerShell，執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Pd290-New-Win11.ps1 -ConfirmAllChanges -SetDefaultPrinter
```

## 安裝後測試

1. 關閉安裝時使用的系統管理員視窗。
2. 以平常使用的帳號開啟「設定 → 藍牙與裝置 → 印表機與掃描器」。
3. 選擇 `Pd290-Win11`。
4. 按下「列印測試頁」。

正常安裝後應顯示：

| 項目 | 正常狀態 |
|---|---|
| 印表機名稱 | `Pd290-Win11` |
| 驅動版本 | `2.0.0.2` |
| 印表機連接埠 | `C:\ProgramData\PU290Relay\spool\PU290.prn` |
| Relay 服務 | `PU290WinUsbRelay`，狀態為 `Running` |
| PL2305 裝置名稱 | `IEEE-1284 Controller` |

## 請勿更改的設定

- 不要另外安裝舊版 `2.0.0.0` 驅動。
- 不要將 `Pd290-Win11` 的連接埠改成 `USB001`、`USB002` 等 USB 連接埠。
- 不要單獨重新命名 `PU290Relay` 或 `PU290WinUsbRelay`；它們是服務與暫存路徑使用的內部名稱。

上述變更會繞過 Windows 11 專用的列印轉送服務，可能讓工作再次卡住或顯示列印錯誤。

## 運作原理

```mermaid
flowchart LR
    A[Windows 應用程式] --> B[Pd290-Win11 驅動]
    B --> C[產生印表機可讀的 RAW 資料]
    C --> D[本機暫存檔]
    D --> E[PU290WinUsbRelay 服務]
    E --> F[WinUSB]
    F --> G[Pd290 印表機]
```

舊 Pd290 在 Windows 11 上透過 Microsoft `usbprint.sys` 傳送資料時會失敗。本專案保留 Windows Unidrv 負責產生正確列印資料，再由本機 Relay 服務透過 WinUSB 將資料送入 PL2305 的 Bulk OUT endpoint。

WinUSB INF 只匹配 `USB\VID_067B&PID_2305`。其他 VID/PID 不同的 USB 印表機不會受到影響；但若另一台設備也使用完全相同的 PL2305 硬體 ID，它也可能套用相同綁定。

## 發生問題時

請先檢查：

1. Pd290 電源及 USB 線是否正常連接。
2. 印表機佇列中是否有卡住的舊工作。
3. `PU290WinUsbRelay` 服務是否為 `Running`。
4. 印表機連接埠是否仍是 `C:\ProgramData\PU290Relay\spool\PU290.prn`。
5. 裝置管理員中的 PL2305 是否顯示為 `IEEE-1284 Controller`。

Relay 執行紀錄位於：

```text
C:\ProgramData\PU290Relay\relay.log
```

若 WinUSB 傳輸失敗，未送出的工作會保存在：

```text
C:\ProgramData\PU290Relay\spool\PU290-failed-日期時間.prn
```

## 完整還原

若要移除 Relay、恢復 Microsoft `USB Printing Support` 並移除測試憑證，請在 `Win11-Pd290` 資料夾中以系統管理員身分執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Pd290Relay\Restore-All.ps1 -ConfirmRestoreAll
```

完成後拔除 USB、關閉並重新開啟 Pd290 電源，再接回 USB。

## 安全性與簽章

本專案使用 `CN=Pd290-Win11 Driver Test` 自簽測試憑證簽署兩個驅動 CAT。安裝程式會將公開憑證加入本機電腦的「受信任的根憑證授權單位」與「受信任的發行者」。儲存庫不包含私密金鑰。

目前測試憑證有效期限至 **2027-07-16**。到期後若要在新的電腦上安裝，必須重新簽署套件；不能只修改系統日期。

## 專案內容

| 路徑 | 用途 |
|---|---|
| `Pd290-Win11-working.zip` | 可直接解壓縮安裝的完整套件 |
| `Win11-Pd290/Printer-Driver` | Pd290-Win11 Unidrv 驅動、GPD、資源 DLL 與 CAT |
| `Win11-Pd290/WinUSB-Relay` | PL2305 WinUSB 綁定、憑證、測試及還原工具 |
| `Win11-Pd290/Pd290Relay` | Windows 列印轉送服務、原始碼與安裝腳本 |
| `Win11-Pd290/NEW-PC-INSTALL.zh-TW.md` | 更詳細的新電腦安裝說明 |
| `Pd290-win10.prn`、`Pd290-win11.prn` | 開發及 RAW 傳輸測試樣本 |
