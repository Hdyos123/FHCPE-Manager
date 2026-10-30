import Foundation

/// 载波单元（PCC 或 SCC）
struct CarrierComponent: Identifiable {
    let id = UUID()
    let index: Int              // 1 = PCC
    let isPrimary: Bool
    let band: String            // "78"
    let bandwidth: String       // "100MHz"
    let arfcn: String
    let pci: String
    let rsrp: String
    let rsrq: String
    let rssi: String
    let sinr: String

    var displayBand: String { band.isEmpty || band == "-" ? "--" : "N\(band)" }
    var tag: String { isPrimary ? "PCC" : "SCC" }
}

@MainActor
extension CpeStore {
    /// 采集载波聚合信息（PCC + SCC1~3）
    func fetchCarriers() async {
        var map: [String: String] = [
            "nums": "X_FH_MobileNetwork.NetworkInfo.SCCInfos.Nums",
            // PCC
            "pBand": "X_FH_MobileNetwork.NetworkInfo.PCCInfo.pccBand",
            "pBw":   "X_FH_MobileNetwork.NetworkInfo.PCCInfo.pccDlBandWidth",
            "pArfcn": "X_FH_MobileNetwork.NetworkInfo.PCCInfo.pccArfcn",
            "pPci":  "X_FH_MobileNetwork.NetworkInfo.PCCInfo.pccPci",
            "pRsrp": "X_FH_MobileNetwork.RadioSignalParameter.SSB_RSRP",
            "pRsrq": "X_FH_MobileNetwork.RadioSignalParameter.SSB_RSRQ",
            "pRssi": "X_FH_MobileNetwork.RadioSignalParameter.SSB_RSSI",
            "pSinr": "X_FH_MobileNetwork.RadioSignalParameter.SSB_SINR",
        ]
        let base = "X_FH_MobileNetwork.NetworkInfo.SCCInfos."
        for i in 1...3 {
            map["s\(i)Band"]  = base + "\(i).sccBand"
            map["s\(i)Bw"]    = base + "\(i).sccDlBandWidth"
            map["s\(i)Arfcn"] = base + "\(i).sccArfcn"
            map["s\(i)Pci"]   = base + "\(i).sccPci"
            map["s\(i)Rsrp"]  = base + "\(i).sccRsrp"
            map["s\(i)Rsrq"]  = base + "\(i).sccRsrq"
            map["s\(i)Rssi"]  = base + "\(i).sccRssi"
            map["s\(i)Sinr"]  = base + "\(i).sccSinr"
        }

        let rows = await mp("get_value_by_xmlnode", ["data_1": map])
        guard let d = rows.first else { return }

        func g(_ k: String) -> String {
            let v = (d[k] as? String) ?? ""
            return (v == "-" || v.isEmpty) ? "" : v
        }

        var list: [CarrierComponent] = []

        // PCC
        let pBand = g("pBand")
        if !pBand.isEmpty {
            list.append(CarrierComponent(
                index: 1, isPrimary: true,
                band: pBand, bandwidth: g("pBw"),
                arfcn: g("pArfcn"), pci: g("pPci"),
                rsrp: g("pRsrp"), rsrq: g("pRsrq"),
                rssi: g("pRssi"), sinr: g("pSinr")))
        }

        // SCC
        for i in 1...3 {
            let band = g("s\(i)Band")
            guard !band.isEmpty else { continue }
            list.append(CarrierComponent(
                index: i + 1, isPrimary: false,
                band: band, bandwidth: g("s\(i)Bw"),
                arfcn: g("s\(i)Arfcn"), pci: g("s\(i)Pci"),
                rsrp: g("s\(i)Rsrp"), rsrq: g("s\(i)Rsrq"),
                rssi: g("s\(i)Rssi"), sinr: g("s\(i)Sinr")))
        }

        carriers = list
    }
}
