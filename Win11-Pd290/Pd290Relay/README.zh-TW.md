# Pd290 Windows 11 WinUSB 列印轉接服務

此方案用於 Pd290 搭配 PL2305（`USB\VID_067B&PID_2305`）在 Windows 11 無法透過 Microsoft `usbprint.sys` 列印的情況。

最終架構：Windows 內建 Local Port Monitor 將已轉譯的 RAW 資料寫到 `C:\ProgramData\PU290Relay\spool\PU290.prn`。`PU290WinUsbRelay` 服務確認檔案已關閉後，以獨佔方式讀取，透過 WinUSB Bulk OUT 寫入 PL2305，成功後刪除暫存檔。此方案不使用 TCP/IP，也不開放網路連接埠。

## 重要版本

列印驅動必須使用 `Printer-Driver` 內的 `2.0.0.2`：

- `DriverIsolation=0`
- 已使用 Pd290-Win11 測試憑證簽署
- Win11 事件會顯示 isolation mode 0

舊 `2.0.0.0` 曾設定 `DriverIsolation=2`，一般使用者的 EMF 工作會卡在 `Error, Printing, Retained`，請勿再安裝。

## 已驗證路徑

1. 一般使用者送出 Windows 測試頁。
2. Pd290-Win11/Unidrv 2.0.0.2 在 Spooler 內轉成 82,798 位元組 RAW 資料。
3. Local Port Monitor 寫入本機 spool 檔。
4. `PU290WinUsbRelay` 經 WinUSB Bulk OUT 傳給 PL2305。
5. 工作從佇列消失、暫存檔刪除，PrintService 事件 307 回報成功。

## 檔案

- `Pd290Relay.cs`：Windows 服務原始碼。
- `Pd290Relay.exe`：本機建置的 x64 服務。
- `Build-Relay.ps1`：重新建置服務。
- `Install-Relay.ps1`：安裝自動啟動服務、建立檔案 Local Port 並切換 Pd290 佇列。
- `Uninstall-Relay.ps1`：移除服務並恢復安裝前的印表機連接埠。
- `Restore-All.ps1`：完整移除服務、恢復 Microsoft `usbprint.inf` 並刪除測試憑證。

## 記錄與失敗檔案

服務記錄：`C:\ProgramData\PU290Relay\relay.log`

成功工作範例：`File job completed, bytes=82798`

若 WinUSB 寫入失敗，資料會保留在 `C:\ProgramData\PU290Relay\spool`，檔名為 `PU290-failed-日期時間.prn`。

## 還原

只移除轉接服務並恢復原連接埠：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-Relay.ps1 -ConfirmUninstall
```

完整恢復 Microsoft USB Printing Support 並移除測試憑證：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Restore-All.ps1 -ConfirmRestoreAll
```