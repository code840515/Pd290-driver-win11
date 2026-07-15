# Pd290-Win11 Windows 11 x64 驅動

這是將舊版 Windows Server 2003 DDK 驅動整理成 Windows 11 可接受的 package-aware Unidrv 套件。保留原廠的 203 DPI、384 點列印寬度與印表機控制命令。

## 套件內容

- `Pd290.inf`：Windows 11 x64 安裝資訊，改用 Unidrv Core Driver dependency。
- `Pd290.gpd`：列印能力與控制命令；已修正自訂紙張最小尺寸的語法錯誤。
- `T58.dll`：原廠 x64 純資源 DLL，沒有程式進入點或 API imports，只提供介面文字。
- `Build-Catalog.ps1`：使用 WDK 的 Inf2Cat 建立 catalog，並可用既有憑證簽署。
- `Verify-Package.ps1`：不安裝驅動，只檢查套件結構、DLL 架構、catalog 與簽章。

## 建立及簽署 catalog

正式安裝套件需要 `Pd290.cat`，而且 catalog 必須由目標電腦信任的憑證簽署。安裝 Windows Driver Kit（WDK）後執行：

```powershell
.\Build-Catalog.ps1
```

使用憑證存放區中的 Code Signing 憑證：

```powershell
.\Build-Catalog.ps1 -CertificateThumbprint '憑證指紋'
```

或使用 PFX：

```powershell
.\Build-Catalog.ps1 -PfxPath 'C:\secure\codesign.pfx'
```

未簽署的 catalog 只適合內容驗證，正常設定的 Windows 11 仍可能拒絕安裝。對外散布需使用 Microsoft Hardware Dev Center/WHCP 接受的正式簽章流程。

## 安裝前檢查

1. 執行 `.\Verify-Package.ps1`。
2. 到「設定 → 藍牙與裝置 → 印表機與掃描器」，確認 **Windows 受保護列印模式**沒有啟用。這個模式會禁止第三方傳統驅動。
3. 以系統管理員身分開啟 PowerShell，執行：

```powershell
pnputil.exe /add-driver .\Pd290.inf /install
```

也可以從「新增印表機 → 手動新增 → 從磁片安裝」選取 `Pd290.inf`。

## 實機測試

安裝後請測試 Windows 測試頁、58(48) × 210 mm、自訂紙長、直向／橫向、濃度，以及列印結束的走紙／切紙動作。

若失敗，請保留完整錯誤畫面，並匯出事件檢視器中 `Microsoft-Windows-PrintService/Admin` 同一時間的錯誤。
