import EventKit

/// 镜像待办到系统"提醒事项"的"闪拾"清单。
/// 优先选择 iCloud (CalDAV) 源，从而自动同步到 iPhone；没有 iCloud 时落到本地源。
final class RemindersMirror {
  static let shared = RemindersMirror()
  static let listName = "闪拾"

  private let store = EKEventStore()

  static func permissionGranted() -> Bool {
    if #available(macOS 14.0, *) {
      return EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    } else {
      return EKEventStore.authorizationStatus(for: .reminder) == .authorized
    }
  }

  func requestAccess(_ done: @escaping (Bool) -> Void) {
    if #available(macOS 14.0, *) {
      store.requestFullAccessToReminders { granted, _ in
        DispatchQueue.main.async { done(granted) }
      }
    } else {
      store.requestAccess(to: .reminder) { granted, _ in
        DispatchQueue.main.async { done(granted) }
      }
    }
  }

  private func ensureAccess(_ then: @escaping (Bool) -> Void) {
    if Self.permissionGranted() {
      then(true)
      return
    }
    requestAccess { granted in
      then(granted)
    }
  }

  private func flashpickCalendar() -> EKCalendar? {
    let calendars = store.calendars(for: .reminder)
    if let existing = calendars.first(where: { $0.title == Self.listName }) {
      return existing
    }
    let sources = store.sources
    let source =
      sources.first {
        $0.sourceType == .calDAV
          && ($0.title.localizedCaseInsensitiveContains("icloud")
            || $0.sourceIdentifier.lowercased().contains("icloud"))
      }
      ?? sources.first { $0.sourceType == .calDAV }
      ?? sources.first { $0.sourceType == .local }
    guard let source else { return nil }
    let calendar = EKCalendar(for: .reminder, eventStore: store)
    calendar.title = Self.listName
    calendar.source = source
    do {
      try store.saveCalendar(calendar, commit: true)
      return calendar
    } catch {
      NSLog("[FlashPick] create mirror calendar failed: %@", error.localizedDescription)
      return nil
    }
  }

  /// 新建镜像，回调返回 calendarItemExternalIdentifier。
  func addReminder(text: String, notes: String?, done: @escaping (String?) -> Void) {
    ensureAccess { [weak self] granted in
      guard let self, granted else {
        done(nil)
        return
      }
      guard let calendar = self.flashpickCalendar() else {
        done(nil)
        return
      }
      let reminder = EKReminder(eventStore: self.store)
      reminder.calendar = calendar
      reminder.title = String(text.prefix(1000))
      reminder.notes = notes
      do {
        try self.store.save(reminder, commit: true)
        // 用 calendarItemIdentifier：与 calendarItem(withIdentifier:) 查询配对
        done(reminder.calendarItemIdentifier)
      } catch {
        NSLog("[FlashPick] mirror save failed: %@", error.localizedDescription)
        done(nil)
      }
    }
  }

  func setCompleted(externalID: String, completed: Bool) {
    ensureAccess { [weak self] granted in
      guard let self, granted else { return }
      guard let item = self.store.calendarItem(withIdentifier: externalID),
            let reminder = item as? EKReminder
      else { return }
      reminder.isCompleted = completed
      reminder.completionDate = completed ? Date() : nil
      try? self.store.save(reminder, commit: true)
    }
  }

  func delete(externalID: String) {
    ensureAccess { [weak self] granted in
      guard let self, granted else { return }
      guard let item = self.store.calendarItem(withIdentifier: externalID),
            let reminder = item as? EKReminder
      else { return }
      try? self.store.remove(reminder, commit: true)
    }
  }
}
