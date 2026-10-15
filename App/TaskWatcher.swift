import Foundation

// 后台任务监控：退后台后每 20s 轮询电脑 /api/all_tasks，
// 任务从「运行中」变「完成/出错」时弹本地通知（借鉴 ZCodeMobile 的 MonitorController 思路，
// 数据源换成 Pocket 自己的合并任务接口）。
final class TaskWatcher {
    static let shared = TaskWatcher()

    private var timer: Timer?
    // taskKey(serviceId/jobId) -> 映射后的状态
    private var known: [String: String] = [:]
    private var loaded = false
    private static let runningStates: Set<String> = ["running", "waiting"]

    func start() {
        guard timer == nil, AppSettings.isValid else { return }
        if loaded == false { preloadOnce() }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 冷启动只记录不弹：App 重启后不会把历史任务轰炸一遍
    private func preloadOnce() {
        loaded = true
        poll(silent: true)
    }

    private func poll(silent: Bool = false) {
        let api = AppSettings.tasksAPI
        guard let url = URL(string: api) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tasks = obj["tasks"] as? [[String: Any]] else { return }
            DispatchQueue.global().async { self.merge(tasks: tasks, silent: silent) }
        }.resume()
    }

    private func merge(tasks: [[String: Any]], silent: Bool) {
        for t in tasks {
            let key = (t["sessionId"] as? String) ?? (t["jobId"] as? String) ?? ""
            guard !key.isEmpty else { continue }
            let status = (t["status"] as? String) ?? ""
            let title = (t["title"] as? String) ?? (t["prompt"] as? String) ?? "未命名任务"
            let prev = known[key]
            known[key] = status
            guard !silent, let prev else { continue }
            guard Self.runningStates.contains(prev), status == "done" || status == "error" else { continue }
            let body = String(title.prefix(120))
            if status == "done" {
                LocalNotify.fire(title: "✅ ZCode 任务完成", body: body, taskId: key)
            } else {
                LocalNotify.fire(title: "❌ ZCode 任务出错", body: body, taskId: key)
            }
        }
    }
}
