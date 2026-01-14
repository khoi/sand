struct VMConfigurer {
    static func applyIfNeeded(tart: Tart, name: String, vm: Config.VM) throws {
        let hardware = vm.hardware
        let display: Tart.Display? = hardware?.display.map {
            Tart.Display(width: $0.width, height: $0.height, unit: $0.unit?.rawValue)
        }
        let displayRefit = hardware?.display?.refit
        let memoryMb = hardware?.ramGb.map { $0 * 1024 }
        let cpuCores = hardware?.cpuCores
        let diskSizeGb = vm.diskSizeGb
        guard cpuCores != nil || memoryMb != nil || display != nil || displayRefit != nil || diskSizeGb != nil else {
            return
        }
        try tart.set(
            name: name,
            cpuCores: cpuCores,
            memoryMb: memoryMb,
            display: display,
            displayRefit: displayRefit,
            diskSizeGb: diskSizeGb
        )
    }

    static func applyDiskSizeIfNeeded(tart: Tart, name: String, vm: Config.VM) throws {
        guard let diskSizeGb = vm.diskSizeGb else {
            return
        }
        try tart.set(
            name: name,
            cpuCores: nil,
            memoryMb: nil,
            display: nil,
            displayRefit: nil,
            diskSizeGb: diskSizeGb
        )
    }
}
