// API.swift — 服务器接口（register / room/create）
import Foundation
import UIKit

struct API {
    var base: String   // 形如 http://120.26.174.238

    private func call(_ path: String, body: [String: Any], token: String? = nil) throws -> [String: Any] {
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token { req.setValue("Bearer " + t, forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try URLSession.shared.synchronousDataTask(with: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "api", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)"])
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    /// 注册设备 → token
    func register() throws -> String {
        let uid = (UserDefaults.standard.string(forKey: "device_uid")
            ?? UUID().uuidString.lowercased())
        UserDefaults.standard.set(uid, forKey: "device_uid")
        let r = try call("/api/device/register", body: [
            "device_uid": uid, "platform": "ios",
            "device_name": UIDevice.current.name,
            "app_version": "1.0", "os_version": "iOS " + UIDevice.current.systemVersion])
        guard let t = r["token"] as? String else {
            throw NSError(domain: "api", code: -2, userInfo: [NSLocalizedDescriptionKey: r["message"] as? String ?? "未返回令牌"])
        }
        return t
    }

    /// 建房 → (房间号, 雷达链接)
    func createRoom(token: String) throws -> (String, String) {
        let r = try call("/api/room/create", body: ["name": "ios"], token: token)
        let room = r["room"] as? [String: Any]
        guard let code = room?["code"] as? String else {
            throw NSError(domain: "api", code: -3, userInfo: [NSLocalizedDescriptionKey: "未返回房间号"])
        }
        let radar = (r["radar_url"] as? String) ?? (base + "/radar/?room=" + code)
        return (code, radar)
    }
}

extension URLSession {
    func synchronousDataTask(with req: URLRequest) throws -> (Data, URLResponse) {
        var out: (Data, URLResponse)!
        let sem = DispatchSemaphore(value: 0)
        dataTask(with: req) { d, r, e in
            if let d = d, let r = r { out = (d, r) }
            else { out = (Data(), e.map { _ in URLResponse() } ?? URLResponse()) }
            sem.signal()
        }.resume()
        sem.wait()
        return out
    }
}
