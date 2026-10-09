// 文件职责：校验待替换的应用包确实由本应用签名（Developer ID 证书链，或与旧副本固定的叶证书一致）。
// 分层：Service（Security.framework 封装）；不做网络请求，仅做本地代码签名校验。
import Foundation
import Security

/// 证明待安装的应用包确属本应用：要么满足 Developer ID 证书链，要么与切换前旧副本固定的叶证书一致。
enum BundleSignature {
    /// 这里绑定的是团队而非具体证书——叶证书在续期和改名时都会重新签发。
    static let developerID = """
        anchor apple generic \
        and certificate leaf[subject.OU] = "SPBUD83MLU" \
        and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] exists
        """

    /// 校验指定应用包的签名是否可信。
    static func isTrusted(_ bundleURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode
        else { return false }
        // 未封存的包可以冒用任意身份，而嵌套的辅助程序正是隐藏冒用者的地方。
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(staticCode, flags, nil) == errSecSuccess else { return false }
        if satisfiesDeveloperID(staticCode, flags: flags) { return true }
        // 在改用 Developer ID 校验之前安装的副本，只认识它自己被签名时使用的那张叶证书。
        guard let running = runningLeaf(), let candidate = leaf(of: staticCode) else { return false }
        return running == candidate
    }

    /// 不包含 `notarized` 检查：其票据查询可能触网，而证书链本身已能证明归属。
    private static func satisfiesDeveloperID(_ code: SecStaticCode, flags: SecCSFlags) -> Bool {
        var requirement: SecRequirement?
        guard
            SecRequirementCreateWithString(developerID as CFString, [], &requirement)
                == errSecSuccess, let requirement
        else { return false }
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    /// 取得当前正在运行的可执行文件的叶证书数据。
    private static func runningLeaf() -> Data? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        return leaf(of: staticCode)
    }

    /// 从静态代码对象中取出签名证书链的第一张（叶）证书。
    private static func leaf(of code: SecStaticCode) -> Data? {
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
            let dictionary = information as? [String: Any],
            let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
            let leaf = certificates.first
        else { return nil }
        return SecCertificateCopyData(leaf) as Data
    }
}
