// 文件职责：封装 MenuSearch 功能对菜单栏 `AXUIElement` 的全部读取、解析与按下操作。
// 分层：Service；不持有 actor 状态，遍历可在主线程之外执行，且不 import AppKit/SwiftUI。
// `@preconcurrency` 用于降级 AX 相关诊断：`kAX…` 是可变的 C 全局量，但实际为常量。
@preconcurrency import ApplicationServices

/// 该功能里对菜单栏 `AXUIElement` 的所有读取：不持有 actor 状态，因此遍历可在主线程之外运行。
enum AXMenuAccess {
    /// 卡死的目标应用不应阻塞唤出；按元素设置超时，与窗口扫描保持一致。
    static let sweepTimeout: Float = 0.2
    /// 整个遍历共用的时间预算；菜单栏过大时宁可截断，也不要拖慢列表。
    static let walkBudget: Duration = .seconds(1)

    /// 为目标进程创建带消息超时的 AX 应用元素。
    static func application(for pid: pid_t) -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, sweepTimeout)
        return application
    }

    /// 读取应用菜单栏的顶层节点树；无菜单栏时返回空数组。
    static func readTopLevel(
        in application: AXUIElement, deadline: ContinuousClock.Instant
    ) -> [MenuTreeNode] {
        guard let bar = element(application, kAXMenuBarAttribute) else { return [] }
        return readNodes(children(of: bar), deadline: deadline)
    }

    /// 快照行背后的实时元素，按路径匹配；菜单已变化时返回 nil。
    static func resolveLeaf(
        in application: AXUIElement, path: [String], title: String
    ) -> AXUIElement? {
        guard let bar = element(application, kAXMenuBarAttribute) else { return nil }
        return resolve(candidates: children(of: bar), trail: [], path: path, title: title)
    }

    /// 对元素执行 AX 按下动作，返回是否成功。
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    /// 已解析出的叶子元素仍值得按下：当前处于启用、可见且可按下状态。
    static func isActionable(_ element: AXUIElement) -> Bool {
        guard bool(element, kAXEnabledAttribute) != false,
            bool(element, kAXHiddenAttribute) != true
        else { return false }
        return canPress(element)
    }

    // MARK: - Reading

    /// 递归读取候选元素的子节点树；超过 deadline 即停止。
    private static func readNodes(
        _ candidates: [AXUIElement], deadline: ContinuousClock.Instant
    ) -> [MenuTreeNode] {
        var nodes: [MenuTreeNode] = []
        nodes.reserveCapacity(candidates.count)
        for child in candidates {
            guard ContinuousClock.now < deadline else { return nodes }
            AXUIElementSetMessagingTimeout(child, sweepTimeout)
            let nested = children(of: child)
            let title = string(child, kAXTitleAttribute) ?? ""
            guard !nested.isEmpty else {
                nodes.append(readLeaf(child, title: title))
                continue
            }
            nodes.append(MenuTreeNode(title: title, children: readNodes(nested, deadline: deadline)))
        }
        return nodes
    }

    /// 把叶子元素读成一个不含子节点的菜单树节点。
    private static func readLeaf(_ element: AXUIElement, title: String) -> MenuTreeNode {
        let details = batch(element)
        return MenuTreeNode(
            title: title,
            isEnabled: details.enabled ?? true,
            isHidden: details.hidden ?? false,
            canPress: canPress(element),
            shortcut: .commandEquivalent(
                character: details.character ?? "", modifiers: details.modifiers ?? 0),
            children: [])
    }

    /// 一次往返读完叶子元素的多个属性值，失败时退回逐个读取。
    private static func batch(
        _ element: AXUIElement
    ) -> (
        enabled: Bool?, hidden: Bool?, character: String?, modifiers: Int?
    ) {
        let names =
            [
                kAXEnabledAttribute, kAXHiddenAttribute, kAXMenuItemCmdCharAttribute,
                kAXMenuItemCmdModifiersAttribute
            ] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names, [], &values) == .success,
            let values = values as? [Any], values.count == 4
        else {
            return (
                bool(element, kAXEnabledAttribute), bool(element, kAXHiddenAttribute),
                string(element, kAXMenuItemCmdCharAttribute),
                (attribute(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue
            )
        }
        return (
            values[0] as? Bool, values[1] as? Bool, values[2] as? String,
            (values[3] as? NSNumber)?.intValue
        )
    }

    /// 元素是否支持 AXPress 动作。
    private static func canPress(_ element: AXUIElement) -> Bool {
        var actions: CFArray?
        return AXUIElementCopyActionNames(element, &actions) == .success
            && (actions as? [String])?.contains(kAXPressAction) == true
    }

    // MARK: - Resolving

    /// 逐层镜像快照遍历，使已展示的行总能被解析到。
    private static func resolve(
        candidates: [AXUIElement], trail: [String], path: [String], title: String
    ) -> AXUIElement? {
        for child in candidates {
            let childTitle = string(child, kAXTitleAttribute) ?? ""
            let nested = children(of: child)
            guard !nested.isEmpty else {
                if trail == path, childTitle == title { return child }
                continue
            }
            var subtrail = trail
            if !childTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                subtrail.append(childTitle)
            }
            guard subtrail.count <= path.count,
                Array(path.prefix(subtrail.count)) == subtrail,
                let found = resolve(
                    candidates: nested, trail: subtrail, path: path, title: title)
            else { continue }
            return found
        }
        return nil
    }

    // MARK: - Primitives

    /// 元素的子元素列表；无该属性时返回空数组。
    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    /// 从属性取出 AXUIElement 类型的值；类型不符时返回 nil。
    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = self.attribute(element, attribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // 上面已用 CFGetTypeID 校验类型；对 CF 类型使用 `as?` 会编译报错。
        return (value as! AXUIElement)
    }

    /// 从属性取出字符串值。
    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        self.attribute(element, attribute) as? String
    }

    /// 从属性取出布尔值。
    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        self.attribute(element, attribute) as? Bool
    }

    /// 拷贝读取元素的单个属性值；失败时返回 nil。
    private static func attribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }
}
