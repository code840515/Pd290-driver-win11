# Pd290 PL2305 WinUSB Relay（實驗性）

此資料夾用於將 `USB\VID_067B&PID_2305` 暫時從 Microsoft `usbprint.inf` 改綁到內建 `winusb.sys`，藉此繞過 Win11 USB Printer Class 傳輸失敗。

## 重要警告

- 這是實驗性裝置綁定，不是正式發布的印表機驅動。
- 綁定 WinUSB 後，裝置管理員中的「USB Printing Support」會暫時消失。
- 原本使用 `USB00x` 的印表機佇列在還原前不能工作。
- `Restore-UsbPrint.ps1` 會移除本套件並讓 Windows 重新使用 `usbprint.inf`。
- 不要在沒有 `PL2305-WinUSB.cat` 或 catalog 簽章無效時安裝。

## 預定測試流程

1. 使用 WDK `Inf2Cat` 建立 catalog。
2. 使用僅供此測試的 Code Signing 憑證簽署 catalog。
3. 確認 `Restore-UsbPrint.ps1` 可解析且套件可被識別。
4. 以系統管理員 PowerShell 執行：

   ```powershell
   .\Install-WinUsbBinding.ps1 -ConfirmBindingChange
   ```

5. 重新插拔 USB 後執行 Bulk Endpoint 測試。

## 還原

以系統管理員 PowerShell 執行：

```powershell
.\Restore-UsbPrint.ps1 -ConfirmRestore
```

完成後拔除 USB、關閉並重開印表機，再插回 USB。裝置應恢復為 Microsoft `USB Printing Support`。
