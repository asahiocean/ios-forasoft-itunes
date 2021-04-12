import Foundation

struct API: GETPOST {
    
    static func get(_ urlStr: String, _ completion: @escaping (Data?)->()) {
        let url: URL = URLS.encoder(urlStr)
        let cache: NSCache = Storage.cache
        var data: Data? { didSet { completion(data) } }
        
        switch cache.object(forKey: url as NSURL) {
        case .some(let nsdata):
            data = Data(referencing: nsdata)
        default:
            do {
                let newData = try Data(contentsOf: url, options: [.mappedRead])
                let nsdata = NSData(data: newData)
                cache.setObject(nsdata, forKey: url as NSURL)
                data = newData
            } catch let error as NSError {
                print(error.localizedDescription)
                // Indicators.network.dc()
            }
        }
    }
    
    static func post(_ urlStr: String = URLS.post, postbody: [String:Any], _ completion: ((Data?)->())? = nil) {
        
        let url: URL = URLS.encoder(urlStr)
        var request = URLRequest(url: url)
        self.requestConfig(&request, .post)
        
        do {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: postbody, options: [.prettyPrinted])
            
            //MARK: POST Authorization
            let username = "pUjBXMqYqWdXOXX7"
            let password = "GdicxwqSrnAk7QeE"
            
            let loginString = String(format: "%@:%@", username, password)
            let loginData: Data = loginString.data(using: .utf8)!
            let base64: String = loginData.base64EncodedString()
            let basic: String = "Basic \(base64)"
            request.setValue(basic, forHTTPHeaderField: "Authorization")
            
            URLSession.shared.dataTask(with: request) { data,_,_ in
                guard let result = completion else { return }
                result(data)
            }.resume()
        } catch let error as NSError {
            print(error.localizedDescription)
        }
    }
    
    fileprivate init() { }
}

extension API {
    fileprivate enum Method: String {
        case get = "GET"
        case post = "POST"
    }
    static fileprivate func requestConfig(_ request: inout URLRequest, _ method: Method) {
        request.httpMethod = method.rawValue
        request.timeoutInterval = .zero
        request.networkServiceType = .background
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    }
    static func request(_ string: String) {
        let (disp,queue,group) = (Dispatcher.self,Dispatcher.queues.self,Dispatcher.groups.self)
        
        disp.operQueue.request.maxConcurrentOperationCount = OperationQueue.defaultMaxConcurrentOperationCount
        
        group.request.enter()
        queue.request.async(group: group.request, execute: { () -> Void in
            
            let get = Self.get
            let url: String = URLS.albums(string, limit: 25)
            
            get(url, { (data) -> Void in
                guard let data = data else {
                    fatalError("DATA NIL: \(url)") }
                
                var request: Request = Handler.jsonDecoder(data)
                
                for i in request.results.indices {
                    let imageUrl = request.results[i].artworkUrl100
                    
                    let loadImage = BlockOperation(block: {
                        get(imageUrl, { data in
                            DispatchQueue.global(qos: .background).async {
                                request.results[i].image100_data = data
                            }
                        })
                    })
                    loadImage.queuePriority = .high
                    loadImage.qualityOfService = .background
                    
                    let urlSongs = URLS.trackList + String(request.results[i].collectionId)
                    
                    let loadSongs = BlockOperation(block: {
                        get(urlSongs, { data in
                            guard let data = data else { return }
                            request.results[i].album = Handler.jsonDecoder(data)
                        })
                    })
                    loadSongs.queuePriority = .high
                    loadSongs.qualityOfService = .background
                    loadSongs.addDependency(loadImage)
                    
                    disp.operQueue.request.addOperations([loadImage,loadSongs], waitUntilFinished: false)
                    // false == non-sequential completion of operations
                }
                disp.operQueue.request.addBarrierBlock {
                    Storage.updater(request)
                }
            })
        })
    }
}
