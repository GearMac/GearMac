// 文件职责：文本提取的命令行入口，接收 <image|pdf> 与文件路径，把提取结果写入标准输出。
// 分层：Service；@main 独立可执行入口，便于在子进程中运行 OCR 以避免阻塞主程序。
import Foundation

/// 命令行入口：参数为 `<image|pdf> <文件路径>`，把提取的文本写入标准输出。
@main
nonisolated enum ClipboardTextHelper {
    /// 校验参数、调用提取器并把结果写入标准输出；失败时以非零状态码退出。
    static func main() async {
        guard CommandLine.arguments.count == 3,
            ["image", "pdf"].contains(CommandLine.arguments[1])
        else { exit(2) }
        do {
            let text = try await ClipboardTextExtractor.extract(
                at: URL(fileURLWithPath: CommandLine.arguments[2]),
                isPDF: CommandLine.arguments[1] == "pdf")
            try FileHandle.standardOutput.write(contentsOf: Data(text.utf8))
        } catch {
            exit(1)
        }
    }
}
