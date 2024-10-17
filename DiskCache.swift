import Foundation
import CryptoKit

fileprivate struct Entry {
    let url: URL
    let meta: URLResourceValues
    
    init?(url: URL?, meta: URLResourceValues?) {
        guard let url = url else { return nil }
        guard let meta = meta else { return nil }
        self.url = url
        self.meta = meta
    }
}   

final class DiskCache {
    static let shared = DiskCache()
    static let name : String = "cache"
    
    var countLimit: Int
    var sizeLimit: Int
    
    // 저장 url
    var folderURL: URL? {
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(DiskCache.name)
    }
    
    init(countLimit: Int = 30, sizeLimit: Int = 1000_000_000) {
        self.countLimit = countLimit
        self.sizeLimit = sizeLimit
        createDirectory()
    }
    
    subscript(_ key: String) -> Data? {
        
        set {
            let sha256 =  SHA256.hash(data: key.data(using: .utf8) ?? Data())
            let key = sha256.compactMap{ String(format:"%02hhx",$0)}.joined()
            //  %: 형식 지정자를 시작하는 문자입니다.
            //  02: 숫자를 최소 두 자리로 출력하며, 한 자리 숫자일 경우 앞에 0을 채워넣습니다.
            //  hh: unsigned char 타입으로 인식하게 합니다. 즉, 1바이트 크기의 데이터를 처리할 수 있도록 합니다.
            //  x: 값을 소문자 16진수로 출력합니다.
            // 0x4f라는 값이 주어지면, 이 형식에 의해 4f라는 문자열로 변환

            guard let folderURL = folderURL else { return }
            let writeURL = folderURL.appendingPathComponent(key) // key를 경로로
    
            if let data = newValue {
                do {
                    try data.write(to: writeURL)
                } catch {
                    print("Disk Cache write Error: \(error)")
                }
            } else {
                try? FileManager.default.removeItem(at: writeURL)
            }
            
            update()
        }
        
        get {
            // 파일path에 접근하기 위해 같은 sha256로 암호화한다.
            let sha256 =  SHA256.hash(data: key.data(using: .utf8) ?? Data())
            let key = sha256.compactMap{ String(format:"%02hhx",$0)}.joined()
            guard let folderURL = folderURL else { return nil }
            let readURL = folderURL.appendingPathComponent(key)
            return FileManager.default.contents(atPath:readURL.path)
        }
        
    }
    
}

extension DiskCache {
    func createDirectory() {
        
        guard let folderURL = self.folderURL else { return }
        
        if !FileManager.default.fileExists(atPath: folderURL.path()) {
            // withIntermediateDirectories: 생성 디렉토리의 부모 디렉토리가 존재하지 않았을 때 생성 여부
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true,attributes: nil)
        }
    }
    
    // 최신화
    private func update() {
        
        guard let folderURL = self.folderURL else { return }
        
         /// .contentAccessDateKey는 파일에 마지막으로 액세스한 날짜를 식별하는 키
         /// .totalFileAllocatedSizeKey는 파일이 차지하는 전체 할당된 크기를 식별하는 키
         /// .contentModificationDateKey는 파일의 마지막 수정 날짜를 식별하는 키
        let keys: [URLResourceKey] = [.contentAccessDateKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]

        /// includingPropertiesForKeys
        /// - 주어진 디렉토리 내의 각 항목에 대해 사전에 가져와야 하는 파일 속성을 식별하는 키
        /// - 반환된 각 URL에 대해 지정된 속성은 가져와져서 NSURL 객체에 캐시됩니다.
         
        ///skipsHiddenFiles
        /// - 옵션은 디렉토리를 나열할 때 숨겨진 파일을 무시하도록 지정하는 옵션입니다.
         
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: keys,options: .skipsHiddenFiles) else {
            return
        }
        
        if urls.isEmpty { return }
        
        let past = Date.distantPast
        
        
        var entrys = urls.compactMap { (url) -> Entry? in
            return Entry(url: url, meta: try? url.resourceValues(forKeys: Set(keys)))
            
        }.sorted(by: {
            
            let firstModifyDate = $0.meta.contentModificationDate ?? past
            let firstAccessDate = $0.meta.contentAccessDate ?? past
            
            let firstDate = firstModifyDate > firstAccessDate ? firstModifyDate : firstAccessDate
            let lastModifyDate = $1.meta.contentModificationDate ?? past
            let lastAccessDate = $1.meta.contentAccessDate ?? past
            let lastDate = lastModifyDate  > lastAccessDate ? lastModifyDate : lastAccessDate
            
            // 더 최신께 앞으로 , 가장 오래 전에 수정된 것이 뒤로
            // LRU
            return firstDate > lastDate
            
        })
        
        var count = entrys.count
        var totalSize = entrys.reduce(0, { $0 + ($1.meta.totalFileAllocatedSize ?? 0) })
        
        // 한도 초과 확인 (갯수, 사이즈)
        guard count > self.countLimit || totalSize > self.sizeLimit else { return }
    
        // 초과한 분량제거
        while ( count > self.countLimit || totalSize > self.sizeLimit ), let entry = entrys.popLast() {  // 가장 오래전에 수정된 것을 하나씩 꺼내옴
            count -= 1
            totalSize -= (entry.meta.totalFileAllocatedSize ?? 0)
            try? FileManager.default.removeItem(at: entry.url)
        }
        
    }
}
