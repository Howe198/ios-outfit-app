import Foundation
import CoreLocation

/// 定位天气：坐标只在内存里用一次，交给 Open-Meteo 换回当前气温；
/// 不写磁盘、不上传到自建服务。任何一步失败都抛错，由界面回落到手动温度。
struct WeatherSnapshot: Equatable {
    let temperature: Int
    let cityName: String?
    let fetchedAt: Date
}

enum WeatherPhase: Equatable {
    case idle
    case loading
    case loaded(WeatherSnapshot)
    case failed(String)
}

enum WeatherError: LocalizedError {
    case permissionDenied
    case locationUnavailable
    case network
    case badResponse

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "没有定位权限"
        case .locationUnavailable: return "暂时拿不到位置"
        case .network: return "网络不可用"
        case .badResponse: return "天气数据解析失败"
        }
    }
}

enum WeatherService {
    /// 一次完整流程：取一次定位 → Open-Meteo 当前气温 → 反查城市名（仅用于界面显示，不存储）。
    static func currentWeather() async throws -> WeatherSnapshot {
        let location = try await LocationProvider.shared.currentLocation()
        let temperature = try await fetchTemperature(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        let city = await cityName(for: location)
        return WeatherSnapshot(temperature: Int(temperature.rounded()), cityName: city, fetchedAt: Date())
    }

    // MARK: - Open-Meteo（免费、无需 key）

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
        }
        let current: Current
    }

    private static func fetchTemperature(latitude: Double, longitude: Double) async throws -> Double {
        // 坐标降精度到 0.01°，城市级别足够，也减少位置可识别性
        let lat = (latitude * 100).rounded() / 100
        let lon = (longitude * 100).rounded() / 100

        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else {
            throw WeatherError.badResponse
        }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", lon)),
            URLQueryItem(name: "current", value: "temperature_2m"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { throw WeatherError.badResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WeatherError.network
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WeatherError.badResponse
        }
        guard let decoded = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data) else {
            throw WeatherError.badResponse
        }
        return decoded.current.temperature_2m
    }

    /// 只把城市名显示在界面上，不写数据库、不写文件。失败不阻塞气温展示。
    private static func cityName(for location: CLLocation) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                if let placemark = placemarks?.first {
                    continuation.resume(
                        returning: placemark.locality
                            ?? placemark.subAdministrativeArea
                            ?? placemark.administrativeArea
                    )
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - 单次定位

/// 注意：CLLocationManager 在主线程创建、主线程回调；
/// 本类只在 TodayView 的 MainActor 上下文调用，一次只处理一个请求。
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var finished = false

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation(timeout: TimeInterval = 12) async throws -> CLLocation {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            throw WeatherError.permissionDenied
        }
        precondition(continuation == nil, "一次只允许一个定位请求")

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            self.continuation = continuation
            self.finished = false

            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.fail(WeatherError.locationUnavailable)
            }
        }
    }

    private func succeed(_ location: CLLocation) {
        guard !finished, let continuation = continuation else { return }
        finished = true
        self.continuation = nil
        continuation.resume(returning: location)
    }

    private func fail(_ error: Error) {
        guard !finished, let continuation = continuation else { return }
        finished = true
        self.continuation = nil
        continuation.resume(throwing: error)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            fail(WeatherError.permissionDenied)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        succeed(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fail(WeatherError.locationUnavailable)
    }
}
