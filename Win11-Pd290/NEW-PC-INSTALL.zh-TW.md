# Pd290 在新 Windows 11 電腦的安裝方式

此套件是目前已在 Windows 11 實際列印成功的版本。它會安裝：

- Pd290-Win11 印表機驅動 2.0.0.2（Driver Isolation 關閉）
- PL2305 的 WinUSB 綁定驅動
- PU290WinUsbRelay 自動啟動服務
- `Pd290-Win11` 印表機佇列

## 安裝前

1. 適用 Windows 11 x64。
2. 把 ZIP 完整解壓縮，不要直接在 ZIP 裡執行檔案。
3. 開啟 Pd290 電源，使用 USB-B 對 USB-A 線接到電腦。
4. 使用具有系統管理員權限的帳號。

## 一鍵安裝

在解壓縮後的 `Pd290-Win11` 資料夾中，按兩下 `Install-Pd290.cmd`，在 Windows 詢問時允許系統管理員權限，等待畫面顯示 `Installation completed`。

如果批次檔被安全性設定攔截，請以滑鼠右鍵開啟「Windows PowerShell（系統管理員）」，切換到 `Pd290-Win11` 資料夾後執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Pd290-New-Win11.ps1 -ConfirmAllChanges -SetDefaultPrinter
```

安裝程式會明確匯入 `Pd290-Win11 Driver Test` 公開憑證到本機電腦的「受信任的根憑證授權單位」和「受信任的發行者」，讓 Windows 11 接受此套件的兩個目錄簽章。套件不包含私密金鑰。

## 安裝後測試

1. 關閉系統管理員 PowerShell。
2. 用平常登入的使用者開啟「設定 → 藍牙與裝置 → 印表機與掃描器」。
3. 選擇 `Pd290-Win11`。
4. 按「列印測試頁」。

正常狀態應為：

- 印表機連接埠：`C:\ProgramData\PU290Relay\spool\PU290.prn`
- 驅動版本：`2.0.0.2`
- 服務 `PU290WinUsbRelay`：`Running`
- 裝置管理員中的 PL2305：`IEEE-1284 Controller`

不要另外安裝舊版 2.0.0.0，也不要把正式印表機切回 `USB001` 或 `USB002`；那會繞過 Win11 專用轉送服務，再度出現卡住或列印錯誤。

## 完整還原

若要把本套件安裝的服務、佇列、WinUSB 綁定和測試憑證全部還原，請用系統管理員 PowerShell執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Pd290Relay\Restore-All.ps1 -ConfirmRestoreAll
```

目前測試憑證的有效期限到 2027-07-16。到期後若要在另一台新電腦安裝，必須重新簽署套件，不能只調整系統日期。