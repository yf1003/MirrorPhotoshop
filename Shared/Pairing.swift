import Foundation

/// Versioned connection information carried only by PSD Mirror's pairing QR code.
struct MirrorPairing: Equatable {
    let hosts: [String]
    let port: Int
    let code: String

    init?(hosts: [String], port: Int, code: String) {
        guard !hosts.isEmpty, hosts.count <= 8, Set(hosts).count == hosts.count,
              hosts.allSatisfy(Self.validHost), (1...65535).contains(port),
              code.utf8.count == 8, code.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        self.hosts = hosts; self.port = port; self.code = code
    }

    var qrString: String {
        var value = URLComponents()
        value.scheme = "psdmirror"; value.host = "pair"
        value.queryItems = [URLQueryItem(name: "v", value: "1"),
                            URLQueryItem(name: "hosts", value: hosts.joined(separator: ",")),
                            URLQueryItem(name: "port", value: String(port)),
                            URLQueryItem(name: "code", value: code)]
        return value.string!
    }

    var baseURLs: [URL] {
        hosts.map { host in
            var value = URLComponents()
            value.scheme = "http"; value.host = host; value.port = port
            return value.url!
        }
    }

    static func decode(_ text: String) -> MirrorPairing? {
        guard text.utf8.count <= 2048, let value = URLComponents(string: text),
              value.scheme == "psdmirror", value.host == "pair", value.path.isEmpty,
              value.user == nil, value.password == nil, value.port == nil, value.fragment == nil,
              let items = value.queryItems, items.count == 4,
              Set(items.map(\.name)) == Set(["v", "hosts", "port", "code"]),
              items.allSatisfy({ $0.value != nil }) else { return nil }
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        guard fields["v"] == "1", let portText = fields["port"],
              portText.utf8.allSatisfy({ (48...57).contains($0) }), let port = Int(portText),
              let hosts = fields["hosts"], let code = fields["code"] else { return nil }
        return MirrorPairing(hosts: hosts.components(separatedBy: ","), port: port, code: code)
    }

    // The Mac currently advertises IPv4 interfaces. Accept unicast numeric hosts
    // only, so scanned text cannot inject a URL path, credentials or another scheme.
    static func validHost(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let n = Int(part), (0...255).contains(n), String(n) == part else { return nil }
            return n
        }
        return numbers.count == 4 && (1...223).contains(numbers[0]) && numbers[0] != 127
    }
}
