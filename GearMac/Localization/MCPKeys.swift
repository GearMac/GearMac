// 文件职责：MCP 服务器功能的本地化键与中英词表（设置分区、编辑器、信任等级与状态）。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// MCP 设置分区、服务器编辑器、信任等级、状态与工具授权对话框的键。
enum MCPKey: String, LocalizableKey {
    // 设置分区
    case enableServers = "mcp.settings.enableServers"
    case emptyState = "mcp.settings.emptyState"
    case addServer = "mcp.settings.addServer"
    case sectionFooter = "mcp.settings.footer"
    case removeDialogTitle = "mcp.settings.removeDialogTitle"
    case removeThisServer = "mcp.settings.removeThisServer"
    case remove = "mcp.settings.remove"
    case removeDialogMessage = "mcp.settings.removeDialogMessage"
    case saveKeychainFailed = "mcp.settings.saveKeychainFailed"
    case removeKeychainFailed = "mcp.settings.removeKeychainFailed"
    case statusDisabled = "mcp.settings.statusDisabled"
    case editServer = "mcp.settings.editServer"
    case removeServer = "mcp.settings.removeServer"

    // 编辑器
    case editorAddTitle = "mcp.editor.addTitle"
    case editorEditTitle = "mcp.editor.editTitle"
    case kindHTTP = "mcp.editor.kindHTTP"
    case kindCommand = "mcp.editor.kindCommand"
    case fieldName = "mcp.editor.fieldName"
    case fieldHandle = "mcp.editor.fieldHandle"
    case fieldConnection = "mcp.editor.fieldConnection"
    case fieldURL = "mcp.editor.fieldURL"
    case fieldAuthentication = "mcp.editor.fieldAuthentication"
    case fieldHeader = "mcp.editor.fieldHeader"
    case authOAuth = "mcp.editor.authOAuth"
    case fieldValue = "mcp.editor.fieldValue"
    case fieldCommand = "mcp.editor.fieldCommand"
    case fieldArguments = "mcp.editor.fieldArguments"
    case fieldEnvironment = "mcp.editor.fieldEnvironment"
    case httpFooter = "mcp.editor.httpFooter"
    case stdioFooter = "mcp.editor.stdioFooter"
    case offerTools = "mcp.editor.offerTools"
    case fieldTrust = "mcp.editor.fieldTrust"
    case testConnection = "mcp.editor.testConnection"
    case toolCount = "mcp.editor.toolCount"
    case toolCountOne = "mcp.editor.toolCountOne"
    case trustFooter = "mcp.editor.trustFooter"
    case buttonCancel = "mcp.editor.cancel"
    case buttonSave = "mcp.editor.save"
    case clientID = "mcp.editor.clientID"
    case clientIDPrompt = "mcp.editor.clientIDPrompt"
    case clientSecret = "mcp.editor.clientSecret"
    case optional = "mcp.editor.optional"
    case signInSection = "mcp.editor.signInSection"
    case signOut = "mcp.editor.signOut"
    case signIn = "mcp.editor.signIn"
    case credentialsRemoveFailed = "mcp.editor.credentialsRemoveFailed"
    case probeSignInRequired = "mcp.editor.probeSignInRequired"
    case probeNoAnswer = "mcp.editor.probeNoAnswer"
    case commandRequired = "mcp.editor.commandRequired"

    // 信任等级
    case trustAsk = "mcp.trust.ask"
    case trustAlways = "mcp.trust.always"
    case trustNever = "mcp.trust.never"

    // 状态
    case statusStopped = "mcp.status.stopped"
    case statusSignInRequired = "mcp.status.signInRequired"
    case statusConnecting = "mcp.status.connecting"
    case statusToolCount = "mcp.status.toolCount"
    case statusToolCountOne = "mcp.status.toolCountOne"
    case statusNotSignedIn = "mcp.status.notSignedIn"
    case statusWaitingSignIn = "mcp.status.waitingSignIn"
    case statusSignedIn = "mcp.status.signedIn"

    // 传输错误
    case errorNotRunning = "mcp.error.notRunning"
    case errorMalformedResponse = "mcp.error.malformedResponse"
    case errorTimedOut = "mcp.error.timedOut"
    case errorCommandNotFound = "mcp.error.commandNotFound"

    // 工具授权对话框
    case toolNoLongerConnected = "mcp.tool.noLongerConnected"
    case toolDeclined = "mcp.tool.declined"
    case toolRunTitle = "mcp.tool.runTitle"
    case toolRunMessage = "mcp.tool.runMessage"
    case toolAlwaysAllow = "mcp.tool.alwaysAllow"
    case toolAllowThisChat = "mcp.tool.allowThisChat"
    case toolDontAllow = "mcp.tool.dontAllow"

    // OAuth 失败
    case oauthInvalidMetadata = "mcp.oauth.invalidMetadata"
    case oauthPKCEUnsupported = "mcp.oauth.pkceUnsupported"
    case oauthClientRequired = "mcp.oauth.clientRequired"
    case oauthIssuerChanged = "mcp.oauth.issuerChanged"
    case oauthInvalidCallback = "mcp.oauth.invalidCallback"
    case oauthDeclined = "mcp.oauth.declined"
    case oauthNoToken = "mcp.oauth.noToken"
    case oauthSignInRequired = "mcp.oauth.signInRequired"
    case oauthNetwork = "mcp.oauth.network"
    case oauthRegistration = "mcp.oauth.registration"
    case oauthPortUnavailable = "mcp.oauth.portUnavailable"
    case oauthInProgress = "mcp.oauth.inProgress"
    case oauthTimedOut = "mcp.oauth.timedOut"

    static let table: [String: L10nEntry] = [
        MCPKey.enableServers.rawValue: L10nEntry("Enable MCP servers", "启用 MCP 服务器"),
        MCPKey.emptyState.rawValue: L10nEntry("No MCP servers yet.", "尚无 MCP 服务器。"),
        MCPKey.addServer.rawValue: L10nEntry("Add MCP Server", "添加 MCP 服务器"),
        MCPKey.sectionFooter.rawValue: L10nEntry(
            "Type @slug to address one server. A chat asks before its first tool call.",
            "输入 @slug 来指定某个服务器。对话会在首次调用工具前询问。"),
        MCPKey.removeDialogTitle.rawValue: L10nEntry("Remove %@?", "移除 %@？"),
        MCPKey.removeThisServer.rawValue: L10nEntry("this server", "此服务器"),
        MCPKey.remove.rawValue: L10nEntry("Remove", "移除"),
        MCPKey.removeDialogMessage.rawValue: L10nEntry(
            "Its tools stop being offered, and its stored credentials are deleted.",
            "其工具将不再提供，存储的凭证会被删除。"),
        MCPKey.saveKeychainFailed.rawValue: L10nEntry(
            "The credentials could not be saved to your login Keychain.",
            "无法把凭证保存到你的登录钥匙串。"),
        MCPKey.removeKeychainFailed.rawValue: L10nEntry(
            "%@ was kept: its credentials could not be removed from your login Keychain.",
            "已保留 %@：无法从你的登录钥匙串移除其凭证。"),
        MCPKey.statusDisabled.rawValue: L10nEntry("Disabled", "已停用"),
        MCPKey.editServer.rawValue: L10nEntry("Edit %@", "编辑 %@"),
        MCPKey.removeServer.rawValue: L10nEntry("Remove %@", "移除 %@"),

        MCPKey.editorAddTitle.rawValue: L10nEntry("Add MCP Server", "添加 MCP 服务器"),
        MCPKey.editorEditTitle.rawValue: L10nEntry("Edit MCP Server", "编辑 MCP 服务器"),
        MCPKey.kindHTTP.rawValue: L10nEntry("HTTP", "HTTP"),
        MCPKey.kindCommand.rawValue: L10nEntry("Command", "命令"),
        MCPKey.fieldName.rawValue: L10nEntry("Name", "名称"),
        MCPKey.fieldHandle.rawValue: L10nEntry("Handle", "句柄"),
        MCPKey.fieldConnection.rawValue: L10nEntry("Connection", "连接方式"),
        MCPKey.fieldURL.rawValue: L10nEntry("URL", "URL"),
        MCPKey.fieldAuthentication.rawValue: L10nEntry("Authentication", "认证方式"),
        MCPKey.fieldHeader.rawValue: L10nEntry("Header", "请求头"),
        MCPKey.authOAuth.rawValue: L10nEntry("OAuth", "OAuth"),
        MCPKey.fieldValue.rawValue: L10nEntry("Value", "值"),
        MCPKey.fieldCommand.rawValue: L10nEntry("Command", "命令"),
        MCPKey.fieldArguments.rawValue: L10nEntry("Arguments", "参数"),
        MCPKey.fieldEnvironment.rawValue: L10nEntry("Environment", "环境变量"),
        MCPKey.httpFooter.rawValue: L10nEntry(
            "Remote endpoints must use HTTPS. Credentials are stored in your login Keychain, never in preferences.",
            "远程端点必须使用 HTTPS。凭证保存在你的登录钥匙串中，绝不写入偏好设置。"),
        MCPKey.stdioFooter.rawValue: L10nEntry(
            "The command runs on this Mac with your own account. One NAME=value per line; values are stored in your login Keychain.",
            "该命令以你自己的账户在这台 Mac 上运行。每行一个 NAME=value；其值保存在你的登录钥匙串中。"),
        MCPKey.offerTools.rawValue: L10nEntry(
            "Offer this server's tools", "提供此服务器的工具"),
        MCPKey.fieldTrust.rawValue: L10nEntry("Trust", "信任等级"),
        MCPKey.testConnection.rawValue: L10nEntry("Test Connection", "测试连接"),
        MCPKey.toolCount.rawValue: L10nEntry("%d tools", "%d 个工具"),
        MCPKey.toolCountOne.rawValue: L10nEntry("1 tool", "1 个工具"),
        MCPKey.trustFooter.rawValue: L10nEntry(
            "Ask Each Chat puts the first tool call of every conversation through a confirmation. Never Allow withholds the server without removing it.",
            "「每次对话询问」会让每次对话的首次工具调用先经过确认。「从不允许」会在不移除服务器的情况下停用其工具。"),
        MCPKey.buttonCancel.rawValue: L10nEntry("Cancel", "取消"),
        MCPKey.buttonSave.rawValue: L10nEntry("Save", "保存"),
        MCPKey.clientID.rawValue: L10nEntry("Client ID", "客户端 ID"),
        MCPKey.clientIDPrompt.rawValue: L10nEntry(
            "Optional — register automatically", "可选 — 自动注册"),
        MCPKey.clientSecret.rawValue: L10nEntry("Client secret", "客户端密钥"),
        MCPKey.optional.rawValue: L10nEntry("Optional", "可选"),
        MCPKey.signInSection.rawValue: L10nEntry("Sign-in", "登录"),
        MCPKey.signOut.rawValue: L10nEntry("Sign Out", "退出登录"),
        MCPKey.signIn.rawValue: L10nEntry("Sign In", "登录"),
        MCPKey.credentialsRemoveFailed.rawValue: L10nEntry(
            "The credentials could not be removed from your login Keychain.",
            "无法从你的登录钥匙串移除凭证。"),
        MCPKey.probeSignInRequired.rawValue: L10nEntry(
            "Sign-in required", "需要登录"),
        MCPKey.probeNoAnswer.rawValue: L10nEntry(
            "The server did not answer.", "服务器没有响应。"),
        MCPKey.commandRequired.rawValue: L10nEntry(
            "Enter the command that starts this server.", "请输入启动此服务器的命令。"),

        MCPKey.trustAsk.rawValue: L10nEntry("Ask Each Chat", "每次对话询问"),
        MCPKey.trustAlways.rawValue: L10nEntry("Always Allow", "始终允许"),
        MCPKey.trustNever.rawValue: L10nEntry("Never Allow", "从不允许"),

        MCPKey.statusStopped.rawValue: L10nEntry("Stopped", "已停止"),
        MCPKey.statusSignInRequired.rawValue: L10nEntry("Sign-in required", "需要登录"),
        MCPKey.statusConnecting.rawValue: L10nEntry("Connecting…", "正在连接…"),
        MCPKey.statusToolCount.rawValue: L10nEntry("%d tools", "%d 个工具"),
        MCPKey.statusToolCountOne.rawValue: L10nEntry("1 tool", "1 个工具"),
        MCPKey.statusNotSignedIn.rawValue: L10nEntry("Not signed in", "未登录"),
        MCPKey.statusWaitingSignIn.rawValue: L10nEntry(
            "Waiting for sign-in…", "正在等待登录…"),
        MCPKey.statusSignedIn.rawValue: L10nEntry("Signed in", "已登录"),

        MCPKey.errorNotRunning.rawValue: L10nEntry(
            "The server is not running.", "服务器未在运行。"),
        MCPKey.errorMalformedResponse.rawValue: L10nEntry(
            "The server sent a response GearMac could not read.",
            "服务器返回了 GearMac 无法读取的响应。"),
        MCPKey.errorTimedOut.rawValue: L10nEntry(
            "The server did not respond in time.", "服务器未及时响应。"),
        MCPKey.errorCommandNotFound.rawValue: L10nEntry(
            "`%@` was not found on this Mac.", "在这台 Mac 上找不到 `%@`。"),

        MCPKey.toolNoLongerConnected.rawValue: L10nEntry(
            "That tool is no longer connected.", "该工具已不再连接。"),
        MCPKey.toolDeclined.rawValue: L10nEntry(
            "The user declined this tool call.", "用户拒绝了此次工具调用。"),
        MCPKey.toolRunTitle.rawValue: L10nEntry(
            "Let %@ run its tools?", "允许 %@ 运行其工具吗？"),
        MCPKey.toolRunMessage.rawValue: L10nEntry(
            "The model wants to call “%@”. GearMac did not write this server and cannot vouch for what it does.",
            "模型想要调用“%@”。GearMac 并未编写该服务器，无法保证其行为。"),
        MCPKey.toolAlwaysAllow.rawValue: L10nEntry("Always Allow", "始终允许"),
        MCPKey.toolAllowThisChat.rawValue: L10nEntry("Allow This Chat", "允许本次对话"),
        MCPKey.toolDontAllow.rawValue: L10nEntry("Don't Allow", "不允许"),

        MCPKey.oauthInvalidMetadata.rawValue: L10nEntry(
            "The server's OAuth metadata is invalid.", "服务器的 OAuth 元数据无效。"),
        MCPKey.oauthPKCEUnsupported.rawValue: L10nEntry(
            "The authorization server must advertise PKCE S256 support.",
            "授权服务器必须声明支持 PKCE S256。"),
        MCPKey.oauthClientRequired.rawValue: L10nEntry(
            "Enter a registered client ID. This server cannot register GearMac automatically.",
            "请输入已注册的客户端 ID。此服务器无法自动注册 GearMac。"),
        MCPKey.oauthIssuerChanged.rawValue: L10nEntry(
            "The authorization server changed. Enter client credentials for the new server.",
            "授权服务器已更改。请输入新服务器的客户端凭证。"),
        MCPKey.oauthInvalidCallback.rawValue: L10nEntry(
            "The sign-in response could not be verified.", "无法验证登录响应。"),
        MCPKey.oauthDeclined.rawValue: L10nEntry("Sign-in was declined.", "登录被拒绝。"),
        MCPKey.oauthNoToken.rawValue: L10nEntry(
            "The authorization server did not return a usable bearer token.",
            "授权服务器未返回可用的 bearer token。"),
        MCPKey.oauthSignInRequired.rawValue: L10nEntry(
            "Sign-in required. Open this MCP server in Settings to sign in.",
            "需要登录。请在设置中打开此 MCP 服务器进行登录。"),
        MCPKey.oauthNetwork.rawValue: L10nEntry(
            "The OAuth request failed. Check the connection and try again.",
            "OAuth 请求失败。请检查连接后重试。"),
        MCPKey.oauthRegistration.rawValue: L10nEntry(
            "Client registration failed. Enter a registered client ID and try again.",
            "客户端注册失败。请输入已注册的客户端 ID 后重试。"),
        MCPKey.oauthPortUnavailable.rawValue: L10nEntry(
            "Sign-in could not open loopback port 4962. Close the app using it and retry.",
            "登录无法打开回环端口 4962。请关闭占用它的应用后重试。"),
        MCPKey.oauthInProgress.rawValue: L10nEntry(
            "Another sign-in is still waiting. Finish it first.",
            "还有另一个登录正在等待。请先完成它。"),
        MCPKey.oauthTimedOut.rawValue: L10nEntry("Sign-in timed out. Try again.", "登录超时。请重试。"),
    ]
}
