import UIKit

enum NetworkingError : Error {
    case imageCachingError
}



typealias SuccessHandler = (_ image: UIImage) -> Void
typealias FailureHandler = (_ error: NetworkingError) -> Void

final class ImageCacheManager {
    static let shared = ImageCacheManager()
    
    private let requestCachePolicy: NSURLRequest.CachePolicy = .useProtocolCachePolicy
    private let timeInterval: TimeInterval = 30.0
    private let session: URLSession = URLSession(configuration: URLSessionConfiguration.default)
    
    private let urlCache =  URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024) // 휘발성 캐시
    private let nsCache = NSCache<NSString, UIImage>() // NSCache의 value는 class만 가능
    private let diskCache = DiskCache()
    
    
    func fetchImage(url: URL?) async throws -> UIImage? {
        
        guard let url, !url.absoluteString.isEmpty else { throw NetworkingError.imageCachingError }
        let urlRequest = URLRequest(url: url, cachePolicy: requestCachePolicy, timeoutInterval: timeInterval)
        
        // url 캐시 확인
        if let cacheResponse = urlCache.cachedResponse(for: urlRequest) {
            if let image = UIImage(data: cacheResponse.data) {
                print("Fetch from url cache")
                return image
            }
        }
        
        // NSCache
        if let cachedImage = nsCache.object(forKey: NSString(string: url.absoluteString)) {
            print("Fetch from NSCache")
            return cachedImage
        }
        
        
        // 디스크 캐시 존재한다면, urlCache 저장
        if let data = diskCache[url.absoluteString] {
            
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) , let image = UIImage(data: data) else {
                throw NetworkingError.imageCachingError
            }
        
            let cacheResponse = CachedURLResponse(response: response, data: data)
            
            urlCache.storeCachedResponse(cacheResponse, for: urlRequest) // urlCache에 저장
            nsCache.setObject(image, forKey: NSString(string: url.absoluteString))
            print("Fetch from disk cache")
            return UIImage(data: data)
        }
        
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let image = UIImage(data: data) else {
            throw NetworkingError.imageCachingError
        }
    
        
        let cacheResponse = CachedURLResponse(response: response, data: data)
        urlCache.storeCachedResponse(cacheResponse, for: urlRequest) // url 캐시에 저장
        diskCache[url.absoluteString] = data // 디스크 캐시에 저장
        nsCache.setObject(image, forKey: NSString(string: url.absoluteString)) // ns cache에 저장
        
        return UIImage(data: data)
    }
}
