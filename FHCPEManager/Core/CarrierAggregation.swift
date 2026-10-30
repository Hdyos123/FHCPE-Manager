import Foundation

/// 载波单元
struct CarrierComponent: Identifiable {
    let id = UUID()
    let index: Int          // 1 = PCC
    let band: String        // "78"
    let bandwidth: String   // "100MHz"
    let pci: String
    let isPrimary: Bool

    var displayBand: String { band.isEmpty ? "--" : "n\(band)" }
}

@MainActor
extension CpeStore {
    /// 读取载波聚合信息（PCC + 所有 SCC）
    func fetchCarriers() async {
        var mapping: [String: String] = [
            "sccNums": "X_FH_MobileNetwork.NetworkInfo.SCCInfos.Nums",
            "pccBand": "X_FH_MobileNetwork.NetworkInfo.PCCInfo.pccBand",
            "pccBw": "X_FH_MobileNetwork.NetworkInfo.PCCInfo.pccDlBandWidth",
            "pccPci": "X_FH_MobileNetwork.NetworkInfo.PCCInfo.pccPci",
        ]
        // 最多查 4 个 SCC
        for i in 1...4 {
            let b = "X_FH_MobileNetwork.NetworkInfo.SCCInfos.SCCInfo.\(i)."
            mapping["scc\(i)Band"] = b + "sccBand"
            mapping["scc\(i)Bw"] = b + "sccDlBandWidth"
            mapping["scc\(i)Pci"] = b + "sccPci"
        }

        let v = await mp("get_value_by_xmlnode", ["data_1": mapping])
        guard let first = v.first else { return }
        let d = first

        var list: [CarrierComponent] = []

        // PCC 总是存在
        let pccBand = (d["pccBand"] as? String) ?? ""
        if !pccBand.isEmpty {
            list.append(CarrierComponent(index: 1,
                                         band: pccBand,
                                         bandwidth: (d["pccBw"] as? String) ?? "",
                                         pci: (d["pccPci"] as? String) ?? "",
                                         isPrimary: true))
        }

        // SCC
        for i in 1...4 {
            let band = (d["scc\(i)Band"] as? String) ?? ""
            guard !band.isEmpty, band != "0" else { continue }
            list.append(CarrierComponent(index: i + 1,
                                         band: band,
                                         bandwidth: (d["scc\(i)Bw"] as? String) ?? "",
                                         pci: (d["scc\(i)Pci"] as? String) ?? "",
                                         isPrimary: false))
        }

        carriers = list
    }
}
