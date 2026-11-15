import CoreImage
import Foundation
import Metal

/// Detected Apple Silicon CPU & Metal GPU capabilities used to size parallel batch export pipelines.
public struct HardwareCapabilities: Sendable {
    public let chipName: String
    public let totalLogicalCores: Int
    public let performanceCores: Int
    public let efficiencyCores: Int
    public let physicalMemoryBytes: UInt64
    public let metalDeviceName: String
    public let hasUnifiedMemory: Bool
    public let recommendedMaxWorkingSetBytes: UInt64

    public var physicalMemoryGB: Double {
        Double(physicalMemoryBytes) / 1_073_741_824.0
    }

    /// Tunes worker count to saturate Apple Silicon Performance cores + Metal command queues without exhausting unified memory.
    public var optimalBatchConcurrency: Int {
        let pCores = performanceCores > 0 ? performanceCores : totalLogicalCores
        let memoryBound = max(2, Int(physicalMemoryGB / 2.0))
        return min(12, max(2, min(pCores, memoryBound)))
    }

    public var summaryBadge: String {
        let memGB = Int(physicalMemoryGB.rounded())
        return "\(chipName) · \(performanceCores)P+\(efficiencyCores)E · \(memGB)GB Unified"
    }

    public static func detect() -> HardwareCapabilities {
        let chip = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        let total = max(1, sysctlInt("hw.ncpu") ?? ProcessInfo.processInfo.activeProcessorCount)
        let rawPerf = sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        let perf = rawPerf > 0 ? rawPerf : total
        let eff = sysctlInt("hw.perflevel1.logicalcpu") ?? max(0, total - perf)
        let mem = ProcessInfo.processInfo.physicalMemory

        let device = MTLCreateSystemDefaultDevice()
        let gpuName = device?.name ?? "Apple GPU"
        let unified = device?.hasUnifiedMemory ?? true
        let workingSet = device?.recommendedMaxWorkingSetSize ?? (mem / 2)

        return HardwareCapabilities(
            chipName: chip,
            totalLogicalCores: total,
            performanceCores: perf,
            efficiencyCores: eff,
            physicalMemoryBytes: mem,
            metalDeviceName: gpuName,
            hasUnifiedMemory: unified,
            recommendedMaxWorkingSetBytes: workingSet
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size: Int = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        let bytes = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var val: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &val, &size, nil, 0) == 0 else { return nil }
        return Int(val)
    }
}

/// Manages a bounded pool of Metal-backed `CIContext` instances sharing Apple Silicon Unified Memory.
public final class CIContextPool: @unchecked Sendable {
    public let capabilities: HardwareCapabilities
    public let metalDevice: MTLDevice?

    private let lock = NSLock()
    private var availableContexts: [CIContext]
    private var waiters: [CheckedContinuation<CIContext, Never>] = []

    public init(capabilities: HardwareCapabilities = .detect(), contextCount: Int? = nil) {
        self.capabilities = capabilities
        let device = MTLCreateSystemDefaultDevice()
        self.metalDevice = device

        let poolSize = max(1, min(6, contextCount ?? min(4, capabilities.optimalBatchConcurrency)))
        var contexts: [CIContext] = []
        let workingCS = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) ?? CGColorSpaceCreateDeviceRGB()

        for _ in 0..<poolSize {
            if let device {
                contexts.append(CIContext(mtlDevice: device, options: [
                    .workingColorSpace: workingCS,
                    .workingFormat: CIFormat.RGBAh,
                    .cacheIntermediates: false,
                    .priorityRequestLow: false
                ]))
            } else {
                contexts.append(CIContext(options: [
                    .workingColorSpace: workingCS,
                    .workingFormat: CIFormat.RGBAh,
                    .cacheIntermediates: false
                ]))
            }
        }
        self.availableContexts = contexts
    }

    public func lease() async -> CIContext {
        await withCheckedContinuation { continuation in
            lock.lock()
            if !availableContexts.isEmpty {
                let ctx = availableContexts.removeLast()
                lock.unlock()
                continuation.resume(returning: ctx)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    public func release(_ context: CIContext) {
        lock.lock()
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            lock.unlock()
            next.resume(returning: context)
        } else {
            availableContexts.append(context)
            lock.unlock()
        }
    }

    public func withContext<T: Sendable>(_ body: @Sendable (CIContext) throws -> T) async rethrows -> T {
        let ctx = await lease()
        defer { release(ctx) }
        return try body(ctx)
    }
}
